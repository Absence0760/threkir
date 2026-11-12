-- First-touch sign-up source (decisions § 2350).
--
-- The social accounts send people to threkir.com, and the owner wants to know
-- which platform each new account came from, without a third-party analytics
-- vendor, a new cookie or a new paid service.
--
-- 1. The gate. Recording where a person came from is new processing, so the
--    whole path is fail-closed behind a 'signup_source' row in
--    private.feature_flags that NO MIGRATION WRITES. It waits on the CISO /
--    Security Analyst review in docs/ops/deployment.md (§ 150); seed.sql opens
--    it for local + CI. While it is closed the web client sends nothing and
--    the trigger records nothing.
--
-- 2. The capture is client-side. The web app's root layout keeps the tab's
--    first touch in sessionStorage (utm_source / utm_medium / utm_campaign
--    when present, else the referrer's host mapped to a platform name, else
--    'direct'), and the sign-up sends it as `signup_source` GoTrue metadata:
--    with signUp for email, with updateUser on an OAuth account's first
--    callback. Nothing is sent for a visitor who does not sign up.
--
-- 3. private.signup_sources: one row per account, written by the auth.users
--    trigger when the account is confirmed (or, for OAuth, when the metadata
--    is written after the first callback), once per account and only within a
--    day of its creation. Private schema, RLS on, every client grant revoked:
--    no user can read any row, their own included. Goes with the account by
--    FK cascade. Every value is checked before the insert, so a malformed
--    value is dropped rather than failing the confirmation it rides on.
--
-- 4. private.signup_sources_daily: confirmed sign-ups per UTC day per source,
--    'unknown' for an account with no row (mobile sign-ups, sign-ups before
--    the gate opened, browsers that refuse storage). For the owner in the SQL
--    editor; not exposed to the API.
--
-- Locks: a new private table, view, functions and triggers (catalogue only).
-- The auth.users triggers take a brief catalogue lock and scan nothing.

-- ── 1. The gate ─────────────────────────────────────────────────────────────

create or replace function private.signup_source_enabled()
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select coalesce(
    (select f.enabled from private.feature_flags f where f.name = 'signup_source'),
    false
  );
$$;

revoke execute on function private.signup_source_enabled() from public, anon, authenticated;
grant execute on function private.signup_source_enabled() to service_role;

create or replace function public.signup_source_enabled()
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select private.signup_source_enabled();
$$;

revoke execute on function public.signup_source_enabled() from public;
grant execute on function public.signup_source_enabled() to anon, authenticated, service_role;

comment on function public.signup_source_enabled() is
  'Whether first-touch sign-up source recording is live (decisions § 2350). '
  'The web sign-up sends no signup_source metadata when false.';

-- ── 2. The table ────────────────────────────────────────────────────────────

create table private.signup_sources (
  user_id       uuid primary key references auth.users (id) on delete cascade,
  source        text not null check (source ~ '^[a-z0-9][a-z0-9._-]{0,63}$'),
  medium        text check (medium ~ '^[a-z0-9][a-z0-9._-]{0,63}$'),
  campaign      text check (campaign ~ '^[a-z0-9][a-z0-9._-]{0,63}$'),
  referrer_host text check (referrer_host ~ '^[a-z0-9.-]{1,253}$'),
  created_at    timestamptz not null default now()
);

create index signup_sources_created_at_idx on private.signup_sources (created_at);

comment on table private.signup_sources is
  'Where each account first arrived from: utm_source (or the referrer''s '
  'platform, or direct / other), utm_medium, utm_campaign and the referrer '
  'host (decisions § 2350). Written once per account by the auth.users '
  'trigger; unreadable by any client role.';

alter table private.signup_sources enable row level security;
revoke all on table private.signup_sources from public, anon, authenticated;

-- ── 3. The trigger ──────────────────────────────────────────────────────────

create or replace function private.record_signup_source()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_src jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb) -> 'signup_source';
  v_token constant text := '^[a-z0-9][a-z0-9._-]{0,63}$';
  v_source text;
  v_medium text;
  v_campaign text;
  v_host text;
begin
  if new.email_confirmed_at is null
     or jsonb_typeof(v_src) is distinct from 'object'
     or coalesce(new.created_at, now()) < now() - interval '1 day'
     or not private.signup_source_enabled() then
    return new;
  end if;

  -- jsonb_typeof first: ->> renders a number or boolean as text that would
  -- pass the pattern.
  v_source := case when jsonb_typeof(v_src -> 'source') = 'string'
                    and (v_src ->> 'source') ~ v_token then v_src ->> 'source' end;
  if v_source is null then
    return new;
  end if;
  v_medium := case when jsonb_typeof(v_src -> 'medium') = 'string'
                    and (v_src ->> 'medium') ~ v_token then v_src ->> 'medium' end;
  v_campaign := case when jsonb_typeof(v_src -> 'campaign') = 'string'
                      and (v_src ->> 'campaign') ~ v_token then v_src ->> 'campaign' end;
  v_host := case when jsonb_typeof(v_src -> 'referrer_host') = 'string'
                  and (v_src ->> 'referrer_host') ~ '^[a-z0-9.-]{1,253}$' then v_src ->> 'referrer_host' end;

  begin
    insert into private.signup_sources (user_id, source, medium, campaign, referrer_host)
    values (new.id, v_source, v_medium, v_campaign, v_host)
    on conflict (user_id) do nothing;
  exception when others then
    -- Attribution must never fail the confirmation or sign-in it rides on.
    raise warning 'record_signup_source: % (%)', sqlerrm, sqlstate;
  end;

  return new;
end;
$$;

revoke execute on function private.record_signup_source() from public, anon, authenticated;

comment on function private.record_signup_source() is
  'Records a confirmed account''s signup_source metadata in '
  'private.signup_sources; once per account, within a day of creation, behind '
  'the signup_source gate. decisions § 2350.';

-- Email sign-up with confirmation off: confirmed at insert.
create trigger auth_users_record_signup_source_on_insert
  after insert on auth.users
  for each row
  when (new.email_confirmed_at is not null and new.raw_user_meta_data ? 'signup_source')
  execute function private.record_signup_source();

-- Email sign-up: the confirmation link.
create trigger auth_users_record_signup_source_on_confirm
  after update of email_confirmed_at on auth.users
  for each row
  when (old.email_confirmed_at is null and new.email_confirmed_at is not null
        and new.raw_user_meta_data ? 'signup_source')
  execute function private.record_signup_source();

-- OAuth sign-up: no metadata at insert, so the callback writes it with
-- updateUser on the account's first sign-in.
create trigger auth_users_record_signup_source_on_metadata
  after update of raw_user_meta_data on auth.users
  for each row
  when (new.raw_user_meta_data ? 'signup_source'
        and (old.raw_user_meta_data -> 'signup_source')
            is distinct from (new.raw_user_meta_data -> 'signup_source'))
  execute function private.record_signup_source();

-- ── 4. The owner's view ─────────────────────────────────────────────────────

create view private.signup_sources_daily as
select (u.created_at at time zone 'utc')::date as day,
       coalesce(s.source, 'unknown') as source,
       count(*)::int as signups
  from auth.users u
  left join private.signup_sources s on s.user_id = u.id
 where u.email_confirmed_at is not null
 group by 1, 2;

revoke all on private.signup_sources_daily from public, anon, authenticated;
grant select on private.signup_sources_daily to service_role;

comment on view private.signup_sources_daily is
  'Confirmed sign-ups per UTC day per first-touch source; ''unknown'' for an '
  'account with no recorded source. Read in the SQL editor (decisions § 2350).';

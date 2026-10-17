-- Subscribable training-plan calendar feed (issue #1186 § Workouts off the
-- phone; docs/features/training.md § Calendar feed; decisions — see the entry that
-- names this migration).
--
-- A calendar client (Google, Apple, Outlook) subscribes to a URL and polls it;
-- it cannot send a bearer header, so the URL itself carries the credential.
-- That makes the token a privacy surface, and the table below is shaped by it:
--
--   * One feed per user (`user_id` unique). Rotating replaces the row's id
--     AND secret, so the old URL stops working the moment a new one exists;
--     revoking deletes the row.
--   * The token handed to the client is `<id as 32 hex><secret as 64 hex>`.
--     The id is a lookup selector; the secret is 32 random bytes and only its
--     SHA-256 is stored. A leaked table therefore yields no working URL, and
--     the Edge Function compares the hash in constant time after an indexed
--     lookup by id — the comparison never runs inside a btree scan.
--   * `last_fetched_at` is the one thing the owner learns about use: when a
--     calendar last pulled the feed, stamped at most once an hour so a client
--     polling every few minutes is not a write per poll. It is the signal that
--     a URL the owner forgot about is still being read.
--   * No client role holds any grant on the table. The owner reads its two
--     timestamps through plan_calendar_feed_status(), rotates and revokes
--     through the two RPCs below, and the feed body is read only by the Edge
--     Function as the service role.
--
-- What the feed carries is decided here, by the projection in
-- `plan_calendar_feed_events`: the ACTIVE plan's non-rest workouts, each as
-- its id, date, kind and prescribed target. No notes, no race name, no plan
-- name, no route, no location of any kind, nothing from any other plan.
--
-- Online-safety: a new table and new functions; nothing existing is locked
-- or rewritten, so docs/backend/migration_locks.md does not apply.

create table public.plan_calendar_feeds (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users (id) on delete cascade,
  secret_hash bytea not null check (octet_length(secret_hash) = 32),
  created_at timestamptz not null default now(),
  last_fetched_at timestamptz
);

comment on table public.plan_calendar_feeds is
  'One subscribable .ics feed per user. Only the SHA-256 of the URL secret is stored; '
  'rotate_plan_calendar_feed / revoke_plan_calendar_feed are the only writers.';

alter table public.plan_calendar_feeds enable row level security;

-- No client role holds any grant on the table, the same posture as
-- apple_sign_in_tokens: the owner learns whether a feed exists, and when it
-- was made and last read, through plan_calendar_feed_status() below, which
-- returns those two timestamps and nothing else. A column-level SELECT grant
-- would have done the same job with one more place for a future column to
-- leak from. RLS stays enabled with no policy, so a grant added by mistake
-- still returns no rows.
revoke all on public.plan_calendar_feeds from public, anon, authenticated;
grant select, insert, update, delete on public.plan_calendar_feeds to service_role;

-- ─────────────────── status ───────────────────

-- The caller's feed, as the two timestamps the Settings card shows. Zero rows
-- when there is no feed.
create or replace function public.plan_calendar_feed_status()
returns table (created_at timestamptz, last_fetched_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select f.created_at, f.last_fetched_at
    from public.plan_calendar_feeds f
   where f.user_id = auth.uid()
$$;

revoke execute on function public.plan_calendar_feed_status() from public, anon;
grant execute on function public.plan_calendar_feed_status() to authenticated, service_role;

-- ─────────────────── rotate / create ───────────────────

-- Mints a new token for the caller, replacing any existing feed. Returns the
-- token exactly once; nothing can read it back afterwards.
create or replace function public.rotate_plan_calendar_feed()
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid := gen_random_uuid();
  v_secret text := encode(extensions.gen_random_bytes(32), 'hex');
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  perform public.enforce_create_rate_limit('plan_calendar_rotate', v_uid, 20, 3600);

  insert into public.plan_calendar_feeds (id, user_id, secret_hash, created_at, last_fetched_at)
  values (v_id, v_uid, sha256(convert_to(v_secret, 'UTF8')), now(), null)
  on conflict (user_id) do update
    set id = excluded.id,
        secret_hash = excluded.secret_hash,
        created_at = excluded.created_at,
        last_fetched_at = null;

  return replace(v_id::text, '-', '') || v_secret;
end;
$$;

revoke execute on function public.rotate_plan_calendar_feed() from public, anon;
grant execute on function public.rotate_plan_calendar_feed() to authenticated, service_role;

-- ─────────────────── revoke ───────────────────

-- Deletes the caller's feed. True when one existed.
create or replace function public.revoke_plan_calendar_feed()
returns boolean
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_count integer;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  delete from public.plan_calendar_feeds where user_id = v_uid;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

revoke execute on function public.revoke_plan_calendar_feed() from public, anon;
grant execute on function public.revoke_plan_calendar_feed() to authenticated, service_role;

-- ─────────────────── feed body (service role only) ───────────────────

-- The feed document for an already-authenticated feed id: the owner's display
-- unit and language, and the active plan's non-rest workouts. Called by the
-- plan-calendar Edge Function only after it has matched the URL secret
-- against `secret_hash`; null when the feed no longer exists (revoked or
-- rotated between the two reads). Stamps `last_fetched_at` at most hourly.
create or replace function public.plan_calendar_feed_events(p_feed_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_unit text;
  v_locale text;
  v_workouts jsonb;
begin
  select user_id into v_uid from public.plan_calendar_feeds where id = p_feed_id;
  if v_uid is null then
    return null;
  end if;

  update public.plan_calendar_feeds
     set last_fetched_at = now()
   where id = p_feed_id
     and (last_fetched_at is null or last_fetched_at < now() - interval '1 hour');

  select s.prefs ->> 'locale',
         coalesce(nullif(s.prefs ->> 'preferred_unit', ''), p.preferred_unit)
    into v_locale, v_unit
    from public.user_profiles p
    left join public.user_settings s on s.user_id = p.id
   where p.id = v_uid;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', w.id,
           'date', w.scheduled_date,
           'kind', w.kind,
           'target_distance_m', w.target_distance_m,
           'target_duration_seconds', w.target_duration_seconds,
           'target_pace_sec_per_km', w.target_pace_sec_per_km,
           'target_pace_end_sec_per_km', w.target_pace_end_sec_per_km,
           'target_pace_tolerance_sec', w.target_pace_tolerance_sec
         ) order by w.scheduled_date, w.id), '[]'::jsonb)
    into v_workouts
    from public.training_plans tp
    join public.plan_weeks pw on pw.plan_id = tp.id
    join public.plan_workouts w on w.week_id = pw.id
   where tp.user_id = v_uid
     and tp.status = 'active'
     and not tp.is_template
     and w.kind <> 'rest';

  return jsonb_build_object(
    'unit', case when v_unit = 'mi' then 'mi' else 'km' end,
    'locale', v_locale,
    'workouts', v_workouts
  );
end;
$$;

revoke execute on function public.plan_calendar_feed_events(uuid) from public, anon, authenticated;
grant execute on function public.plan_calendar_feed_events(uuid) to service_role;

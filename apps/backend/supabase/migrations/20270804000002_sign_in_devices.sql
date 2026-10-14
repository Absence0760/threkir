-- New-device sign-in alerts: remember which coarse device classes have signed
-- in to each account, and enqueue a `security_email` (template
-- `new_device_sign_in`) the first time a class appears on an account that
-- already had one. docs/features/email.md § Security emails; the privacy
-- design is decisions R10MAIL-2.
--
-- What "device" means here, and what is deliberately NOT kept:
--
--   * A device is a (browser family, platform family) PAIR derived from the
--     session's User-Agent by the two classifiers below — "firefox"/"linux",
--     "threkir_app"/"other". Nothing finer. No browser version, no OS
--     version, no device model, and never the raw User-Agent: the classes are
--     computed inside the trigger and only the two enum values are written.
--   * The session's IP address is never read. GoTrue keeps it on its own
--     auth.sessions row under its own retention; this table copies nothing
--     from it, and the email names no location.
--   * The classes are stored in the clear, not hashed. Hashing a value drawn
--     from ~60 combinations hides nothing — anyone holding the table can
--     hash all sixty — so a hash would be a privacy claim the design cannot
--     back. The honest protection is that the values are coarse.
--
-- When it fires: the triggers sit on auth.sessions, which GoTrue inserts once
-- per SIGN-IN (password, OTP, magic link, OAuth, SSO) and only UPDATEs on a
-- token refresh. So a refresh is never a sign-in here by construction. The
-- second trigger covers a session whose user_agent GoTrue fills in after the
-- insert rather than on it: the first time it becomes known is evaluated as
-- the sign-in, and every later refresh — which rewrites user_agent with the
-- same value — is excluded by the WHEN clause.
--
-- Who is not emailed:
--
--   * The first-ever sign-in on an account (no row exists for the user yet):
--     that session becomes the baseline silently, so signing up — which signs
--     the new user straight in — never mails "a new device signed in".
--   * An anonymous user (no address, no account to protect).
--   * A recipient who set `email_new_device_alerts = 'off'` — gated in the
--     worker at send time, not here, so the device is still recorded and
--     turning the alert back on does not mail about devices already seen.
--
-- Layered resilience: a fault in this bookkeeping must never fail a sign-in,
-- so the trigger body traps every error and returns. Losing one alert is the
-- worst case; losing the session would be an outage of sign-in itself.

-- ─────────────────── 1. classifiers ───────────────────

-- The mobile apps reach GoTrue through supabase_flutter over dart:io, whose
-- default User-Agent is `Dart/<version> (dart:io)` with no OS in it, so the
-- app is its own browser class and its platform reads `other`. Order matters
-- in both: Edge and Opera carry `Chrome/`, Chrome carries `Safari/`, and
-- Android carries `Linux`.
create or replace function public.sign_in_browser_class(p_ua text)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when p_ua is null or btrim(p_ua) = '' then 'other'
    when p_ua ~ '^Dart/' then 'threkir_app'
    when p_ua ~ 'Edg(e|A|iOS)?/' then 'edge'
    when p_ua ~ '(OPR|Opera)/' then 'opera'
    when p_ua ~ 'SamsungBrowser/' then 'samsung'
    when p_ua ~ '(Firefox|FxiOS)/' then 'firefox'
    when p_ua ~ '(Chrome|CriOS|Chromium)/' then 'chrome'
    when p_ua ~ 'Safari/' and p_ua ~ 'Version/' then 'safari'
    else 'other'
  end
$$;

create or replace function public.sign_in_platform_class(p_ua text)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when p_ua is null or btrim(p_ua) = '' then 'other'
    when p_ua ~ 'Android' then 'android'
    when p_ua ~ '(iPhone|iPad|iPod)' then 'ios'
    when p_ua ~ 'CrOS' then 'chromeos'
    when p_ua ~ 'Windows' then 'windows'
    when p_ua ~ '(Macintosh|Mac OS X)' then 'macos'
    when p_ua ~ 'Linux' then 'linux'
    else 'other'
  end
$$;

revoke execute on function public.sign_in_browser_class(text) from public, anon, authenticated;
revoke execute on function public.sign_in_platform_class(text) from public, anon, authenticated;
grant execute on function public.sign_in_browser_class(text) to service_role;
grant execute on function public.sign_in_platform_class(text) to service_role;

-- ─────────────────── 2. sign_in_devices ───────────────────

create table public.sign_in_devices (
  user_id uuid not null references auth.users (id) on delete cascade,
  browser text not null check (browser in ('chrome', 'edge', 'firefox', 'safari', 'opera', 'samsung', 'threkir_app', 'other')),
  platform text not null check (platform in ('android', 'ios', 'windows', 'macos', 'linux', 'chromeos', 'other')),
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  primary key (user_id, browser, platform)
);

comment on table public.sign_in_devices is
  'Coarse (browser family, platform family) classes that have signed in to '
  'each account, kept to detect a sign-in from a class not seen before '
  '(security_email new_device_sign_in). No raw User-Agent, no IP. Pruned '
  'after 180 days unseen, never below one row per user (prune_sign_in_devices).';

alter table public.sign_in_devices enable row level security;

-- The owner may read their own classes (they are personal data about them,
-- and ship in the Art 20 export). There is no client write surface at all:
-- the rows are written only by the SECURITY DEFINER trigger and the prune,
-- so a client cannot pre-register a class to silence a future alert.
create policy "sign_in_devices: owner reads own"
  on public.sign_in_devices
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

grant select on public.sign_in_devices to authenticated;
grant select, insert, update, delete on public.sign_in_devices to service_role;

-- ─────────────────── 3. the sign-in trigger ───────────────────

create or replace function public.record_sign_in_device()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_browser text;
  v_platform text;
  v_had_baseline boolean;
  v_inserted integer;
begin
  begin
    if exists (
      select 1 from auth.users u
       where u.id = new.user_id and coalesce(u.is_anonymous, false)
    ) then
      return new;
    end if;

    v_browser := sign_in_browser_class(new.user_agent);
    v_platform := sign_in_platform_class(new.user_agent);
    v_had_baseline := exists (
      select 1 from sign_in_devices d where d.user_id = new.user_id
    );

    insert into sign_in_devices (user_id, browser, platform)
    values (new.user_id, v_browser, v_platform)
    on conflict (user_id, browser, platform) do nothing;
    get diagnostics v_inserted = row_count;

    if v_inserted = 0 then
      update sign_in_devices
         set last_seen_at = now()
       where user_id = new.user_id
         and browser = v_browser
         and platform = v_platform;
    elsif v_had_baseline then
      insert into jobs (kind, payload)
      values (
        'security_email',
        jsonb_build_object(
          'user_id', new.user_id::text,
          'template', 'new_device_sign_in',
          'browser', v_browser,
          'platform', v_platform,
          'signed_in_at', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
        )
      );
    end if;
  exception when others then
    -- SQLSTATE only: the message text can carry row values (PII rule).
    raise warning 'record_sign_in_device failed: %', sqlstate;
  end;
  return new;
end;
$$;

revoke execute on function public.record_sign_in_device() from public, anon, authenticated;

create trigger sessions_record_sign_in_device
  after insert on auth.sessions
  for each row
  when (new.user_agent is not null)
  execute function public.record_sign_in_device();

create trigger sessions_record_sign_in_device_late_ua
  after update of user_agent on auth.sessions
  for each row
  when (old.user_agent is null and new.user_agent is not null)
  execute function public.record_sign_in_device();

-- ─────────────────── 4. baseline backfill ───────────────────

-- Every account with a live session gets its current classes as a silent
-- baseline, so detection works from the first sign-in after deploy rather
-- than spending each existing account's next sign-in on becoming a baseline.
-- `sign_in_devices` is new and empty, so this takes no lock anyone waits on;
-- auth.sessions is only read.
insert into public.sign_in_devices (user_id, browser, platform, first_seen_at, last_seen_at)
select s.user_id,
       public.sign_in_browser_class(s.user_agent),
       public.sign_in_platform_class(s.user_agent),
       coalesce(min(s.created_at), now()),
       coalesce(max(greatest(s.created_at, s.updated_at)), now())
  from auth.sessions s
  join auth.users u on u.id = s.user_id
 where s.user_agent is not null
   and not coalesce(u.is_anonymous, false)
 group by 1, 2, 3
on conflict do nothing;

-- ─────────────────── 5. retention ───────────────────

-- A class unseen for 180 days stops counting as known, so a long-abandoned
-- laptop that signs in again is reported. Two rules keep that honest:
--
--   * `last_seen_at` is first refreshed from auth.sessions, because a session
--     that stays signed in for months only REFRESHES — it never inserts a
--     session row — and without this a phone used every day would be pruned
--     and mail "new device" the next time it signed in.
--   * The user's most recently seen class is never deleted. An account with
--     no rows reads as "first-ever sign-in" to the trigger, which stays
--     silent — so pruning an account to zero would turn the alert off for
--     exactly the dormant account an attacker most wants.
create or replace function public.prune_sign_in_devices()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  update sign_in_devices d
     set last_seen_at = live.seen_at
    from (
      select s.user_id,
             sign_in_browser_class(s.user_agent) as browser,
             sign_in_platform_class(s.user_agent) as platform,
             max(greatest(s.created_at, s.updated_at)) as seen_at
        from auth.sessions s
       where s.user_agent is not null
       group by 1, 2, 3
    ) live
   where d.user_id = live.user_id
     and d.browser = live.browser
     and d.platform = live.platform
     and live.seen_at > d.last_seen_at;

  delete from sign_in_devices d
   where d.last_seen_at < now() - interval '180 days'
     and exists (
       select 1 from sign_in_devices newer
        where newer.user_id = d.user_id
          and newer.last_seen_at > d.last_seen_at
     );
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.prune_sign_in_devices() from public, anon, authenticated;
grant execute on function public.prune_sign_in_devices() to service_role;

select cron.schedule(
  'prune-sign-in-devices',
  '23 4 * * *',
  $$select public.prune_sign_in_devices()$$
);

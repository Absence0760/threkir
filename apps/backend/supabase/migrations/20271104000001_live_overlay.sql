-- Streamer overlay (issue #1273 item 3, decisions § 2265).
--
-- A creator adds a transparent page to OBS as a browser source. It shows their
-- live distance, pace, elapsed time, optionally heart rate and a mini-map,
-- read through a revocable token rather than the public live link, so a run
-- can be streamed without being public.
--
-- 1. private.live_overlay_tokens: ONE token per user, not per run. A browser
--    source is set up once, and a per-run token would put a fresh URL into
--    OBS on every run, typed in after the run has already started. The token
--    resolves to the owner's current live stub at read time. Like
--    private.challenge_invite_tokens (§ 2261) it is plaintext in the
--    unexposed schema, because the owner copies it again from another device
--    (set up on the phone, pasted on the streaming PC); no client role holds a
--    grant, and the definer RPCs below are the only path to it.
--
-- 2. What the token admits is decided here, not by the page:
--      * delay_s: pings are returned only once they are older than this many
--        seconds. A delay applied in the browser hides nothing, since the page
--        would already hold the fresh rows.
--      * show_map: coordinates are returned only when on (default off). With
--        it off the overlay gets distance, time and pace and no location.
--      * show_heart_rate: bpm only when on AND live_heart_rate_admitted().
--    Pings are clipped to the owner's privacy zones when they are written
--    (live_run_pings_drop_in_zone, 20260618_001 + 20270121_001); the coarse
--    last-seen carve-out row keeps its odometer but never its coordinates.
--
-- 3. Heart rate on any live surface. bpm is Art 9 health data. Until now
--    live_run_pings stored it on every ping and RLS handed it to anyone who
--    could read a public live run. A BEFORE INSERT trigger now stores it only
--    for an owner with health_data_consent_at on record (the rule the other
--    third-party heart-rate reads use, e.g. the coach roster's HR drift) and
--    while the gate is open. The Go live hub asks the same question through
--    live_heart_rate_shared() before it fans a ping out.
--
-- 4. The gate. Broadcasting live location and heart rate to an audience is a
--    CISO / Security Analyst sign-off (docs/ops/deployment.md, § 150), so
--    everything new is fail-closed behind a `live_overlay` row of
--    private.feature_flags that NO MIGRATION WRITES. seed.sql opens it for
--    local + CI. While it is closed the feed returns nothing, no token can be
--    made or configured, and no ping keeps its bpm. Revoking always works.
--
-- 5. The feed's cursor is live_run_pings.at, so `at` has to be the time the
--    row arrived. Every writer in the tree already leaves it to the column
--    default; a client that wrote an older one would put its ping behind a
--    cursor the overlay had already passed, and it would never be shown. A
--    BEFORE INSERT trigger stamps `at := now()` on every anon / authenticated
--    write. The service role (the live hub, e2e fixtures) and the table owner
--    (pgTAP, cron) keep the `at` they write.
--
-- Locks: a new table in the private schema, function creation, and CREATE
-- TRIGGER on live_run_pings (SHARE ROW EXCLUSIVE for the catalogue write
-- only). No populated table is rewritten or scanned.

create table private.live_overlay_tokens (
  user_id         uuid primary key references auth.users(id) on delete cascade,
  token           text not null unique,
  delay_s         integer not null default 60 check (delay_s between 0 and 900),
  show_map        boolean not null default false,
  show_heart_rate boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

comment on table private.live_overlay_tokens is
  'One revocable streamer-overlay token per user, plus what it admits: the '
  'server-side delay, the map and heart rate (decisions § 2265). Reached only '
  'through the definer RPCs.';

alter table private.live_overlay_tokens enable row level security;
revoke all on table private.live_overlay_tokens from public, anon, authenticated;

-- ─────────────────── the gate ───────────────────

create or replace function private.live_overlay_enabled()
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select coalesce(
    (select f.enabled from private.feature_flags f where f.name = 'live_overlay'),
    false
  );
$$;

revoke execute on function private.live_overlay_enabled() from public, anon, authenticated;
grant execute on function private.live_overlay_enabled() to service_role;

create or replace function public.live_overlay_enabled()
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select private.live_overlay_enabled();
$$;

revoke execute on function public.live_overlay_enabled() from public;
grant execute on function public.live_overlay_enabled() to anon, authenticated, service_role;

comment on function public.live_overlay_enabled() is
  'Whether the streamer overlay and live heart rate are live (decisions § 2265). '
  'Clients hide both surfaces when false.';

-- ─────────────────── heart rate on live surfaces ───────────────────

create or replace function private.live_heart_rate_admitted(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select p_user_id is not null
     and private.live_overlay_enabled()
     and exists (
       select 1 from user_profiles p
        where p.id = p_user_id
          and p.health_data_consent_at is not null
     );
$$;

revoke execute on function private.live_heart_rate_admitted(uuid) from public, anon, authenticated;
grant execute on function private.live_heart_rate_admitted(uuid) to service_role;

-- The Go live hub's question, asked as the service role before it publishes a
-- ping. Not callable by a client: the answer says whether a named user has
-- given health-data consent.
create or replace function public.live_heart_rate_shared(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select private.live_heart_rate_admitted(p_user_id);
$$;

revoke execute on function public.live_heart_rate_shared(uuid) from public, anon, authenticated;
grant execute on function public.live_heart_rate_shared(uuid) to service_role;

comment on function public.live_heart_rate_shared(uuid) is
  'Whether a live ping from this user may carry bpm: the live_overlay gate is '
  'open and the user has health_data_consent_at on record. Service role only '
  '(the live hub); decisions § 2265.';

create or replace function private.live_run_pings_strip_bpm()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
begin
  -- An out-of-range value is left for the column's CHECK to refuse, so a
  -- broken writer still gets its 23514 rather than a silent null.
  if new.bpm between 0 and 300 and not private.live_heart_rate_admitted(new.user_id) then
    new.bpm := null;
  end if;
  return new;
end;
$$;

revoke execute on function private.live_run_pings_strip_bpm() from public, anon, authenticated;

create trigger live_run_pings_strip_bpm_before_insert
  before insert on public.live_run_pings
  for each row execute function private.live_run_pings_strip_bpm();

-- SECURITY INVOKER on purpose: current_user is then the writing role. Under
-- DEFINER it would always be the owner.
create or replace function private.live_run_pings_stamp_at()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if current_user in ('anon', 'authenticated') then
    new.at := now();
  end if;
  return new;
end;
$$;

revoke execute on function private.live_run_pings_stamp_at() from public, anon, authenticated;

create trigger live_run_pings_stamp_at_before_insert
  before insert on public.live_run_pings
  for each row execute function private.live_run_pings_stamp_at();

-- ─────────────────── the owner's RPCs ───────────────────

create or replace function private.new_live_overlay_token()
returns text
language sql
volatile
set search_path = public, extensions
as $$
  select translate(encode(extensions.gen_random_bytes(18), 'base64'), '+/', '-_');
$$;

revoke execute on function private.new_live_overlay_token() from public, anon, authenticated;

-- The caller's overlay: its token and what it admits, plus whether the
-- caller has health-data consent on record, so the heart-rate control can say
-- why it is off before a write is refused. Zero rows when there is none or
-- the gate is closed.
create or replace function public.get_live_overlay()
returns table (
  token              text,
  delay_s            integer,
  show_map           boolean,
  show_heart_rate    boolean,
  created_at         timestamptz,
  heart_rate_consent boolean
)
language sql
stable
security definer
set search_path = public, private
as $$
  select t.token, t.delay_s, t.show_map, t.show_heart_rate, t.created_at,
         exists (
           select 1 from user_profiles p
            where p.id = t.user_id and p.health_data_consent_at is not null
         )
    from private.live_overlay_tokens t
   where t.user_id = (select auth.uid())
     and private.live_overlay_enabled();
$$;

revoke execute on function public.get_live_overlay() from public, anon;
grant execute on function public.get_live_overlay() to authenticated, service_role;

comment on function public.get_live_overlay() is
  'The caller''s streamer-overlay token and settings; empty when none exists or '
  'the live_overlay gate is closed (decisions § 2265).';

-- Make the token, or replace it: the old URL stops working at once and the
-- settings are kept. 10 per user per hour, like the other create paths.
create or replace function public.create_live_overlay_token()
returns text
language plpgsql
volatile
security definer
set search_path = public, private
as $$
declare
  v_uid uuid := auth.uid();
  v_token text := private.new_live_overlay_token();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if not private.live_overlay_enabled() then
    raise exception 'live_overlay_disabled'
      using errcode = 'P0001',
            hint = 'The streamer overlay is not available yet.';
  end if;

  perform enforce_create_rate_limit('create_live_overlay_token', v_uid, 10, 3600);

  insert into private.live_overlay_tokens (user_id, token)
  values (v_uid, v_token)
  on conflict (user_id) do update
    set token = excluded.token, created_at = now(), updated_at = now();
  return v_token;
end;
$$;

revoke execute on function public.create_live_overlay_token() from public, anon;
grant execute on function public.create_live_overlay_token() to authenticated, service_role;

comment on function public.create_live_overlay_token() is
  'Create or replace the caller''s streamer-overlay token; a replaced URL stops '
  'working at once. Rate-limited to 10 per hour (decisions § 2265).';

-- Revoking is a narrowing, so it works with the gate closed too.
create or replace function public.revoke_live_overlay_token()
returns void
language plpgsql
volatile
security definer
set search_path = public, private
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  delete from private.live_overlay_tokens where user_id = auth.uid();
end;
$$;

revoke execute on function public.revoke_live_overlay_token() from public, anon;
grant execute on function public.revoke_live_overlay_token() to authenticated, service_role;

comment on function public.revoke_live_overlay_token() is
  'Delete the caller''s streamer-overlay token; the URL stops working at once.';

-- Heart rate can only be turned on with health-data consent on record. The
-- feed re-checks consent on every read, so withdrawing it stops bpm at once
-- whatever this column says.
create or replace function public.update_live_overlay_settings(
  p_delay_s integer,
  p_show_map boolean,
  p_show_heart_rate boolean
)
returns void
language plpgsql
volatile
security definer
set search_path = public, private
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if not private.live_overlay_enabled() then
    raise exception 'live_overlay_disabled'
      using errcode = 'P0001',
            hint = 'The streamer overlay is not available yet.';
  end if;
  if p_delay_s is null or p_delay_s < 0 or p_delay_s > 900 then
    raise exception 'delay out of range' using errcode = '22023';
  end if;
  if coalesce(p_show_heart_rate, false) and not exists (
    select 1 from user_profiles p
     where p.id = v_uid and p.health_data_consent_at is not null
  ) then
    raise exception 'health_data_consent_required'
      using errcode = '42501',
            hint = 'Heart rate can be shown only with health-data consent.';
  end if;

  update private.live_overlay_tokens
     set delay_s = p_delay_s,
         show_map = coalesce(p_show_map, false),
         show_heart_rate = coalesce(p_show_heart_rate, false),
         updated_at = now()
   where user_id = v_uid;
  if not found then
    raise exception 'no live overlay' using errcode = 'P0002';
  end if;
end;
$$;

revoke execute on function public.update_live_overlay_settings(integer, boolean, boolean) from public, anon;
grant execute on function public.update_live_overlay_settings(integer, boolean, boolean)
  to authenticated, service_role;

comment on function public.update_live_overlay_settings(integer, boolean, boolean) is
  'Set the caller''s overlay delay (0-900 s), map and heart rate. Heart rate '
  'needs health_data_consent_at (42501). Decisions § 2265.';

-- ─────────────────── the overlay's read ───────────────────

-- The pings an overlay token admits, from the owner's newest live stub that is
-- still in progress and not concluded. Only pings at least delay_s old come
-- back, so the newest a viewer can see is the one the creator chose to show.
-- Without p_since: the newest 1000 such pings, oldest first. With it: what
-- became visible after it, oldest first, which is the overlay's poll. No run
-- id or user id is returned: the token holder learns nothing it could use to
-- reach the run any other way. Zero rows covers a wrong token, no live run,
-- and a closed gate alike. Paging on `at` is sound because a client cannot
-- choose it (live_run_pings_stamp_at above).
create or replace function public.live_overlay_feed(
  p_token text,
  p_since timestamptz default null
)
returns table (
  at         timestamptz,
  elapsed_s  integer,
  distance_m double precision,
  lat        double precision,
  lng        double precision,
  bpm        integer
)
language plpgsql
stable
security definer
set search_path = public, private
as $$
declare
  v_user uuid;
  v_delay integer;
  v_map boolean;
  v_hr boolean;
  v_run uuid;
  v_cutoff timestamptz;
begin
  if p_token is null or not private.live_overlay_enabled() then
    return;
  end if;

  select t.user_id, t.delay_s, t.show_map, t.show_heart_rate
    into v_user, v_delay, v_map, v_hr
    from private.live_overlay_tokens t
   where t.token = p_token;
  if v_user is null then
    return;
  end if;
  v_hr := v_hr and private.live_heart_rate_admitted(v_user);

  select r.id into v_run
    from runs r
   where r.user_id = v_user
     and coalesce(r.metadata->>'in_progress', '') = 'true'
     and r.concluded_at is null
   order by r.started_at desc
   limit 1;
  if v_run is null then
    return;
  end if;

  v_cutoff := now() - make_interval(secs => v_delay);

  return query
    select q.at, q.elapsed_s, q.distance_m, q.lat, q.lng, q.bpm
      from (
        select p.at,
               p.elapsed_s,
               p.distance_m::double precision as distance_m,
               case when v_map and not p.coarse then p.lat end as lat,
               case when v_map and not p.coarse then p.lng end as lng,
               case when v_hr then p.bpm end as bpm
          from live_run_pings p
         where p.run_id = v_run
           and p.at <= v_cutoff
           and (p_since is null or p.at > p_since)
         order by case when p_since is null then p.at end desc,
                  case when p_since is not null then p.at end asc
         limit 1000
      ) q
     order by q.at asc;
end;
$$;

revoke execute on function public.live_overlay_feed(text, timestamptz) from public;
grant execute on function public.live_overlay_feed(text, timestamptz)
  to anon, authenticated, service_role;

comment on function public.live_overlay_feed(text, timestamptz) is
  'Privacy-clipped, server-delayed live pings for a streamer-overlay token '
  '(decisions § 2265). Coordinates only with show_map, bpm only with '
  'show_heart_rate and health-data consent. Empty when nothing is admitted.';

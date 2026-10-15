-- Recurring events expand on the wall-clock of the event's own zone
-- (decisions § 1918).
--
-- `private.is_event_occurrence` (20270807000001) and both clients read a
-- timezoned series' weekday, day-of-month and time of day on the UTC clock.
-- The organiser picked them in the event's zone (20270111_001, § 599), so a
-- Wednesday 21:30 New York series expanded to Tuesday evenings, and every
-- series in a DST zone drifted an hour across each transition. The semantics
-- the clients and this file now share:
--
--   * an occurrence is a LOCAL date in `events.timezone`: a weekday in
--     `recurrence_byday`, else starts_at's local weekday; biweekly counted in
--     local weeks from the local Monday of starts_at; monthly on starts_at's
--     local day-of-month, clamped to the month's last day;
--   * it is stamped at starts_at's local time of day. A wall-clock inside a
--     spring-forward gap moves forward by the gap (02:30 -> 03:30); one inside
--     a fall-back overlap takes the EARLIER instant (RFC 5545). Postgres's own
--     `timestamp at time zone` picks the later one, so the choice is made
--     explicitly in `private.wallclock_instant`;
--   * the occurrence on starts_at's own local date is starts_at, to the second;
--   * a zone name this database cannot resolve expands in UTC, as the clients
--     do when their runtime cannot resolve it.
--
-- A legacy series with no timezone still expands in each viewer's zone on the
-- clients and keeps its looser server rule (bounds + a whole-day offset, § 1905,
-- § 1910): there is no stored fact that would say which zone its RSVPs meant.
--
-- 1. `private.recurrence_occurrences` walks a series in a given zone and
--    `private.recurrence_is_occurrence` answers membership in O(1) (it is fed a
--    client-supplied instant). `private.event_occurrences(event, from, to)` is
--    the canonical set for one event row; a legacy series has none.
-- 2. `private.is_event_occurrence(event, instant, p_allow_legacy default true)`
--    accepts the wall-clock instant and, while the transition window is open
--    and the caller allows it, also the UTC-clock instant the old expansion
--    produced, so photos from builds already in the field keep working. Money
--    paths pass p_allow_legacy => false (20270808000041): no new order lands
--    on an instant only the old clock produces. The window is the
--    `recurrence_utc_clock_legacy` row in private.feature_flags, seeded
--    ENABLED here; absent or disabled is strict, as for every flag in that
--    table. `private.close_recurrence_wallclock_transition()` disables it and
--    refuses while a keyed row still sits on a UTC-clock-only instant.
-- 3. `private.remap_recurrence_wallclock(...)` moves every instance-keyed row
--    of a timezoned series from its UTC-clock instant to the matching
--    wall-clock one. It is CREATED HERE AND NEVER CALLED: it runs only when an
--    operator calls it after the owner has read
--    apps/backend/scripts/ops/measure_recurrence_wallclock_impact.sql and
--    approved (runbook: docs/ops/recurrence_wallclock_remap.md). Its default is
--    a dry run. The pairing is ALIGNED ORDER: the i-th UTC-clock occurrence
--    moves to the (i + k)-th wall-clock one, a strictly increasing one-to-one
--    map that cannot fold two occurrences onto one key. k (-2..2) is chosen
--    per series as the offset that moves its first 60 occurrences least, so a
--    New York Wednesday-evening series, whose UTC-clock expansion dropped its
--    first night, pairs each Tuesday with the next day rather than with the
--    Wednesday before it. Done series are recorded in
--    private.recurrence_wallclock_remaps, which is what makes a second run a
--    no-op; a sweep pass moves rows an old build wrote afterwards. A dry run
--    records nothing, so it is single-shot: one refuses a p_max_events below
--    the number of series it would select.
--
-- Locks: CREATE TABLE in `private`, CREATE / DROP FUNCTION and one row into
-- the tiny private.feature_flags take no lock on any populated table. Nothing
-- here scans or updates a populated row.

-- ── 1. zone + wall-clock helpers ────────────────────────────────────────────

create or replace function private.recurrence_zone(p_zone text)
returns text
language plpgsql
stable
set search_path = ''
as $$
begin
  -- IANA names only: a POSIX string such as 'UTC+3' would be read here with
  -- its sign inverted and refused by Intl on the clients.
  if p_zone is null
     or p_zone !~ '^([A-Za-z_]+(/[A-Za-z0-9_+-]+)*|[A-Z]{3}[0-9][A-Z]{3})$' then
    return 'UTC';
  end if;
  perform now() at time zone p_zone;
  return p_zone;
exception when invalid_parameter_value then
  return 'UTC';
end;
$$;

create or replace function private.zone_offset(p_at timestamptz, p_zone text)
returns interval
language sql
stable
set search_path = ''
as $$
  select (p_at at time zone p_zone) - (p_at at time zone 'UTC');
$$;

-- The instant a local wall-clock names in p_zone: the earlier of two in an
-- overlap, and the pre-transition offset (so a later wall time) in a gap.
create or replace function private.wallclock_instant(p_wall timestamp, p_zone text)
returns timestamptz
language plpgsql
stable
set search_path = ''
as $$
declare
  v_wall   timestamptz := p_wall at time zone 'UTC';
  v_before interval := private.zone_offset(v_wall - interval '24 hours', p_zone);
  v_after  interval := private.zone_offset(v_wall + interval '24 hours', p_zone);
  v_o      interval;
  v_t      timestamptz;
  v_best   timestamptz;
begin
  foreach v_o in array array[v_before, v_after] loop
    v_t := v_wall - v_o;
    if private.zone_offset(v_t, p_zone) = v_o and (v_best is null or v_t < v_best) then
      v_best := v_t;
    end if;
  end loop;
  return coalesce(v_best, v_wall - v_before);
end;
$$;

-- ── 2. expansion + membership ───────────────────────────────────────────────

create or replace function private.recurrence_occurrences(
  p_starts_at timestamptz,
  p_freq      text,
  p_byday     text[],
  p_until     timestamptz,
  p_count     int,
  p_zone      text,
  p_from      timestamptz,
  p_to        timestamptz,
  p_max       int default null
)
returns setof timestamptz
language plpgsql
stable
set search_path = ''
as $$
declare
  v_codes    text[] := array['MO','TU','WE','TH','FR','SA','SU'];
  v_start    timestamptz := date_trunc('second', p_starts_at);
  v_local    timestamp := date_trunc('second', p_starts_at) at time zone p_zone;
  v_day0     date := (date_trunc('second', p_starts_at) at time zone p_zone)::date;
  v_tod      interval;
  v_last     date;
  v_byday    text[];
  v_step     int;
  v_anchor   date;
  v_day      date;
  v_at       timestamptz;
  v_produced bigint := 0;
  v_emitted  bigint := 0;
  v_i        int := 0;
  v_total    int;
  v_first_of date;
  v_budget   int;
begin
  if p_freq is null then
    if p_starts_at >= p_from and p_starts_at <= p_to then
      return next p_starts_at;
    end if;
    return;
  end if;
  if p_count is not null and p_count <= 0 then
    return;
  end if;

  v_tod := v_local - v_day0::timestamp;
  v_last := (least(p_to, coalesce(p_until, p_to)) at time zone p_zone)::date + 1;

  if p_freq = 'monthly' then
    v_budget := (extract(year from v_last)::int - extract(year from v_day0)::int) * 12
              + (extract(month from v_last)::int - extract(month from v_day0)::int) + 1;
    loop
      exit when p_count is not null and v_produced >= p_count;
      exit when v_i > v_budget;
      v_total := extract(month from v_day0)::int - 1 + v_i;
      v_first_of := make_date(extract(year from v_day0)::int + v_total / 12, v_total % 12 + 1, 1);
      v_day := v_first_of + (least(
        extract(day from v_day0)::int,
        ((v_first_of + interval '1 month')::date - v_first_of)
      ) - 1);
      v_at := case when v_day = v_day0 then v_start
                   else private.wallclock_instant(v_day + v_tod, p_zone) end;
      exit when p_until is not null and v_at > p_until;
      v_produced := v_produced + 1;
      exit when v_at > p_to;
      if v_at >= p_from then
        return next v_at;
        v_emitted := v_emitted + 1;
        exit when p_max is not null and v_emitted >= p_max;
      end if;
      v_i := v_i + 1;
    end loop;
    return;
  end if;

  v_byday := coalesce(nullif(p_byday, '{}'::text[]),
                      array[v_codes[extract(isodow from v_day0)::int]]);
  v_step := case when p_freq = 'biweekly' then 2 else 1 end;
  v_anchor := v_day0 - (extract(isodow from v_day0)::int - 1);
  v_day := v_day0;
  while v_day <= v_last loop
    if ((v_day - v_anchor) / 7) % v_step = 0
       and v_codes[extract(isodow from v_day)::int] = any (v_byday) then
      v_at := case when v_day = v_day0 then v_start
                   else private.wallclock_instant(v_day + v_tod, p_zone) end;
      if not ((p_until is not null and v_at > p_until) or v_at > p_to or v_at < v_start) then
        exit when p_count is not null and v_produced >= p_count;
        v_produced := v_produced + 1;
        if v_at >= p_from then
          return next v_at;
          v_emitted := v_emitted + 1;
          exit when p_max is not null and v_emitted >= p_max;
        end if;
      end if;
    end if;
    v_day := v_day + 1;
  end loop;
end;
$$;

-- Membership in O(1): p_instance is client-supplied, so this never walks the
-- series (a count with no until would otherwise let one insert expand a range
-- out to year 9999). The candidate is resolved from p_instance's own local
-- date, or the day before it when a gap pushed a late wall-clock past
-- midnight, and must be exactly the instant the walk would stamp.
create or replace function private.recurrence_is_occurrence(
  p_starts_at timestamptz,
  p_freq      text,
  p_byday     text[],
  p_until     timestamptz,
  p_count     int,
  p_zone      text,
  p_instance  timestamptz
)
returns boolean
language plpgsql
stable
set search_path = ''
as $$
declare
  v_codes  text[] := array['MO','TU','WE','TH','FR','SA','SU'];
  v_start  timestamptz := date_trunc('second', p_starts_at);
  v_day0   date;
  v_tod    interval;
  v_byday  text[];
  v_step   int;
  v_anchor date;
  v_cand   date;
  v_day    date;
  v_months int;
  v_n      bigint;
  v_i      int;
  v_first  date;
begin
  if p_instance is null then
    return false;
  end if;
  if p_freq is null then
    return p_instance = p_starts_at;
  end if;
  if p_instance < v_start
     or (p_until is not null and p_instance > p_until)
     or p_instance <> date_trunc('second', p_instance)
     or (p_count is not null and p_count <= 0) then
    return false;
  end if;

  v_day0 := (v_start at time zone p_zone)::date;
  v_tod := (v_start at time zone p_zone) - v_day0::timestamp;
  v_cand := (p_instance at time zone p_zone)::date;
  v_byday := coalesce(nullif(p_byday, '{}'::text[]),
                      array[v_codes[extract(isodow from v_day0)::int]]);
  v_step := case when p_freq = 'biweekly' then 2 else 1 end;
  v_anchor := v_day0 - (extract(isodow from v_day0)::int - 1);

  foreach v_day in array array[v_cand, v_cand - 1] loop
    continue when v_day < v_day0;
    continue when p_instance <> case when v_day = v_day0 then v_start
                                     else private.wallclock_instant(v_day + v_tod, p_zone) end;
    if p_freq = 'monthly' then
      v_months := (extract(year from v_day)::int - extract(year from v_day0)::int) * 12
                + (extract(month from v_day)::int - extract(month from v_day0)::int);
      continue when extract(day from v_day)::int <> least(
        extract(day from v_day0)::int,
        extract(day from ((date_trunc('month', v_day::timestamp) + interval '1 month')::date - 1))::int
      );
      return p_count is null or v_months + 1 <= p_count;
    end if;

    continue when not (v_codes[extract(isodow from v_day)::int] = any (v_byday));
    continue when ((v_day - v_anchor) / 7) % v_step <> 0;
    if p_count is null then
      return true;
    end if;
    -- Counted per weekday, never walked: every eligible local date from the
    -- start date to v_day is an occurrence no later than p_instance.
    v_n := 0;
    for v_i in 1..7 loop
      continue when not (v_codes[v_i] = any (v_byday));
      v_first := v_day0 + ((v_i - extract(isodow from v_day0)::int + 7) % 7);
      v_first := v_first + 7 * (((v_first - v_anchor) / 7) % v_step);
      if v_first <= v_day then
        v_n := v_n + (v_day - v_first) / (7 * v_step) + 1;
      end if;
    end loop;
    return v_n <= p_count;
  end loop;
  return false;
end;
$$;

-- The canonical occurrence set of one event row. A legacy series (no
-- timezone) has none: its instants were always minted in each viewer's zone.
create or replace function private.event_occurrences(
  p_event_id uuid,
  p_from     timestamptz,
  p_to       timestamptz
)
returns setof timestamptz
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  e record;
begin
  select starts_at, recurrence_freq, recurrence_byday, recurrence_until,
         recurrence_count, timezone
    into e
    from public.events
   where id = p_event_id;
  if not found or (e.recurrence_freq is not null and e.timezone is null) then
    return;
  end if;
  return query
    select private.recurrence_occurrences(
      e.starts_at, e.recurrence_freq, e.recurrence_byday, e.recurrence_until,
      e.recurrence_count, private.recurrence_zone(e.timezone), p_from, p_to);
end;
$$;

-- ── 3. the transition window ────────────────────────────────────────────────

-- Enabled = window open: the UTC-clock instants every build before § 1918
-- mints are still occurrences where the caller allows them. Absent or disabled
-- = strict, so losing the row can only narrow what is accepted.
insert into private.feature_flags (name, enabled)
values ('recurrence_utc_clock_legacy', true)
on conflict (name) do nothing;

create or replace function private.recurrence_utc_clock_accepted()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select f.enabled from private.feature_flags f where f.name = 'recurrence_utc_clock_legacy'),
    false
  );
$$;

-- A third, defaulted argument would make every two-argument call ambiguous
-- beside the 20270807000001 signature, so that one goes.
drop function private.is_event_occurrence(uuid, timestamptz);

create function private.is_event_occurrence(
  p_event_id     uuid,
  p_instance     timestamptz,
  p_allow_legacy boolean default true
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  e           record;
  v_start_sec timestamptz;
  v_rem       numeric;
  v_zone      text;
begin
  if p_event_id is null or p_instance is null then
    return false;
  end if;

  select starts_at, recurrence_freq, recurrence_byday, recurrence_until,
         recurrence_count, timezone
    into e
    from public.events
   where id = p_event_id;
  if not found then
    return false;
  end if;

  if e.recurrence_freq is null then
    return p_instance = e.starts_at;
  end if;

  if e.timezone is null then
    v_start_sec := date_trunc('second', e.starts_at);
    if p_instance < v_start_sec
       or (e.recurrence_until is not null and p_instance > e.recurrence_until) then
      return false;
    end if;
    if e.recurrence_freq = 'monthly' then
      return true;
    end if;
    v_rem := mod(extract(epoch from (p_instance - v_start_sec)), 86400);
    return v_rem <= 3600 or v_rem >= 82800;
  end if;

  v_zone := private.recurrence_zone(e.timezone);
  if private.recurrence_is_occurrence(e.starts_at, e.recurrence_freq, e.recurrence_byday,
       e.recurrence_until, e.recurrence_count, v_zone, p_instance) then
    return true;
  end if;
  return p_allow_legacy
     and v_zone <> 'UTC'
     and private.recurrence_utc_clock_accepted()
     and private.recurrence_is_occurrence(e.starts_at, e.recurrence_freq, e.recurrence_byday,
           e.recurrence_until, e.recurrence_count, 'UTC', p_instance);
end;
$$;

-- ── 4. the gated remap ──────────────────────────────────────────────────────

create table private.recurrence_wallclock_remaps (
  event_id      uuid primary key references public.events(id) on delete cascade,
  shift         int not null,
  moved         bigint not null,
  conflicts     bigint not null,
  unmapped      bigint not null,
  remapped_at   timestamptz not null default clock_timestamp(),
  last_swept_at timestamptz
);

comment on table private.recurrence_wallclock_remaps is
  'One row per timezoned recurring series private.remap_recurrence_wallclock has '
  'moved onto wall-clock instants (decisions § 1918). Its presence is what makes a '
  'second run skip the series; a sweep only moves rows still on UTC-clock-only instants.';

alter table private.recurrence_wallclock_remaps enable row level security;
revoke all on table private.recurrence_wallclock_remaps from public, anon, authenticated, service_role;

-- Rows of one event keyed at one instant, across every instance-keyed table.
create or replace function private.recurrence_key_rows(p_event_id uuid, p_at timestamptz)
returns bigint
language sql
stable
set search_path = ''
as $$
  select (select count(*) from public.event_pricing where event_id = p_event_id and instance_start = p_at)
       + (select count(*) from public.event_orders where event_id = p_event_id and instance_start = p_at)
       + (select count(*) from public.event_exceptions where event_id = p_event_id and instance_start = p_at)
       + (select count(*) from public.race_sessions where event_id = p_event_id and instance_start = p_at)
       + (select count(*) from public.event_attendees where event_id = p_event_id and instance_start = p_at)
       + (select count(*) from public.event_results where event_id = p_event_id and instance_start = p_at)
       + (select count(*) from public.checkpoint_crossings where event_id = p_event_id and instance_start = p_at)
       + (select count(*) from public.race_pings where event_id = p_event_id and instance_start = p_at)
       + (select count(*) from public.run_photos where event_id = p_event_id and event_instance_start = p_at)
       + (select count(*) from public.club_posts where event_id = p_event_id and event_instance_start = p_at)
       + (select count(*) from public.notifications where event_id = p_event_id and event_instance_start = p_at);
$$;

-- Move one event's rows from one instant to another. Tables go in the order
-- their triggers need: a priced `going` RSVP is checked against the pricing
-- row and the paid order at its NEW instant, so those move first. A row whose
-- target is already held by the same identity (a unique key) stays where it
-- is, and so does any row a trigger refuses; the caller counts what is left
-- and reports the refusals. Each table is its own subtransaction so one
-- refusal cannot undo another table's move.
create or replace function private.recurrence_move_key(
  p_event_id uuid,
  p_from     timestamptz,
  p_to       timestamptz,
  inout p_refused text[]
)
language plpgsql
volatile
set search_path = ''
as $$
begin
  begin
    update public.event_pricing p set instance_start = p_to
     where p.event_id = p_event_id and p.instance_start = p_from
       and not exists (select 1 from public.event_pricing q
                        where q.event_id = p_event_id and q.instance_start = p_to);
  exception when others then
    p_refused := p_refused || ('event_pricing: ' || sqlerrm);
  end;

  begin
    update public.event_orders o set instance_start = p_to
     where o.event_id = p_event_id and o.instance_start = p_from;
  exception when others then
    p_refused := p_refused || ('event_orders: ' || sqlerrm);
  end;

  begin
    update public.event_exceptions x set instance_start = p_to
     where x.event_id = p_event_id and x.instance_start = p_from
       and not exists (select 1 from public.event_exceptions q
                        where q.event_id = p_event_id and q.instance_start = p_to);
  exception when others then
    p_refused := p_refused || ('event_exceptions: ' || sqlerrm);
  end;

  begin
    update public.race_sessions s set instance_start = p_to
     where s.event_id = p_event_id and s.instance_start = p_from
       and not exists (select 1 from public.race_sessions q
                        where q.event_id = p_event_id and q.instance_start = p_to);
  exception when others then
    p_refused := p_refused || ('race_sessions: ' || sqlerrm);
  end;

  begin
    update public.event_attendees a set instance_start = p_to
     where a.event_id = p_event_id and a.instance_start = p_from
       and not exists (select 1 from public.event_attendees q
                        where q.event_id = p_event_id and q.user_id = a.user_id
                          and q.instance_start = p_to);
  exception when others then
    p_refused := p_refused || ('event_attendees: ' || sqlerrm);
  end;

  begin
    update public.event_results r set instance_start = p_to
     where r.event_id = p_event_id and r.instance_start = p_from
       and not exists (select 1 from public.event_results q
                        where q.event_id = p_event_id and q.instance_start = p_to
                          and ((r.user_id is not null and q.user_id = r.user_id)
                               or (r.bib is not null and q.bib = r.bib)));
  exception when others then
    p_refused := p_refused || ('event_results: ' || sqlerrm);
  end;

  begin
    update public.checkpoint_crossings c set instance_start = p_to
     where c.event_id = p_event_id and c.instance_start = p_from
       and not exists (select 1 from public.checkpoint_crossings q
                        where q.event_id = p_event_id and q.checkpoint_id = c.checkpoint_id
                          and q.instance_start = p_to
                          and ((c.user_id is not null and q.user_id = c.user_id)
                               or (c.bib is not null and q.bib = c.bib)));
  exception when others then
    p_refused := p_refused || ('checkpoint_crossings: ' || sqlerrm);
  end;

  begin
    update public.race_pings g set instance_start = p_to
     where g.event_id = p_event_id and g.instance_start = p_from;
  exception when others then
    p_refused := p_refused || ('race_pings: ' || sqlerrm);
  end;

  begin
    update public.run_photos rp set event_instance_start = p_to
     where rp.event_id = p_event_id and rp.event_instance_start = p_from;
  exception when others then
    p_refused := p_refused || ('run_photos: ' || sqlerrm);
  end;

  begin
    update public.club_posts cp set event_instance_start = p_to
     where cp.event_id = p_event_id and cp.event_instance_start = p_from;
  exception when others then
    p_refused := p_refused || ('club_posts: ' || sqlerrm);
  end;

  begin
    update public.notifications n set event_instance_start = p_to
     where n.event_id = p_event_id and n.event_instance_start = p_from
       and not (n.kind = 'event_reminder' and exists (
         select 1 from public.notifications q
          where q.kind = 'event_reminder' and q.user_id = n.user_id
            and q.event_id = p_event_id and q.event_instance_start = p_to));
  exception when others then
    p_refused := p_refused || ('notifications: ' || sqlerrm);
  end;
end;
$$;

-- Remap up to p_max_events series per call, one call per transaction.
--   p_apply = false (the default): a dry run. Every move is made and then
--     rolled back, so the counts are the real ones; nothing is recorded. That
--     makes it single-shot: a loop of dry runs would select the same series
--     forever, so a dry run whose p_max_events is below the number of series
--     it would select is refused (22023) rather than silently truncated.
--   p_swept_before null: first pass over series not yet in the ledger.
--   p_swept_before set: a sweep over series already remapped whose last sweep
--     is older than it, moving only rows still on a UTC-clock-only instant
--     (written by an old build during the transition window).
--   p_event_ids: only these series (a pilot, or one organiser's events).
-- Returns one row per series processed; an operator loops an APPLY until it
-- returns none (docs/ops/recurrence_wallclock_remap.md).
create or replace function private.remap_recurrence_wallclock(
  p_max_events   int default 10,
  p_apply        boolean default false,
  p_swept_before timestamptz default null,
  p_event_ids    uuid[] default null
)
returns table (
  event_id  uuid,
  shift     int,
  moved     bigint,
  conflicts bigint,
  unmapped  bigint,
  stray     bigint,
  refused   text[]
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  e        record;
  v_sweep  boolean := p_swept_before is not null;
  v_zone   text;
  v_keys   timestamptz[];
  v_old    timestamptz[];
  v_new    timestamptz[];
  v_m      int;
  v_i      int;
  v_pair   record;
  v_before bigint;
  v_after  bigint;
  v_ids    uuid[];
  v_batch  int := greatest(coalesce(p_max_events, 0), 0);
begin
  v_ids := array(
    select ev.id
      from public.events ev
      left join private.recurrence_wallclock_remaps l on l.event_id = ev.id
     where ev.recurrence_freq is not null
       and ev.timezone is not null
       and (p_event_ids is null or ev.id = any (p_event_ids))
       and case when v_sweep
                then l.event_id is not null
                     and coalesce(l.last_swept_at, l.remapped_at) < p_swept_before
                else l.event_id is null end
     order by ev.id);

  if not p_apply and cardinality(v_ids) > v_batch then
    raise exception 'a dry run records nothing, so it cannot be batched: % series are eligible and p_max_events is %; pass p_max_events => % or narrow p_event_ids',
      cardinality(v_ids), v_batch, cardinality(v_ids)
      using errcode = 'invalid_parameter_value';
  end if;

  for e in
    select ev.id, ev.starts_at, ev.recurrence_freq, ev.recurrence_byday,
           ev.recurrence_until, ev.recurrence_count, ev.timezone, l.shift as done_shift
      from public.events ev
      left join private.recurrence_wallclock_remaps l on l.event_id = ev.id
     where ev.id = any (v_ids[1:v_batch])
     order by ev.id
  loop
    event_id := e.id;
    moved := 0;
    conflicts := 0;
    unmapped := 0;
    stray := 0;
    refused := '{}';
    v_zone := private.recurrence_zone(e.timezone);

    select array_agg(distinct k order by k) into v_keys from (
                select instance_start k from public.event_pricing where event_pricing.event_id = e.id and instance_start is not null
      union all select instance_start from public.event_orders where event_orders.event_id = e.id
      union all select instance_start from public.event_exceptions where event_exceptions.event_id = e.id
      union all select instance_start from public.race_sessions where race_sessions.event_id = e.id
      union all select instance_start from public.event_attendees where event_attendees.event_id = e.id
      union all select instance_start from public.event_results where event_results.event_id = e.id
      union all select instance_start from public.checkpoint_crossings where checkpoint_crossings.event_id = e.id
      union all select distinct instance_start from public.race_pings where race_pings.event_id = e.id
      union all select event_instance_start from public.run_photos where run_photos.event_id = e.id and event_instance_start is not null
      union all select event_instance_start from public.club_posts where club_posts.event_id = e.id and event_instance_start is not null
      union all select event_instance_start from public.notifications where notifications.event_id = e.id and event_instance_start is not null
    ) s;

    shift := coalesce(e.done_shift, 0);
    if v_zone <> 'UTC' and v_keys is not null then
      v_old := array(select private.recurrence_occurrences(
        e.starts_at, e.recurrence_freq, e.recurrence_byday, e.recurrence_until,
        e.recurrence_count, 'UTC', '-infinity', v_keys[cardinality(v_keys)]));
      v_new := array(select private.recurrence_occurrences(
        e.starts_at, e.recurrence_freq, e.recurrence_byday, e.recurrence_until,
        e.recurrence_count, v_zone, '-infinity', v_keys[cardinality(v_keys)] + interval '9600 hours',
        cardinality(v_old) + 3));

      if e.done_shift is null then
        v_m := least(cardinality(v_old), 60);
        select k into shift
          from generate_series(-2, 2) k
         order by (select coalesce(sum(case when i + k between 1 and cardinality(v_new)
                                            then abs(extract(epoch from v_new[i + k] - v_old[i]))
                                            else 31 * 86400 end), 0)
                     from generate_series(1, v_m) i),
                  abs(k), k
         limit 1;
      end if;

      begin
        -- Up-moves from the latest down, down-moves from the earliest up: a
        -- strictly increasing pairing means an instant's rows only ever move
        -- onto an instant whose own rows have already left it.
        for v_pair in
          select o.at as from_at, v_new[o.i + shift] as to_at
            from unnest(v_old) with ordinality as o(at, i)
           where o.i + shift between 1 and cardinality(v_new)
             and o.at <> v_new[o.i + shift]
             and o.at = any (v_keys)
             and (not v_sweep or not private.recurrence_is_occurrence(
                    e.starts_at, e.recurrence_freq, e.recurrence_byday, e.recurrence_until,
                    e.recurrence_count, v_zone, o.at))
           order by (v_new[o.i + shift] > o.at) desc,
                    case when v_new[o.i + shift] > o.at then o.at end desc,
                    o.at asc
        loop
          v_before := private.recurrence_key_rows(e.id, v_pair.from_at);
          refused := private.recurrence_move_key(e.id, v_pair.from_at, v_pair.to_at, refused);
          v_after := private.recurrence_key_rows(e.id, v_pair.from_at);
          moved := moved + (v_before - v_after);
          conflicts := conflicts + v_after;
        end loop;

        select coalesce(sum(private.recurrence_key_rows(e.id, o.at)), 0) into unmapped
          from unnest(v_old) with ordinality as o(at, i)
         where not (o.i + shift between 1 and cardinality(v_new))
           and o.at = any (v_keys);

        if not p_apply then
          raise exception using errcode = 'RW001', message = 'recurrence_wallclock_dry_run';
        end if;
      exception when sqlstate 'RW001' then
        null;
      end;

      select coalesce(sum(private.recurrence_key_rows(e.id, k)), 0) into stray
        from unnest(v_keys) k
       where not (k = any (v_old))
         and not private.recurrence_is_occurrence(
               e.starts_at, e.recurrence_freq, e.recurrence_byday, e.recurrence_until,
               e.recurrence_count, v_zone, k);
    end if;

    select array(select distinct r from unnest(refused) r order by r) into refused;

    if p_apply then
      insert into private.recurrence_wallclock_remaps as l
             (event_id, shift, moved, conflicts, unmapped)
      values (e.id, shift, moved, conflicts, unmapped)
      on conflict on constraint recurrence_wallclock_remaps_pkey do update
         set moved = l.moved + excluded.moved,
             conflicts = excluded.conflicts,
             unmapped = excluded.unmapped,
             last_swept_at = clock_timestamp();
    end if;
    return next;
  end loop;
end;
$$;

-- Keyed rows of timezoned series still on an instant only the UTC clock
-- produces. What the window must be empty of before it closes.
create or replace function private.recurrence_wallclock_old_only_rows()
returns table (table_name text, event_id uuid, instance_start timestamptz, row_count bigint)
language sql
stable
security definer
set search_path = ''
as $$
  with keyed as (
              select 'event_pricing' t, k.event_id e, k.instance_start i from public.event_pricing k where k.instance_start is not null
    union all select 'event_orders', k.event_id, k.instance_start from public.event_orders k
    union all select 'event_exceptions', k.event_id, k.instance_start from public.event_exceptions k
    union all select 'race_sessions', k.event_id, k.instance_start from public.race_sessions k
    union all select 'event_attendees', k.event_id, k.instance_start from public.event_attendees k
    union all select 'event_results', k.event_id, k.instance_start from public.event_results k
    union all select 'checkpoint_crossings', k.event_id, k.instance_start from public.checkpoint_crossings k
    union all select 'race_pings', k.event_id, k.instance_start from public.race_pings k
    union all select 'run_photos', k.event_id, k.event_instance_start from public.run_photos k where k.event_id is not null and k.event_instance_start is not null
    union all select 'club_posts', k.event_id, k.event_instance_start from public.club_posts k where k.event_id is not null and k.event_instance_start is not null
    union all select 'notifications', k.event_id, k.event_instance_start from public.notifications k where k.event_id is not null and k.event_instance_start is not null
  ), grouped as (
    select t, e, i, count(*) n from keyed group by t, e, i
  )
  select g.t, g.e, g.i, g.n
    from grouped g
    join public.events ev on ev.id = g.e
   where ev.recurrence_freq is not null
     and ev.timezone is not null
     and private.recurrence_zone(ev.timezone) <> 'UTC'
     and not private.recurrence_is_occurrence(ev.starts_at, ev.recurrence_freq, ev.recurrence_byday,
           ev.recurrence_until, ev.recurrence_count, private.recurrence_zone(ev.timezone), g.i)
     and private.recurrence_is_occurrence(ev.starts_at, ev.recurrence_freq, ev.recurrence_byday,
           ev.recurrence_until, ev.recurrence_count, 'UTC', g.i)
   order by g.t, g.e, g.i;
$$;

-- Close the window by disabling the legacy flag: from here a UTC-clock-only
-- instant is no occurrence on any path.
-- Refuses while any keyed row still sits on one, unless p_force. Returns the
-- number of such rows it found.
create or replace function private.close_recurrence_wallclock_transition(p_force boolean default false)
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_rows bigint;
begin
  select coalesce(sum(row_count), 0) into v_rows from private.recurrence_wallclock_old_only_rows();
  if v_rows > 0 and not p_force then
    raise exception '% keyed rows still sit on UTC-clock-only instants; sweep them first or pass p_force => true', v_rows
      using errcode = 'P0001';
  end if;
  insert into private.feature_flags (name, enabled)
  values ('recurrence_utc_clock_legacy', false)
  on conflict (name) do update set enabled = false, updated_at = now();
  return v_rows;
end;
$$;

-- ── 5. grants ───────────────────────────────────────────────────────────────

revoke execute on function private.is_event_occurrence(uuid, timestamptz, boolean) from public, anon;
grant execute on function private.is_event_occurrence(uuid, timestamptz, boolean) to authenticated, service_role;

revoke execute on function private.recurrence_zone(text) from public, anon, authenticated;
revoke execute on function private.zone_offset(timestamptz, text) from public, anon, authenticated;
revoke execute on function private.wallclock_instant(timestamp, text) from public, anon, authenticated;
revoke execute on function private.recurrence_occurrences(timestamptz, text, text[], timestamptz, int, text, timestamptz, timestamptz, int) from public, anon, authenticated;
revoke execute on function private.recurrence_is_occurrence(timestamptz, text, text[], timestamptz, int, text, timestamptz) from public, anon, authenticated;
revoke execute on function private.event_occurrences(uuid, timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function private.event_occurrences(uuid, timestamptz, timestamptz) to service_role;
revoke execute on function private.recurrence_utc_clock_accepted() from public, anon, authenticated;
revoke execute on function private.recurrence_key_rows(uuid, timestamptz) from public, anon, authenticated, service_role;
revoke execute on function private.recurrence_move_key(uuid, timestamptz, timestamptz, text[]) from public, anon, authenticated, service_role;
revoke execute on function private.remap_recurrence_wallclock(int, boolean, timestamptz, uuid[]) from public, anon, authenticated, service_role;
revoke execute on function private.recurrence_wallclock_old_only_rows() from public, anon, authenticated, service_role;
revoke execute on function private.close_recurrence_wallclock_transition(boolean) from public, anon, authenticated, service_role;

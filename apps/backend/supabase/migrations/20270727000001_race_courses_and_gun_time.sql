-- Multi-course races with automatic gun-time finishes (clubs.md § Live race
-- mode, decisions § 1842).
--
-- A host creates a race with one or more courses, each racer picks a course
-- when they RSVP, the host presses GO, and each racer's device records their
-- finish (gun time against race_sessions.started_at) without anyone typing a
-- time. This migration is the data half of that loop:
--
--   * event_courses — the courses of an event (a route, a name, a distance, an
--     order). One per existing event that names a route is backfilled, so the
--     legacy single-route event reads as a one-course race; events.route_id
--     stays as that legacy pointer and is not dropped.
--   * event_attendees.course_id — the racer's chosen course. When an event has
--     more than one course a self-RSVP to going / waitlisted must name one.
--   * event_results.course_id / gun_time_s / chip_time_s / finish_method —
--     where the time came from. duration_s stays the ranked time, and
--     recompute_event_ranks now ranks within a course (a NULL course is one
--     bucket, so every pre-course event ranks exactly as before).
--   * The write window: a self-written result on a raced occurrence lands only
--     while the race is running or within 24 h of it finishing — never before
--     GO, so an armed race cannot collect times, and a finish queued with no
--     signal still lands when the phone reconnects.
--   * Ending a race (running -> finished) files a host DNF for every attendee
--     who pinged the race but never filed a result, and an organiser's edit of
--     someone else's time stamps finish_method = 'host'.
--
-- Online safety (docs/backend/migration_locks.md): event_results and
-- event_attendees are populated, so every constraint added to them here is
-- NOT VALID and validated by 20270727000002 in its own transaction. The new
-- columns are nullable with no default, which is a catalogue-only change.

set search_path = public;

-- ─── event_courses ─────────────────────────────────────────────────────────

create table public.event_courses (
  id          uuid primary key default gen_random_uuid(),
  event_id    uuid not null references public.events(id) on delete cascade,
  route_id    uuid references public.routes(id) on delete set null,
  name        text not null
    constraint event_courses_name_len_chk
      check (char_length(btrim(name)) between 1 and 120),
  distance_m  double precision
    constraint event_courses_distance_m_check
      check (distance_m is null or (distance_m > 0 and distance_m <= 1000000)),
  sort_order  integer not null default 0
    constraint event_courses_sort_order_check
      check (sort_order between 0 and 1000),
  created_at  timestamptz not null default now()
);

create index event_courses_event_id on public.event_courses (event_id, sort_order);
create index event_courses_route_id on public.event_courses (route_id);

alter table public.event_courses enable row level security;

-- Read follows the parent event: the subquery is itself filtered by the events
-- SELECT policy, so a course is visible exactly when its event is.
create policy event_courses_visible_with_event
  on public.event_courses for select
  using (exists (select 1 from public.events e where e.id = event_courses.event_id));

-- Write is the predicate the events INSERT/UPDATE/DELETE policies use.
create policy event_courses_organiser_insert
  on public.event_courses for insert
  with check (exists (
    select 1 from public.events e
    where e.id = event_courses.event_id and private.is_event_organiser(e.club_id)
  ));

create policy event_courses_organiser_update
  on public.event_courses for update
  using (exists (
    select 1 from public.events e
    where e.id = event_courses.event_id and private.is_event_organiser(e.club_id)
  ))
  with check (exists (
    select 1 from public.events e
    where e.id = event_courses.event_id and private.is_event_organiser(e.club_id)
  ));

create policy event_courses_organiser_delete
  on public.event_courses for delete
  using (exists (
    select 1 from public.events e
    where e.id = event_courses.event_id and private.is_event_organiser(e.club_id)
  ));

grant select on public.event_courses to anon;
grant select, insert, update, delete on public.event_courses to authenticated;
grant select, insert, update, delete on public.event_courses to service_role;

-- Backfill: one course per event that names a route. `events` is a bounded
-- config table, so one statement is fine. The distance prefers the route's
-- geometry (what the finish rule measures against) over the event's stated
-- distance, and is dropped rather than clamped when neither is in range.
insert into public.event_courses (event_id, route_id, name, distance_m, sort_order)
select
  e.id,
  e.route_id,
  coalesce(nullif(left(btrim(r.name), 120), ''), 'Course'),
  case
    when coalesce(r.distance_m::float8, e.distance_m::float8) > 0
     and coalesce(r.distance_m::float8, e.distance_m::float8) <= 1000000
      then coalesce(r.distance_m::float8, e.distance_m::float8)
  end,
  0
from public.events e
left join public.routes r on r.id = e.route_id
where e.route_id is not null
  and not exists (select 1 from public.event_courses c where c.event_id = e.id);

-- ─── event_attendees.course_id ────────────────────────────────────────────

alter table public.event_attendees add column course_id uuid;

alter table public.event_attendees
  add constraint event_attendees_course_id_fkey
  foreign key (course_id) references public.event_courses(id) on delete set null
  not valid;

create index event_attendees_course_id on public.event_attendees (course_id);

-- The attendee write grants are per-column (20270520_001 for INSERT,
-- 20270102_001 + 20270408_001 for UPDATE), so a new column is deny-by-default
-- until it is named.
grant insert (course_id) on public.event_attendees to authenticated;
grant update (course_id) on public.event_attendees to authenticated;

-- Validation only — it never assigns NEW, so a fixture's supplied value is the
-- value that lands. Two rules:
--   1. a course must belong to the attendee's event;
--   2. on an event with more than one course, a racer's own going / waitlisted
--      RSVP must name a course. Only a direct write is held to this
--      (pg_trigger_depth() = 1): a waitlist promotion fired from another
--      trigger, or the SET NULL cascade from a host deleting a course, must not
--      be refused for a choice the racer never got to make.
create or replace function public.event_attendees_course_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.course_id is not null and not exists (
    select 1 from event_courses c
    where c.id = new.course_id and c.event_id = new.event_id
  ) then
    raise exception 'event_course_mismatch: course % does not belong to event %',
      new.course_id, new.event_id
      using errcode = 'check_violation';
  end if;

  if new.course_id is null
     and new.status in ('going', 'waitlisted')
     and pg_trigger_depth() = 1
     and new.user_id = auth.uid()
     and (tg_op = 'INSERT' or old.status is distinct from new.status
          or old.course_id is not null)
     and (select count(*) from event_courses c where c.event_id = new.event_id) > 1
  then
    raise exception 'event_course_required: pick a course for this event'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger event_attendees_course_guard_trg
  before insert or update of course_id, status on public.event_attendees
  for each row execute function public.event_attendees_course_guard();

-- ─── event_results: course + timing provenance ─────────────────────────────

alter table public.event_results
  add column course_id uuid,
  add column gun_time_s integer,
  add column chip_time_s integer,
  add column finish_method text;

alter table public.event_results
  add constraint event_results_course_id_fkey
  foreign key (course_id) references public.event_courses(id) on delete set null
  not valid;

alter table public.event_results
  add constraint event_results_gun_time_s_check
  check (gun_time_s is null or gun_time_s >= 0) not valid;

alter table public.event_results
  add constraint event_results_chip_time_s_check
  check (chip_time_s is null or chip_time_s >= 0) not valid;

alter table public.event_results
  add constraint event_results_finish_method_check
  check (finish_method in ('auto', 'manual', 'host')) not valid;

create index event_results_course_id on public.event_results (course_id);

-- One BEFORE trigger for the three race rules on a result write.
--
--   * Course. On INSERT a result with no course takes the racer's RSVP'd
--     course, else the event's only course — so an old client that never
--     sends course_id still lands in the same leaderboard bucket as a new one.
--     A course must belong to the result's event.
--   * Host edit. When someone other than the result's own runner changes its
--     time or status (RLS admits only a race director, or an organiser for a
--     bib-only row), the result is stamped finish_method = 'host'.
--   * Write window. A runner's own timing write on an occurrence that has a
--     race session lands only while it is running or within 24 h after it
--     finished. An occurrence with no race session (the plain "Submit my time"
--     path) is untouched, and so is a host: the race director / organiser, the
--     service role, and the server itself (no JWT).
create or replace function public.event_results_race_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  );
  v_club uuid;
  v_timing_changed boolean;
  v_status text;
  v_finished_at timestamptz;
begin
  if tg_op = 'INSERT' and new.course_id is null then
    if new.user_id is not null then
      select a.course_id into new.course_id
      from event_attendees a
      where a.event_id = new.event_id
        and a.instance_start = new.instance_start
        and a.user_id = new.user_id;
    end if;
    if new.course_id is null then
      select min(c.id::text)::uuid into new.course_id
      from event_courses c
      where c.event_id = new.event_id
      having count(*) = 1;
    end if;
  end if;

  if new.course_id is not null and not exists (
    select 1 from event_courses c
    where c.id = new.course_id and c.event_id = new.event_id
  ) then
    raise exception 'event_course_mismatch: course % does not belong to event %',
      new.course_id, new.event_id
      using errcode = 'check_violation';
  end if;

  v_timing_changed := tg_op = 'INSERT'
    or new.duration_s is distinct from old.duration_s
    or new.gun_time_s is distinct from old.gun_time_s
    or new.chip_time_s is distinct from old.chip_time_s
    or new.finisher_status is distinct from old.finisher_status;

  if v_role = 'service_role' or v_uid is null or not v_timing_changed then
    return new;
  end if;

  if tg_op = 'UPDATE' and new.user_id is distinct from v_uid then
    new.finish_method := 'host';
  end if;

  select e.club_id into v_club from events e where e.id = new.event_id;
  if private.is_race_director(v_club) or private.is_event_organiser(v_club) then
    return new;
  end if;

  select rs.status, rs.finished_at into v_status, v_finished_at
  from race_sessions rs
  where rs.event_id = new.event_id and rs.instance_start = new.instance_start;

  if not found then
    return new;
  end if;

  if v_status = 'running'
     or (v_status = 'finished' and v_finished_at >= now() - interval '24 hours')
  then
    return new;
  end if;

  raise exception 'race_result_window_closed: race is %', v_status
    using errcode = 'check_violation';
end;
$$;

create trigger event_results_race_guard_before_write
  before insert or update on public.event_results
  for each row execute function public.event_results_race_guard();

-- ─── ranking within a course ───────────────────────────────────────────────

-- Latest body: 20261222_001 (finishers-only window). Only the partition grows:
-- a NULL course_id is a single partition, so a pre-course event ranks as one
-- field exactly as it did.
create or replace function public.recompute_event_ranks(
  p_event_id uuid,
  p_instance_start timestamptz
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  with ranked as (
    select
      ctid,
      case
        when finisher_status = 'finished'
          then rank() over (
            partition by course_id, (finisher_status = 'finished')
            order by duration_s asc, created_at asc
          )
        else null
      end as new_rank
    from event_results
    where event_id = p_event_id and instance_start = p_instance_start
  )
  update event_results er
  set rank = ranked.new_rank,
      updated_at = now()
  from ranked
  where er.ctid = ranked.ctid
    and er.rank is distinct from ranked.new_rank;
end;
$$;

revoke execute on function public.recompute_event_ranks(uuid, timestamptz)
  from public, anon, authenticated;

-- Moving a result between courses moves it between leaderboards, so a
-- course_id change reranks too. Trigger function unchanged (20270516_001).
drop trigger if exists event_results_rerank_after_change on public.event_results;
create trigger event_results_rerank_after_change
  after insert or update of duration_s, finisher_status, course_id or delete
  on public.event_results
  for each row execute function public.event_results_rerank_trigger();

-- ─── host DNF on race end ──────────────────────────────────────────────────

-- The racers a host's End would mark DNF: an attendee of the occurrence (any
-- status but declined) who sent at least one race ping and has no result.
-- Their last ping carries how far and how long they got. Shared by the End
-- trigger and the count the race-control card shows before End.
create or replace function private.race_dnf_candidates(
  p_event_id uuid,
  p_instance_start timestamptz
) returns table (user_id uuid, course_id uuid, elapsed_s integer, distance_m double precision)
language sql
stable
security definer
set search_path = public
as $$
  select a.user_id, a.course_id, lp.elapsed_s, lp.distance_m
  from event_attendees a
  join lateral (
    select p.elapsed_s, p.distance_m
    from race_pings p
    where p.event_id = a.event_id
      and p.instance_start = a.instance_start
      and p.user_id = a.user_id
    order by p.at desc
    limit 1
  ) lp on true
  where a.event_id = p_event_id
    and a.instance_start = p_instance_start
    and a.status <> 'declined'
    and not exists (
      select 1 from event_results r
      where r.event_id = a.event_id
        and r.instance_start = a.instance_start
        and r.user_id = a.user_id
    );
$$;

revoke execute on function private.race_dnf_candidates(uuid, timestamptz)
  from public, anon, authenticated;

create or replace function public.race_sessions_fill_dnf_on_finish()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'finished' and old.status is distinct from 'finished' then
    insert into event_results (
      event_id, instance_start, user_id, course_id,
      duration_s, distance_m, finisher_status, finish_method
    )
    select
      new.event_id, new.instance_start, d.user_id, d.course_id,
      greatest(coalesce(d.elapsed_s, 0), 0),
      greatest(coalesce(d.distance_m, 0), 0),
      'dnf', 'host'
    from private.race_dnf_candidates(new.event_id, new.instance_start) d
    on conflict (event_id, instance_start, user_id) do nothing;
  end if;
  return null;
end;
$$;

create trigger race_sessions_fill_dnf_after_finish
  after update of status on public.race_sessions
  for each row execute function public.race_sessions_fill_dnf_on_finish();

-- What End will do, for the confirm dialog. Race directors only — the same
-- predicate the race_sessions write policies use; anyone else gets NULL rather
-- than a count of another club's racers.
create or replace function public.race_pending_dnf_count(
  p_event_id uuid,
  p_instance_start timestamptz
) returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_club uuid;
begin
  select e.club_id into v_club from events e where e.id = p_event_id;
  if v_club is null or not private.is_race_director(v_club) then
    return null;
  end if;
  return (select count(*)::int from private.race_dnf_candidates(p_event_id, p_instance_start));
end;
$$;

revoke execute on function public.race_pending_dnf_count(uuid, timestamptz)
  from public, anon;
grant execute on function public.race_pending_dnf_count(uuid, timestamptz)
  to authenticated, service_role;

-- ─── read surface ──────────────────────────────────────────────────────────

-- Latest body: 20261030_001. Columns are only appended, so `create or replace`
-- keeps the view's OID, comment and security_invoker; the reset below restates
-- the read-only grant every view carries (20270324_001).
create or replace view public.event_results_redacted as
select
  id,
  event_id,
  instance_start,
  user_id,
  bib,
  finisher_name,
  duration_s,
  distance_m,
  rank,
  finisher_status,
  case
    when user_id = auth.uid() then age_grade_pct
    else null
  end as age_grade_pct,
  case
    when user_id = auth.uid() then note
    else null
  end as note,
  created_at,
  updated_at,
  organiser_approved,
  case
    when user_id = auth.uid() then run_id
    else null
  end as run_id,
  course_id,
  gun_time_s,
  chip_time_s,
  finish_method
from public.event_results;

alter view public.event_results_redacted set (security_invoker = on);

revoke all on public.event_results_redacted from public, anon, authenticated;
grant select on public.event_results_redacted to anon, authenticated;

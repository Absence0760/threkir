-- Three corrections to the race write guards 20270727000001 added
-- (decisions § R6SQL-2, § R6SQL-3).
--
--   * The result write window closed on any race_sessions row that was not
--     running or freshly finished. A race the host armed and then cancelled
--     (or armed and never started) therefore locked every runner out of
--     "Submit my time" for that occurrence, dns / dnf included. Only a race
--     that finished more than 24 h ago closes it now; armed and cancelled
--     occurrences take a runner's own result like an occurrence with no race.
--   * A runner's own timing write is a statement of the whole result, but the
--     clients upsert only the race columns they know, so the old row's
--     gun_time_s / chip_time_s / finish_method survived beside a new time
--     (a self-filed DNF still carrying an auto method and a gun time). The
--     guard now normalises them on the runner's own write: a DNF / DNS keeps
--     none of the three; a gun or chip time the new ranked time no longer
--     matches is dropped; and 'host' — provenance only someone else's edit can
--     earn — is never kept on the runner's own write.
--   * A second self-RSVP upsert on a multi-course event that omitted course_id
--     was refused by the BEFORE INSERT half of the upsert, which sees the
--     proposed row (no course) and not the stored one (with a course). The
--     upsert's UPDATE leaves an omitted course untouched, so the requirement
--     is already met; it now checks the stored row first. A write that
--     explicitly clears the course is still refused, by the UPDATE half.
--
-- Locks: function bodies only; the triggers are unchanged.

set search_path = public;

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
     and not (tg_op = 'INSERT' and exists (
       select 1 from event_attendees a
       where a.event_id = new.event_id
         and a.user_id = new.user_id
         and a.instance_start = new.instance_start
         and a.course_id is not null
     ))
     and (select count(*) from event_courses c where c.event_id = new.event_id) > 1
  then
    raise exception 'event_course_required: pick a course for this event'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

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

  if new.user_id is distinct from v_uid then
    if tg_op = 'UPDATE' then
      new.finish_method := 'host';
    end if;
  else
    -- Only the ranked time and the status are always sent, so a race column
    -- that disagrees with them is left over from the row being replaced. On
    -- INSERT there is no earlier row, so only the status and 'host' rules
    -- apply and a client's gun / chip pair is kept as sent.
    if new.finisher_status is distinct from 'finished' then
      new.gun_time_s := null;
      new.chip_time_s := null;
      new.finish_method := null;
    else
      if new.finish_method = 'host' then
        new.finish_method := null;
      end if;
      if tg_op = 'UPDATE' then
        if new.gun_time_s is distinct from new.duration_s then
          new.gun_time_s := null;
        end if;
        if new.gun_time_s is null and new.chip_time_s is distinct from new.duration_s then
          new.chip_time_s := null;
        end if;
      end if;
    end if;
  end if;

  select e.club_id into v_club from events e where e.id = new.event_id;
  if private.is_race_director(v_club) or private.is_event_organiser(v_club) then
    return new;
  end if;

  select rs.status, rs.finished_at into v_status, v_finished_at
  from race_sessions rs
  where rs.event_id = new.event_id and rs.instance_start = new.instance_start;

  if not found
     or v_status is distinct from 'finished'
     or v_finished_at >= now() - interval '24 hours'
  then
    return new;
  end if;

  raise exception 'race_result_window_closed: race finished at %', v_finished_at
    using errcode = 'check_violation';
end;
$$;

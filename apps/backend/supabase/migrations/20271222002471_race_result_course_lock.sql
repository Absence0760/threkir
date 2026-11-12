-- A result's course and distance lock with its timing (decisions § 2471).
--
-- event_results_race_guard refused a runner's own change to a timing column
-- once the race finished more than 24 h ago, but not a change of course_id or
-- distance_m, so a runner could still move a closed result onto another
-- course's board (where it takes a place) or restate its distance. Both now
-- join the locked set: past the window the runner's write is refused with the
-- same race_result_window_closed error, and a race director or event
-- organiser still corrects a genuine mistake, as for a time. Inside the
-- window nothing changes.
--
-- Only the window check reads the new columns. The runner / host
-- normalisation still runs on a timing change alone, so a course or distance
-- change with no timing change is not re-timed, re-stamped host or sent back
-- for approval -- the same rows reach the same branches as before.
--
-- Locks: a function only; no table lock.

set search_path = public;

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
  v_locked_changed boolean;
  v_session record;
  v_chip integer;
  v_gun integer;
  v_clean boolean;
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
    or new.finisher_status is distinct from old.finisher_status
    or new.start_at is distinct from old.start_at
    or new.finish_at is distinct from old.finish_at
    or new.start_detection is distinct from old.start_detection
    or new.finish_detection is distinct from old.finish_detection;

  v_locked_changed := v_timing_changed
    or new.course_id is distinct from old.course_id
    or new.distance_m is distinct from old.distance_m;

  if v_role = 'service_role' or v_uid is null or not v_locked_changed then
    return new;
  end if;

  select rs.status, rs.finished_at, rs.started_at, rs.start_mode, rs.window_opens_at,
         rs.window_closes_at, rs.is_auto_approve
    into v_session
    from race_sessions rs
   where rs.event_id = new.event_id and rs.instance_start = new.instance_start;

  if v_timing_changed then
    if new.user_id is distinct from v_uid then
      if tg_op = 'UPDATE' then
        new.finish_method := 'host';
        new.start_at := null;
        new.finish_at := null;
        new.start_detection := null;
        new.finish_detection := null;
        new.needs_review := false;
      end if;
    else
      if new.finisher_status is distinct from 'finished' then
        new.gun_time_s := null;
        new.chip_time_s := null;
        new.finish_method := null;
        new.start_at := null;
        new.finish_at := null;
        new.start_detection := null;
        new.finish_detection := null;
        new.needs_review := false;
      else
        if new.finish_method = 'host' then
          new.finish_method := null;
        end if;
        if new.finish_method is distinct from 'auto' then
          new.finish_detection := null;
        end if;
        if v_session.start_mode is distinct from 'self_timed' and tg_op = 'UPDATE' then
          if new.gun_time_s is distinct from new.duration_s then
            new.gun_time_s := null;
          end if;
          if new.gun_time_s is null and new.chip_time_s is distinct from new.duration_s then
            new.chip_time_s := null;
          end if;
        end if;
      end if;

      if v_session.start_mode = 'self_timed' and new.finisher_status = 'finished' then
        new.gun_time_s := null;
        if new.start_at is not null and new.finish_at is not null then
          v_chip := floor(extract(epoch from new.finish_at - new.start_at))::integer;
          if v_chip > 0 then
            new.chip_time_s := v_chip;
            new.duration_s := v_chip;
          end if;
        elsif new.chip_time_s is not null and new.chip_time_s > 0 then
          new.duration_s := new.chip_time_s;
        end if;

        v_clean := new.start_detection = 'gate'
          and v_chip is not null and v_chip > 0
          and new.start_at >= v_session.window_opens_at
          and new.start_at < v_session.window_closes_at
          and private.race_result_plausible(new.event_id, new.instance_start, new.user_id,
                new.course_id, new.start_at, new.finish_at);
        v_clean := coalesce(v_clean, false);
        new.needs_review := not v_clean;
      end if;

      if v_session.start_mode is distinct from 'self_timed'
         and new.finisher_status = 'finished'
         and new.finish_at is not null then
        v_gun := null;
        if v_session.started_at is not null then
          v_gun := floor(extract(epoch from new.finish_at - v_session.started_at))::integer;
          if v_gun < 0 then
            v_gun := null;
          end if;
        end if;
        v_chip := null;
        if new.start_at is not null then
          v_chip := floor(extract(epoch from new.finish_at - new.start_at))::integer;
          if v_chip < 0 then
            v_chip := null;
          end if;
        end if;
        if v_gun is not null and v_chip is not null and v_chip > v_gun then
          v_chip := v_gun;
        end if;
        if v_gun is not null or v_chip is not null then
          new.gun_time_s := v_gun;
          new.chip_time_s := v_chip;
          new.duration_s := coalesce(v_gun, v_chip);
        end if;
      end if;

      if v_session.start_mode = 'self_timed'
         and tg_op = 'UPDATE'
         and old.finisher_status = 'finished'
         and old.start_detection = 'gate'
         and old.finish_detection = 'gate'
         and not old.needs_review
         and not (new.finisher_status = 'finished'
                  and new.start_detection = 'gate'
                  and new.finish_detection = 'gate'
                  and not new.needs_review
                  and new.duration_s < old.duration_s)
      then
        return old;
      end if;

      if tg_op = 'UPDATE' and v_session.status is not null then
        if v_session.start_mode = 'self_timed' then
          if new.needs_review or not v_session.is_auto_approve then
            new.organiser_approved := false;
            new.organiser_approved_by := null;
            new.organiser_approved_at := null;
          else
            new.organiser_approved := true;
            new.organiser_approved_by := new.user_id;
            new.organiser_approved_at := now();
          end if;
        elsif not v_session.is_auto_approve then
          new.organiser_approved := false;
          new.organiser_approved_by := null;
          new.organiser_approved_at := null;
          new.needs_review := new.finisher_status = 'finished';
        end if;
      end if;
    end if;
  end if;

  select e.club_id into v_club from events e where e.id = new.event_id;
  if private.is_race_director(v_club) or private.is_event_organiser(v_club) then
    return new;
  end if;

  if v_session.status is null
     or v_session.status is distinct from 'finished'
     or v_session.finished_at >= now() - interval '24 hours'
  then
    return new;
  end if;

  raise exception 'race_result_window_closed: race finished at %', v_session.finished_at
    using errcode = 'check_violation';
end;
$$;

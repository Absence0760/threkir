-- Real runs check a park course after launch (owner decision 2026-11-20).
--
-- Park courses now go live on automated build checks alone, with nobody
-- walking them first, so the runs people record are the check that follows.
-- Every run that set out on a course either got a time (a
-- global_segment_efforts row on the course's segment) or says why it did not
-- (a park_course_attempts row, 20280106001446). When most of a course's recent
-- runs fail the same way, from enough different runners, the course is
-- probably wrong (a checkpoint off the trail, the line drawn the wrong way
-- round, a stretch that leaves the path), and the sweep here closes it the
-- way an operator would, for an admin to check.
--
--   * private.close_park_courses_failing_runs(p_dry_run, p_now): the sweep.
--     The rule and its five constants live in its body. A closure is the
--     operator's: status 'closed' with a plain-language note the course page
--     shows, one 'close' row in park_course_status_actions with a null actor
--     (the sweep is no person), a pending `reports` row on the course so it
--     sits in /admin/reports where an admin reopens it, and a
--     park_course_report notice to every app admin. Its note is never the
--     catalogue's "Removed from the park catalogue.", so the catalogue sync
--     never reopens it, exactly as with an admin's closure. It deletes
--     nothing, and the course's own pending reports are left for the admin.
--     p_dry_run returns what it would close and changes nothing, whatever
--     the flag says, so an operator can preview before arming it.
--   * Gate: `park_course_attempt_closures` in private.feature_flags, seeded
--     OFF here and declared off in apps/backend/ops/prod_config.json. With it
--     off, a real (not dry) run returns nothing and changes nothing.
--   * A daily pg_cron entry, `close-park-courses-failing-runs`.
--
-- No new index. Per open course the sweep reads its attempts through
-- park_course_attempts_course_idx and its efforts through
-- global_segment_efforts_segment (both lead with the course's key), once a
-- day, over a bounded catalogue; an index on global_segment_efforts would be
-- a build on a populated table for a job that runs once a day.
--
-- Locks (docs/backend/migration_locks.md): a feature-flag row, new functions
-- and a cron row. No table is altered; nothing on a populated table.

insert into private.feature_flags (name, enabled)
values ('park_course_attempt_closures', false)
on conflict (name) do nothing;

create or replace function private.close_park_courses_failing_runs(
  p_dry_run boolean default false,
  p_now timestamptz default now()
)
returns table (
  park_course_id    uuid,
  course_slug       text,
  outcome           text,
  missed_checkpoint smallint,
  progress_band     smallint,
  tries             integer,
  signature_tries   integer,
  signature_runners integer,
  note              text,
  closed            boolean
)
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  -- The evidence is the course's own recent runs. 90 days is a season: long
  -- enough for a quiet course to gather ten runs, short enough that a fault
  -- fixed since (a trail reopened, a reroute) is not judged on old runs.
  c_window constant interval := interval '90 days';
  -- At most the newest 50 runs, so a busy course is judged on how it runs
  -- now rather than diluted by months of good runs before a fault appeared.
  c_max_tries constant integer := 50;
  -- Fewer than 10 runs is too few to tell a course fault from bad luck.
  c_min_tries constant integer := 10;
  -- One failure accounts for at least half of the runs. Below half, most
  -- runners get round, so the course works for most people.
  c_min_share constant numeric := 0.5;
  -- At least 5 different runners share that failure, so one person (or one
  -- small group) repeating the same mistake cannot close a course.
  c_min_runners constant integer := 5;
  c_prefix constant text := 'Closed automatically: ';
  c_suffix constant text := ' We are checking the course.';
  v_enabled boolean;
  v_course record;
  v_since timestamptz;
  v_top record;
  v_note text;
begin
  v_enabled := coalesce(
    (select f.enabled from private.feature_flags f where f.name = 'park_course_attempt_closures'),
    false
  );
  if not p_dry_run and not v_enabled then
    return;
  end if;

  for v_course in
    select pc.id, pc.slug, pc.global_segment_id
      from park_courses pc
      join parks p on p.id = pc.park_id and p.is_active
     where pc.status = 'open'
     order by pc.id
  loop
    if not p_dry_run then
      -- admin_set_park_course_status takes the same row lock, so an admin's
      -- close or reopen and this one serialise, and the evidence below is
      -- read after any action that landed first.
      perform 1 from park_courses pc where pc.id = v_course.id and pc.status = 'open' for update;
      if not found then
        continue;
      end if;
    end if;

    -- A status action (an admin's reopen above all) resets the evidence:
    -- only runs after it count. A run is placed by when it was run, not by
    -- when its row was written, because a re-score (a matcher change's
    -- backfill) rewrites the attempt rows and would otherwise bring runs
    -- from before a reopen back as new.
    v_since := greatest(
      p_now - c_window,
      (select max(a.created_at) from park_course_status_actions a where a.park_course_id = v_course.id)
    );

    -- Efforts carry no matcher version, so every attempt counts whatever
    -- version wrote it. stopped_short and gps_gap are the runner's or the
    -- device's, not the course's: they stay in the count of runs but are
    -- never a failure that closes a course.
    select g.outcome, g.missed_checkpoint, g.progress_band, g.n, g.runners, g.total
      into v_top
      from (
        with recent as (
          select t.user_id, t.outcome, t.missed_checkpoint, t.progress_band
            from (
              select e.user_id, e.run_id, e.started_at as ran_at,
                     null::text as outcome, null::smallint as missed_checkpoint, null::smallint as progress_band
                from global_segment_efforts e
               where e.global_segment_id = v_course.global_segment_id
                 and e.started_at > v_since
                 and e.started_at <= p_now
              union all
              select a.user_id, a.run_id, r.started_at,
                     case when a.outcome in ('wrong_direction', 'skipped_checkpoint', 'off_course') then a.outcome end,
                     case when a.outcome = 'skipped_checkpoint' then a.missed_checkpoint end,
                     case when a.outcome = 'off_course'
                          then least(9, (10 * a.progress_m) / a.course_m)::smallint end
                from park_course_attempts a
                join runs r on r.id = a.run_id
               where a.park_course_id = v_course.id
                 and r.started_at > v_since
                 and r.started_at <= p_now
            ) t
           order by t.ran_at desc, t.run_id desc
           limit c_max_tries
        )
        select s.outcome, s.missed_checkpoint, s.progress_band,
               count(*)::integer as n,
               count(distinct s.user_id)::integer as runners,
               (select count(*)::integer from recent) as total
          from recent s
         where s.outcome is not null
         group by s.outcome, s.missed_checkpoint, s.progress_band
         order by n desc, runners desc, s.outcome, s.missed_checkpoint, s.progress_band
         limit 1
      ) g;

    if not found or v_top.total < c_min_tries
       or v_top.n < c_min_share * v_top.total
       or v_top.runners < c_min_runners then
      continue;
    end if;

    v_note := c_prefix || case v_top.outcome
      when 'skipped_checkpoint' then
        'most recent runs on this course missed checkpoint ' || v_top.missed_checkpoint || '.'
      when 'wrong_direction' then
        'most recent runs on this course went the opposite way round to it.'
      else
        'most recent runs on this course left it between ' || (v_top.progress_band * 10) || '% and '
          || (v_top.progress_band * 10 + 10) || '% of the way along.'
    end || c_suffix;

    park_course_id := v_course.id;
    course_slug := v_course.slug;
    outcome := v_top.outcome;
    missed_checkpoint := v_top.missed_checkpoint;
    progress_band := v_top.progress_band;
    tries := v_top.total;
    signature_tries := v_top.n;
    signature_runners := v_top.runners;
    note := v_note;
    closed := not p_dry_run;

    if not p_dry_run then
      update park_courses pc
         set status = 'closed', status_note = v_note, status_checked_at = now()
       where pc.id = v_course.id;

      insert into park_course_status_actions
        (park_course_id, course_slug, actor_id, action, status_before, note, reports_resolved)
      values (v_course.id, v_course.slug, null, 'close', 'open', v_note, 0);

      -- The admin queue lists a course by its pending reports, so the
      -- closure files one, reported by nobody, for the admin to reopen from.
      insert into reports (reporter_id, target_kind, target_id, reason, notes, signed_out)
      values (null, 'park_course', v_course.id, 'other', v_note, false);

      insert into notifications (user_id, actor_id, kind)
      select a.user_id, null, 'park_course_report' from app_admins a;
    end if;

    return next;
  end loop;
end;
$$;

revoke execute on function private.close_park_courses_failing_runs(boolean, timestamptz)
  from public, anon, authenticated;
grant execute on function private.close_park_courses_failing_runs(boolean, timestamptz) to service_role;

comment on function private.close_park_courses_failing_runs(boolean, timestamptz) is
  'Closes an open park course whose recent runs fail the same way (owner decision 2026-11-20): of its newest '
  '50 runs in 90 days since its last status action, at least 10, one failure (wrong way round, a missed '
  'checkpoint, off the course in one tenth of its length) is half or more and comes from 5 or more runners. '
  'Logs the close with a null actor, files a pending report for /admin/reports and notifies the admins. Does '
  'nothing unless the park_course_attempt_closures flag is on; p_dry_run returns what it would close. '
  'Scheduled by pg_cron entry `close-park-courses-failing-runs` (05:37 UTC daily). 20280107000001.';

-- 05:37 UTC daily, a minute no other job uses; after the night's retention
-- jobs, and late night across the US parks the catalogue covers.
select cron.schedule(
  'close-park-courses-failing-runs',
  '37 5 * * *',
  $$select count(*) from private.close_park_courses_failing_runs()$$
);

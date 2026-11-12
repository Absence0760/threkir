-- This season's record on every park course, in one call (issue #1352): the
-- "Run any time" section of the web Races & courses page lists every course
-- with its current record, and a per-course `global_segment_leaderboard` call
-- would be one round trip per course on every visit as the catalogue grows.
--
-- It is a security-invoker wrapper over `global_segment_leaderboard` with
-- `p_limit` 1 and `p_season` the park's current season, so every visibility,
-- block, shadow-hidden and consent rule that board applies is the rule here,
-- with no second copy to drift. The caller's RLS decides which parks and
-- courses are listed (an inactive park is hidden), and the board's own
-- 42501 still refuses an anonymous caller. A course with no visible effort
-- this season has no row.
--
-- Locks (docs/backend/migration_locks.md): one new function and its grants.

create or replace function public.park_course_records()
returns table (
  course_id uuid,
  season integer,
  user_id uuid,
  display_name text,
  time_seconds integer
)
language sql
stable
security invoker
set search_path = public
as $$
  select pc.id, public.park_season(p), b.user_id, b.display_name, b.time_seconds
  from public.park_courses pc
  join public.parks p on p.id = pc.park_id
  cross join lateral public.global_segment_leaderboard(
    pc.global_segment_id, null, null, 1, null, public.park_season(p)
  ) b;
$$;

revoke execute on function public.park_course_records() from public, anon;
grant  execute on function public.park_course_records() to authenticated, service_role;

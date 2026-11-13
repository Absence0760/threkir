-- "N runners this month" on a park's page (issue #1343, decisions § 2426):
-- for each course in one park, how many runners the caller can see with an
-- effort in the current calendar month where the park is.
--
--   * One call per park page, returning a count per course, rather than a
--     monthly completions board per course: the page wants a number, and a
--     board would ship up to 200 names and avatars per course to count them.
--   * The month is the park's own, from local midnight on the 1st to local
--     midnight on the next 1st, the same reading as park_month() and the
--     monthly boards, so the count and the "This month" board agree.
--   * Every rule the monthly completions board applies to the runners it
--     counts applies here: run visibility to the caller, the block graph in
--     both directions, an active catalogue segment. A shadow-hidden runner is
--     counted, as the board keeps them as an unnamed row. A course with no
--     visible effort this month returns no row.
--   * Signed-in only, like both boards: anon holds no EXECUTE and the body
--     raises 42501 for a missing caller.
--
-- ── Online safety (docs/backend/migration_locks.md) ──
-- Function DDL only. The read is one park's courses through
-- global_segment_efforts' per-segment index, as the monthly board's is.

create function public.park_course_month_runners(p_park_id uuid)
returns table (
  course_id uuid,
  runners integer
)
language plpgsql
stable
security definer
set search_path = public, private
as $$
declare
  caller uuid := auth.uid();
  v_tz text;
  v_month_start timestamp;
begin
  if caller is null then
    raise exception 'park_course_month_runners requires an authenticated caller'
      using errcode = '42501';
  end if;

  select p.timezone into v_tz
  from public.parks p
  where p.id = p_park_id
    and p.is_active;
  if v_tz is null then
    return;
  end if;

  v_month_start := date_trunc('month', now() at time zone v_tz);

  return query
  select pc.id, count(distinct se.user_id)::integer
  from public.park_courses pc
  join public.global_segments gs on gs.id = pc.global_segment_id and gs.is_active
  join public.global_segment_efforts se on se.global_segment_id = pc.global_segment_id
  where pc.park_id = p_park_id
    and se.started_at >= (v_month_start at time zone v_tz)
    and se.started_at < ((v_month_start + interval '1 month') at time zone v_tz)
    and private.is_run_visible_to(se.run_id, caller)
    and not is_blocked_either_way(caller, se.user_id)
  group by pc.id;
end;
$$;

revoke execute on function public.park_course_month_runners(uuid) from public, anon;
grant execute on function public.park_course_month_runners(uuid) to authenticated, service_role;

-- The NPS alert review queue returns every flag in a state.
--
-- admin_park_nps_alerts (20271214131303) ended on `limit 200`, so a state
-- holding more flags (the dismissed and reviewed history grows every day the
-- sweep runs) answered with the first 200 and nothing to say the rest exist.
-- The cap is removed. The web reader walks the result by keyset on `id`
-- (PostgREST filters, orders and limits a set-returning function's rows), so
-- no page is cut at db.max-rows either, and a walk that ends short fails.
-- Same signature, return shape, admin check, status check, order and grants.
--
-- Locks (docs/backend/migration_locks.md): CREATE OR REPLACE FUNCTION only,
-- which locks no table.

create or replace function public.admin_park_nps_alerts(p_status text default 'pending')
returns table (
  id bigint,
  park_course_id uuid,
  course_name text,
  course_slug text,
  course_status text,
  park_name text,
  park_slug text,
  region_code text,
  alert_id text,
  category text,
  title text,
  description text,
  url text,
  match text,
  review_status text,
  reviewed_at timestamptz,
  first_seen_at timestamptz,
  last_seen_at timestamptz,
  gone_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, private, pg_temp
as $$
begin
  if not private.is_admin(auth.uid()) then
    raise exception 'admin_park_nps_alerts: not authorized' using errcode = '42501';
  end if;
  if p_status is null or p_status not in ('pending', 'reviewed', 'dismissed') then
    raise exception 'admin_park_nps_alerts: invalid status' using errcode = '22023';
  end if;
  return query
    select a.id, a.park_course_id, gs.name, pc.slug, pc.status, pk.name, pk.slug, pk.region_code,
           a.alert_id, a.category, a.title, a.description, a.url, a.match, a.review_status, a.reviewed_at,
           a.first_seen_at, a.last_seen_at, a.gone_at
      from park_course_nps_alerts a
      join park_courses pc on pc.id = a.park_course_id
      join parks pk on pk.id = pc.park_id
      join global_segments gs on gs.id = pc.global_segment_id
     where a.review_status = p_status
     order by (a.gone_at is not null), a.first_seen_at, a.id;
end;
$$;

revoke execute on function public.admin_park_nps_alerts(text) from public, anon;
grant execute on function public.admin_park_nps_alerts(text) to authenticated;

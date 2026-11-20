-- A park course's route guide gains a `road` step (issue #1430): the stretch
-- of road a course follows to join two pieces of trail that OSM, or the
-- ground, leaves apart (the Cold Harbor tour road between the Main and
-- Extended Loop trails). `{ kind: 'road', at_m, length_m, name? }`: where it
-- starts, how far it runs (whole metres), and the road's OSM name when it has
-- one. The build emits it for each stretch along a way the park's
-- `trail_review.road_connectors` lists, and refuses any stretch over 250 m
-- (scripts/parks/lib/course_geometry.mjs `ROAD_CONNECTOR_MAX_M`).
--
-- `private.park_course_route_guide_ok` is the 20271212001344 body with the one
-- new kind; every guide it accepted before it still accepts, so the CHECK on
-- park_courses.route_guide needs no revalidation. The vocabularies mirror
-- scripts/parks/lib/route_guide.mjs, apps/web/src/lib/parks/route_guide.ts and
-- apps/mobile_android/lib/route_guide.dart.
--
-- Locks (docs/backend/migration_locks.md): one function replaced in place; no
-- table is touched and no row is written.

create or replace function private.park_course_route_guide_ok(p_guide jsonb)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog, pg_temp
as $$
declare
  v_steps jsonb := p_guide -> 'steps';
  v_step jsonb;
  v_kind text;
  v_allowed text[];
  v_at numeric;
  v_prev numeric := 0;
  v_n int := 0;
  v_last int;
begin
  if jsonb_typeof(p_guide) is distinct from 'object' then return false; end if;
  if exists (select 1 from jsonb_object_keys(p_guide) k where k not in ('version', 'lang', 'getting_there', 'steps')) then
    return false;
  end if;
  if p_guide -> 'version' is distinct from '1'::jsonb then return false; end if;
  if jsonb_typeof(p_guide -> 'lang') is distinct from 'string'
     or (p_guide ->> 'lang') !~ '^[a-z]{2,3}(-[A-Z]{2})?$' then
    return false;
  end if;
  if p_guide ? 'getting_there'
     and (jsonb_typeof(p_guide -> 'getting_there') is distinct from 'string'
          or length(btrim(p_guide ->> 'getting_there')) not between 1 and 500) then
    return false;
  end if;
  if jsonb_typeof(v_steps) is distinct from 'array' or jsonb_array_length(v_steps) not between 2 and 200 then
    return false;
  end if;
  v_last := jsonb_array_length(v_steps);

  for v_step in select * from jsonb_array_elements(v_steps) loop
    v_n := v_n + 1;
    if jsonb_typeof(v_step) is distinct from 'object' then return false; end if;
    v_kind := v_step ->> 'kind';
    v_allowed := case v_kind
      when 'start' then array['kind', 'at_m', 'name', 'way']
      when 'direction' then array['kind', 'at_m', 'rotation', 'keep_on', 'landmark']
      when 'lap' then array['kind', 'at_m', 'lap', 'of']
      when 'junction' then array['kind', 'at_m', 'turn', 'name', 'way']
      when 'road' then array['kind', 'at_m', 'length_m', 'name']
      when 'crossing' then array['kind', 'at_m', 'crossing']
      when 'surface' then array['kind', 'at_m', 'surface']
      when 'climb' then array['kind', 'at_m', 'gain_m', 'length_m']
      when 'checkpoint' then array['kind', 'at_m', 'order', 'of']
      when 'finish' then array['kind', 'at_m']
    end;
    if v_allowed is null then return false; end if;
    if exists (select 1 from jsonb_object_keys(v_step) k where k <> all (v_allowed)) then return false; end if;
    if (v_n = 1) <> (v_kind = 'start') or (v_n = v_last) <> (v_kind = 'finish') then return false; end if;

    if jsonb_typeof(v_step -> 'at_m') is distinct from 'number' then return false; end if;
    v_at := (v_step ->> 'at_m')::numeric;
    if v_at <> trunc(v_at) or v_at < v_prev or v_at > 1000000 then return false; end if;
    if v_kind = 'start' and v_at <> 0 then return false; end if;
    v_prev := v_at;

    if v_step ? 'name'
       and (jsonb_typeof(v_step -> 'name') is distinct from 'string'
            or length(btrim(v_step ->> 'name')) not between 1 and 120) then
      return false;
    end if;
    if v_step ? 'way' and coalesce(v_step ->> 'way' <> all (array['fire_road', 'road', 'path']), true) then
      return false;
    end if;
    if v_kind in ('start', 'junction') and (v_step ? 'name') = (v_step ? 'way') then return false; end if;

    if v_kind = 'direction' then
      if coalesce(v_step ->> 'rotation' <> all (array['clockwise', 'counterclockwise']), true) then return false; end if;
      if (v_step ? 'keep_on') <> (v_step ? 'landmark') then return false; end if;
      if v_step ? 'keep_on' and coalesce(v_step ->> 'keep_on' <> all (array['left', 'right']), true) then return false; end if;
      if v_step ? 'landmark'
         and (jsonb_typeof(v_step -> 'landmark') is distinct from 'string'
              or length(btrim(v_step ->> 'landmark')) not between 1 and 120) then
        return false;
      end if;
    elsif v_kind = 'junction' then
      if coalesce(v_step ->> 'turn' <> all (array['left', 'right', 'straight']), true) then return false; end if;
    elsif v_kind = 'road' then
      if jsonb_typeof(v_step -> 'length_m') is distinct from 'number'
         or (v_step ->> 'length_m')::numeric not between 1 and 1000000
         or (v_step ->> 'length_m')::numeric <> trunc((v_step ->> 'length_m')::numeric) then
        return false;
      end if;
    elsif v_kind = 'crossing' then
      if coalesce(v_step ->> 'crossing' <> all (array['bridge', 'ford']), true) then return false; end if;
    elsif v_kind = 'surface' then
      if coalesce(v_step ->> 'surface' <> all (array['paved', 'gravel', 'dirt', 'unpaved', 'boardwalk']), true) then
        return false;
      end if;
    elsif v_kind = 'climb' then
      if jsonb_typeof(v_step -> 'gain_m') is distinct from 'number'
         or jsonb_typeof(v_step -> 'length_m') is distinct from 'number'
         or (v_step ->> 'gain_m')::numeric not between 1 and 10000
         or (v_step ->> 'length_m')::numeric not between 1 and 1000000
         or (v_step ->> 'gain_m')::numeric <> trunc((v_step ->> 'gain_m')::numeric)
         or (v_step ->> 'length_m')::numeric <> trunc((v_step ->> 'length_m')::numeric) then
        return false;
      end if;
    elsif v_kind in ('lap', 'checkpoint') then
      if jsonb_typeof(v_step -> case v_kind when 'lap' then 'lap' else 'order' end) is distinct from 'number'
         or jsonb_typeof(v_step -> 'of') is distinct from 'number' then
        return false;
      end if;
      declare
        v_k numeric := (v_step ->> case v_kind when 'lap' then 'lap' else 'order' end)::numeric;
        v_of numeric := (v_step ->> 'of')::numeric;
      begin
        if v_k <> trunc(v_k) or v_of <> trunc(v_of) or v_k < (case v_kind when 'lap' then 2 else 1 end)
           or v_k > v_of or v_of > (case v_kind when 'lap' then 1000 else 50 end) then
          return false;
        end if;
      end;
    end if;
  end loop;
  return true;
end;
$$;

comment on function private.park_course_route_guide_ok(jsonb) is
  'Whether a park course route guide is well formed: version 1, a lang tag, an optional getting_there note of '
  '1-500 characters, and 2-200 steps, start first at 0 and finish last, in distance order, each holding only '
  'its kind''s fields from their vocabularies. The CHECK on park_courses.route_guide (decisions § 2448); '
  'a road step, the stretch of road a course follows between two pieces of trail, since 20280102001430.';

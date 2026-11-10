-- The official content catalogue loads itself on every backend release
-- (issue #1190, decisions § 2446), the way the park catalogue does (§ 2429).
--
-- private.load_official_catalogue(catalogue, club, author, now) takes the
-- payload `scripts/official/sync.mjs` builds from
-- `scripts/official/catalogue/` and, in one transaction, publishes each item
-- as the official club:
--
--   plans          a public library plan (`is_template`, `is_public_template`,
--                  `club_id` = the club), its design on the reference week
--                  of 2001-01-01 the way publish_plan_to_library lays a copy
--                  out (§ 2340), so a clone shifts it to the runner's start;
--   gym_routines   a public library routine owned by the club (20271211000002
--                  lets a service-role writer publish one);
--   challenges     one public individual board per period: a `monthly` item
--                  publishes the current month and every month starting in
--                  the next 45 days, a `yearly` item likewise by year, each
--                  under `<slug>@YYYY-MM` / `<slug>@YYYY`, in UTC. A period
--                  more than half over is not opened late (a board already
--                  published for it stays). A board whose window has started
--                  keeps its terms (title, metric, goal, window): only its
--                  publication is written;
--   race_courses   a public club route traced from the race's published map,
--                  claimed and linked to its race listing as `traced`. Only
--                  while the `official_race_courses` flag is on
--                  (20271211000001); off, each item reports `gated` and
--                  nothing is read or written for it.
--
-- One function rather than one per kind: one official-publisher check, one
-- advisory lock and one report per release, and the retire pass of a kind
-- needs that kind's whole list, which only the caller holding the whole
-- catalogue has. Each kind's upsert is its own private helper below.
--
-- Same contract as load_park_catalogue:
--   * service role only, and refused unless the author is an active owner or
--     admin of the verified, public, visible club
--     (`private.is_official_publisher`);
--   * idempotent: every write is guarded by a comparison with what is stored
--     (a plan's or routine's weeks / exercises by their whole design), so an
--     unchanged catalogue writes nothing and reports `unchanged`;
--   * retire, never delete: a plan or routine the catalogue no longer names
--     is unpublished and detached from the club (author-private, so it leaves
--     the club's templates too); a challenge board still open is made
--     private, so its participants keep it; a race course's route is made
--     private and unlinked. Each is reported `retired` once. Naming it again
--     republishes it (`updated`);
--   * a row taken down after a naming dispute (§ 2441) is left alone and
--     reported `held` while the takedown stands;
--   * a change of club owner re-authors every live row to the new account.
--
-- Returns one row per item (per board, for a challenge): kind, slug,
-- target_id and action (`created`, `updated`, `unchanged`, `retired`,
-- `held`, `gated`, `missing_listing`, `claimed_elsewhere`).
--
-- Locks (docs/backend/migration_locks.md): new functions only.

-- ── Plan design: the comparable shape of a library plan's weeks ─────────────
-- The same projection from the payload and from the stored rows, with the
-- payload put through the library redaction first (20271107000001), so a
-- payload field the redaction would drop cannot make every load `updated`.

create or replace function private.official_plan_design_from_payload(p_weeks jsonb)
returns jsonb
language sql
immutable
set search_path = public, private, pg_catalog
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'week_index', (w ->> 'week_index')::int,
           'phase', w ->> 'phase',
           'target_volume_m', round((w ->> 'target_volume_m')::numeric, 2),
           'workouts', (
             select coalesce(jsonb_agg(jsonb_build_object(
                      'day', (o ->> 'day')::int,
                      'kind', o ->> 'kind',
                      'target_distance_m', round((o ->> 'target_distance_m')::numeric, 2),
                      'target_duration_seconds',
                        case when o ->> 'target_distance_m' is not null or o ->> 'kind' = 'race' then null
                             else (o ->> 'target_duration_seconds')::int end,
                      'pace_zone', o ->> 'pace_zone',
                      'structure', private.redact_plan_structure(nullif(o -> 'structure', 'null'::jsonb)),
                      'target_rpe_min', (o ->> 'target_rpe_min')::int,
                      'target_rpe_max', (o ->> 'target_rpe_max')::int)
                    order by (o ->> 'day')::int), '[]'::jsonb)
               from jsonb_array_elements(coalesce(w -> 'workouts', '[]'::jsonb)) o))
         order by (w ->> 'week_index')::int), '[]'::jsonb)
    from jsonb_array_elements(p_weeks) w;
$$;

create or replace function private.official_plan_design_stored(p_plan_id uuid)
returns jsonb
language sql
stable
set search_path = public, private, pg_catalog
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'week_index', w.week_index::int,
           'phase', w.phase::text,
           'target_volume_m', w.target_volume_m,
           'workouts', (
             select coalesce(jsonb_agg(jsonb_build_object(
                      'day', o.scheduled_date - p.start_date,
                      'kind', o.kind::text,
                      'target_distance_m', o.target_distance_m,
                      'target_duration_seconds', o.target_duration_seconds,
                      'pace_zone', o.pace_zone,
                      'structure', o.structure,
                      'target_rpe_min', o.target_rpe_min::int,
                      'target_rpe_max', o.target_rpe_max::int)
                    order by o.scheduled_date), '[]'::jsonb)
               from plan_workouts o
              where o.week_id = w.id))
         order by w.week_index), '[]'::jsonb)
    from plan_weeks w
    join training_plans p on p.id = w.plan_id
   where w.plan_id = p_plan_id;
$$;

-- ── Routine design ──────────────────────────────────────────────────────────

create or replace function private.official_routine_design_from_payload(p_exercises jsonb)
returns jsonb
language sql
immutable
set search_path = public, private, pg_catalog
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'position', (e.ord - 1)::int,
           'exercise_name', e.x ->> 'name',
           'superset_group', (e.x ->> 'superset_group')::int,
           'superset_order', (e.x ->> 'superset_order')::int,
           'modality', e.x ->> 'modality',
           'progression', coalesce(e.x ->> 'progression', 'none'),
           'progression_params', coalesce(nullif(e.x -> 'progression_params', 'null'::jsonb), '{}'::jsonb),
           'notes', nullif(btrim(e.x ->> 'notes'), ''),
           'sets', (
             select coalesce(jsonb_agg(jsonb_build_object(
                      'set_index', (s.ord - 1)::int,
                      'set_type', coalesce(s.x ->> 'set_type', 'working'),
                      'target_reps_min', (s.x ->> 'target_reps_min')::int,
                      'target_reps_max', (s.x ->> 'target_reps_max')::int,
                      'target_weight_kg', round((s.x ->> 'target_weight_kg')::numeric, 2),
                      'target_percent_1rm', round((s.x ->> 'target_percent_1rm')::numeric, 2),
                      'target_rpe', round((s.x ->> 'target_rpe')::numeric, 1),
                      'rest_s', (s.x ->> 'rest_s')::int,
                      'tempo', s.x ->> 'tempo',
                      'target_duration_s', (s.x ->> 'target_duration_s')::int,
                      'target_distance_m', round((s.x ->> 'target_distance_m')::numeric, 2))
                    order by s.ord), '[]'::jsonb)
               from jsonb_array_elements(coalesce(e.x -> 'sets', '[]'::jsonb)) with ordinality s(x, ord)))
         order by e.ord), '[]'::jsonb)
    from jsonb_array_elements(p_exercises) with ordinality e(x, ord);
$$;

create or replace function private.official_routine_design_stored(p_routine_id uuid)
returns jsonb
language sql
stable
set search_path = public, private, pg_catalog
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'position', e.position,
           'exercise_name', e.exercise_name,
           'superset_group', e.superset_group,
           'superset_order', e.superset_order,
           'modality', e.modality,
           'progression', e.progression,
           'progression_params', e.progression_params,
           'notes', e.notes,
           'sets', (
             select coalesce(jsonb_agg(jsonb_build_object(
                      'set_index', s.set_index,
                      'set_type', s.set_type,
                      'target_reps_min', s.target_reps_min,
                      'target_reps_max', s.target_reps_max,
                      'target_weight_kg', s.target_weight_kg,
                      'target_percent_1rm', s.target_percent_1rm,
                      'target_rpe', s.target_rpe,
                      'rest_s', s.rest_s,
                      'tempo', s.tempo,
                      'target_duration_s', s.target_duration_s,
                      'target_distance_m', s.target_distance_m)
                    order by s.set_index), '[]'::jsonb)
               from gym_routine_sets s
              where s.routine_exercise_id = e.id))
         order by e.position), '[]'::jsonb)
    from gym_routine_exercises e
   where e.routine_id = p_routine_id;
$$;

-- The crosswalk row for a slug, pointed at a (new) target.
create or replace function private.official_catalogue_point(p_kind text, p_slug text, p_target uuid)
returns void
language sql
set search_path = public, private, pg_temp
as $$
  insert into private.official_catalogue_items as i (kind, slug, target_id)
  values (p_kind, p_slug, p_target)
  on conflict (kind, slug) do update set target_id = excluded.target_id
  where i.target_id is distinct from excluded.target_id;
$$;

-- ── Plans ───────────────────────────────────────────────────────────────────

create or replace function private.official_catalogue_plan(p_item jsonb, p_club_id uuid, p_author_id uuid)
returns table (target_id uuid, action text)
language plpgsql
set search_path = public, private, pg_temp
as $$
#variable_conflict use_column
declare
  c_start constant date := date '2001-01-01';
  v_slug text := p_item ->> 'slug';
  v_weeks jsonb := p_item -> 'weeks';
  v_end date;
  v_id uuid;
  v_created boolean := false;
  v_written int := 0;
  v_rows int;
  v_week jsonb;
  v_week_id uuid;
begin
  if jsonb_typeof(v_weeks) is distinct from 'array' or jsonb_array_length(v_weeks) = 0 then
    raise exception 'load_official_catalogue: plan % has no weeks', v_slug using errcode = '22023';
  end if;
  v_end := c_start + (p_item ->> 'end_day')::int;

  select p.id into v_id
    from private.official_catalogue_items i
    join training_plans p on p.id = i.target_id
   where i.kind = 'training_plan' and i.slug = v_slug
     for update of p;

  if v_id is not null and private.organiser_dispute_hidden('training_plan', v_id) then
    return query select v_id, 'held'::text;
    return;
  end if;

  if v_id is not null then
    update training_plans p set
      user_id = p_author_id,
      club_id = p_club_id,
      name = p_item ->> 'name',
      goal_event = (p_item ->> 'goal_event')::goal_event,
      goal_distance_m = (p_item ->> 'goal_distance_m')::numeric,
      start_date = c_start,
      end_date = v_end,
      days_per_week = (p_item ->> 'days_per_week')::smallint,
      source = coalesce(p_item ->> 'source', 'generated'),
      is_template = true,
      is_public_template = true,
      status = 'completed',
      updated_at = now()
     where p.id = v_id
       and (p.user_id, p.club_id, p.name, p.goal_event::text, p.goal_distance_m, p.start_date, p.end_date,
            p.days_per_week, p.source, p.is_template, p.is_public_template, p.status)
           is distinct from
           (p_author_id, p_club_id, p_item ->> 'name', p_item ->> 'goal_event',
            round((p_item ->> 'goal_distance_m')::numeric, 2), c_start, v_end,
            (p_item ->> 'days_per_week')::smallint, coalesce(p_item ->> 'source', 'generated'), true, true,
            'completed');
    get diagnostics v_rows = row_count;
    v_written := v_written + v_rows;

    if private.official_plan_design_stored(v_id) is not distinct from
       private.official_plan_design_from_payload(v_weeks) then
      return query select v_id, case when v_written = 0 then 'unchanged' else 'updated' end;
      return;
    end if;
    delete from plan_weeks w where w.plan_id = v_id;
  else
    insert into training_plans (
      user_id, club_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week,
      status, source, is_template, is_public_template
    )
    values (
      p_author_id, p_club_id, p_item ->> 'name', (p_item ->> 'goal_event')::goal_event,
      (p_item ->> 'goal_distance_m')::numeric, c_start, v_end, (p_item ->> 'days_per_week')::smallint,
      'completed', coalesce(p_item ->> 'source', 'generated'), true, true
    )
    returning id into v_id;
    perform private.official_catalogue_point('training_plan', v_slug, v_id);
    v_created := true;
  end if;

  for v_week in select * from jsonb_array_elements(v_weeks) loop
    insert into plan_weeks (plan_id, week_index, phase, target_volume_m)
    values (v_id, (v_week ->> 'week_index')::smallint, (v_week ->> 'phase')::plan_phase,
            (v_week ->> 'target_volume_m')::numeric)
    returning id into v_week_id;

    insert into plan_workouts (
      week_id, scheduled_date, kind, target_distance_m, target_duration_seconds, pace_zone, structure,
      target_rpe_min, target_rpe_max
    )
    select v_week_id, c_start + (o ->> 'day')::int, (o ->> 'kind')::workout_kind,
           (o ->> 'target_distance_m')::numeric, (o ->> 'target_duration_seconds')::int, o ->> 'pace_zone',
           nullif(o -> 'structure', 'null'::jsonb), (o ->> 'target_rpe_min')::smallint,
           (o ->> 'target_rpe_max')::smallint
      from jsonb_array_elements(coalesce(v_week -> 'workouts', '[]'::jsonb)) o;
  end loop;

  return query select v_id, case when v_created then 'created' else 'updated' end;
end;
$$;

-- ── Gym routines ────────────────────────────────────────────────────────────

create or replace function private.official_catalogue_routine(p_item jsonb, p_club_id uuid, p_author_id uuid)
returns table (target_id uuid, action text)
language plpgsql
set search_path = public, private, pg_temp
as $$
#variable_conflict use_column
declare
  v_slug text := p_item ->> 'slug';
  v_exercises jsonb := p_item -> 'exercises';
  v_notes text := nullif(btrim(p_item ->> 'notes'), '');
  v_count int;
  v_id uuid;
  v_created boolean := false;
  v_written int := 0;
  v_rows int;
  v_ex record;
  v_ex_id uuid;
begin
  if jsonb_typeof(v_exercises) is distinct from 'array' or jsonb_array_length(v_exercises) = 0 then
    raise exception 'load_official_catalogue: routine % has no exercises', v_slug using errcode = '22023';
  end if;
  v_count := jsonb_array_length(v_exercises);

  select r.id into v_id
    from private.official_catalogue_items i
    join gym_routines r on r.id = i.target_id
   where i.kind = 'gym_routine' and i.slug = v_slug
     for update of r;

  if v_id is not null and private.organiser_dispute_hidden('gym_routine', v_id) then
    return query select v_id, 'held'::text;
    return;
  end if;

  if v_id is not null then
    update gym_routines r set
      author_id = p_author_id,
      club_id = p_club_id,
      title = p_item ->> 'title',
      notes = v_notes,
      periodisation = coalesce(p_item ->> 'periodisation', 'none'),
      exercise_count = v_count,
      is_public_template = true,
      last_modified_at = now()
     where r.id = v_id
       and (r.author_id, r.club_id, r.title, r.notes, r.periodisation, r.exercise_count, r.is_public_template)
           is distinct from
           (p_author_id, p_club_id, p_item ->> 'title', v_notes, coalesce(p_item ->> 'periodisation', 'none'),
            v_count, true);
    get diagnostics v_rows = row_count;
    v_written := v_written + v_rows;

    if private.official_routine_design_stored(v_id) is not distinct from
       private.official_routine_design_from_payload(v_exercises) then
      return query select v_id, case when v_written = 0 then 'unchanged' else 'updated' end;
      return;
    end if;
    delete from gym_routine_exercises e where e.routine_id = v_id;
    update gym_routines r set last_modified_at = now() where r.id = v_id;
  else
    insert into gym_routines (author_id, club_id, title, notes, periodisation, exercise_count, is_public_template)
    values (p_author_id, p_club_id, p_item ->> 'title', v_notes, coalesce(p_item ->> 'periodisation', 'none'),
            v_count, true)
    returning id into v_id;
    perform private.official_catalogue_point('gym_routine', v_slug, v_id);
    v_created := true;
  end if;

  for v_ex in select x, ord from jsonb_array_elements(v_exercises) with ordinality e(x, ord) loop
    insert into gym_routine_exercises (
      routine_id, exercise_name, position, superset_group, superset_order, modality, progression,
      progression_params, notes
    )
    values (
      v_id, v_ex.x ->> 'name', (v_ex.ord - 1)::int, (v_ex.x ->> 'superset_group')::int,
      (v_ex.x ->> 'superset_order')::int, v_ex.x ->> 'modality', coalesce(v_ex.x ->> 'progression', 'none'),
      coalesce(nullif(v_ex.x -> 'progression_params', 'null'::jsonb), '{}'::jsonb),
      nullif(btrim(v_ex.x ->> 'notes'), '')
    )
    returning id into v_ex_id;

    insert into gym_routine_sets (
      routine_exercise_id, set_index, set_type, target_reps_min, target_reps_max, target_weight_kg,
      target_percent_1rm, target_rpe, rest_s, tempo, target_duration_s, target_distance_m
    )
    select v_ex_id, (s.ord - 1)::int, coalesce(s.x ->> 'set_type', 'working'), (s.x ->> 'target_reps_min')::int,
           (s.x ->> 'target_reps_max')::int, (s.x ->> 'target_weight_kg')::numeric,
           (s.x ->> 'target_percent_1rm')::numeric, (s.x ->> 'target_rpe')::numeric, (s.x ->> 'rest_s')::int,
           s.x ->> 'tempo', (s.x ->> 'target_duration_s')::int, (s.x ->> 'target_distance_m')::numeric
      from jsonb_array_elements(coalesce(v_ex.x -> 'sets', '[]'::jsonb)) with ordinality s(x, ord);
  end loop;

  return query select v_id, case when v_created then 'created' else 'updated' end;
end;
$$;

-- ── Challenges: one board per period ────────────────────────────────────────

create or replace function private.official_catalogue_challenge(
  p_item jsonb,
  p_club_id uuid,
  p_author_id uuid,
  p_now timestamptz
)
returns table (slug text, target_id uuid, action text)
language plpgsql
set search_path = public, private, pg_temp
as $$
#variable_conflict use_column
declare
  c_lookahead constant interval := interval '45 days';
  v_base text := p_item ->> 'slug';
  v_unit text;
  v_step interval;
  v_start timestamptz;
  v_end timestamptz;
  v_slug text;
  v_title text;
  v_description text := nullif(btrim(p_item ->> 'description'), '');
  v_row challenges%rowtype;
  v_found boolean;
  v_rows int;
begin
  case p_item ->> 'recurrence'
    when 'monthly' then v_unit := 'month'; v_step := interval '1 month';
    when 'yearly' then v_unit := 'year'; v_step := interval '1 year';
    else
      raise exception 'load_official_catalogue: challenge % has no recurrence (monthly or yearly)', v_base
        using errcode = '22023';
  end case;

  for v_start in
    select g from generate_series(date_trunc(v_unit, p_now), date_trunc(v_unit, p_now + c_lookahead), v_step) g
  loop
    v_end := v_start + v_step;
    v_slug := v_base || '@' || case v_unit when 'month' then to_char(v_start, 'YYYY-MM') else to_char(v_start, 'YYYY') end;
    v_title := replace(p_item ->> 'title', '{period}',
                       case v_unit when 'month' then to_char(v_start, 'FMMonth YYYY') else to_char(v_start, 'YYYY') end);

    select c.* into v_row
      from private.official_catalogue_items i
      join challenges c on c.id = i.target_id
     where i.kind = 'challenge' and i.slug = v_slug
       for update of c;
    v_found := found;

    if v_found and private.organiser_dispute_hidden('challenge', v_row.id) then
      return query select v_slug, v_row.id, 'held'::text;
      continue;
    end if;

    if not v_found and p_now > v_start + (v_end - v_start) / 2 then
      continue;
    end if;

    if not v_found then
      insert into challenges (creator_id, club_id, title, description, metric, scope, goal_value, activity_type,
                              starts_at, ends_at, is_public)
      values (p_author_id, p_club_id, v_title, v_description, p_item ->> 'metric', 'individual',
              (p_item ->> 'goal_value')::numeric, p_item ->> 'activity_type', v_start, v_end, true)
      returning * into v_row;
      perform private.official_catalogue_point('challenge', v_slug, v_row.id);
      return query select v_slug, v_row.id, 'created'::text;
      continue;
    end if;

    if v_row.starts_at <= p_now then
      update challenges c set creator_id = p_author_id, club_id = p_club_id, is_public = true
       where c.id = v_row.id
         and (c.creator_id, c.club_id, c.is_public) is distinct from (p_author_id, p_club_id, true);
    else
      update challenges c set
        creator_id = p_author_id,
        club_id = p_club_id,
        title = v_title,
        description = v_description,
        metric = p_item ->> 'metric',
        scope = 'individual',
        goal_value = (p_item ->> 'goal_value')::numeric,
        activity_type = p_item ->> 'activity_type',
        starts_at = v_start,
        ends_at = v_end,
        is_public = true
       where c.id = v_row.id
         and (c.creator_id, c.club_id, c.title, c.description, c.metric, c.scope, c.goal_value, c.activity_type,
              c.starts_at, c.ends_at, c.is_public)
             is distinct from
             (p_author_id, p_club_id, v_title, v_description, p_item ->> 'metric', 'individual',
              (p_item ->> 'goal_value')::numeric, p_item ->> 'activity_type', v_start, v_end, true);
    end if;
    get diagnostics v_rows = row_count;
    return query select v_slug, v_row.id, case when v_rows = 0 then 'unchanged' else 'updated' end;
  end loop;
end;
$$;

-- ── Race courses (behind official_race_courses) ─────────────────────────────

create or replace function private.official_catalogue_race_course(p_item jsonb, p_club_id uuid, p_author_id uuid)
returns table (target_id uuid, action text)
language plpgsql
set search_path = public, private, pg_temp
as $$
#variable_conflict use_column
declare
  v_slug text := p_item ->> 'slug';
  v_description text := nullif(btrim(p_item ->> 'description'), '');
  v_listing race_listings%rowtype;
  v_route uuid;
  v_hidden boolean;
  v_created boolean := false;
  v_written int := 0;
  v_rows int;
  v_redrawn boolean := false;
begin
  if p_item ? 'listing_id' then
    select l.* into v_listing from race_listings l where l.id = (p_item ->> 'listing_id')::uuid for update;
  else
    select l.* into v_listing from race_listings l
     where l.provider = p_item -> 'listing' ->> 'provider'
       and l.provider_race_id = p_item -> 'listing' ->> 'provider_race_id'
       for update;
  end if;
  if not found then
    return query select null::uuid, 'missing_listing'::text;
    return;
  end if;
  if private.organiser_dispute_hidden('race_listing', v_listing.id) then
    return query select v_listing.route_id, 'held'::text;
    return;
  end if;
  if v_listing.organiser_club_id is not null and v_listing.organiser_club_id <> p_club_id then
    return query select null::uuid, 'claimed_elsewhere'::text;
    return;
  end if;

  select r.id, r.shadow_hidden into v_route, v_hidden
    from private.official_catalogue_items i
    join routes r on r.id = i.target_id
   where i.kind = 'race_course' and i.slug = v_slug
     for update of r;

  if v_route is not null and (v_hidden or private.organiser_dispute_hidden('route', v_route)) then
    return query select v_route, 'held'::text;
    return;
  end if;

  if v_route is not null then
    select r.waypoints is distinct from p_item -> 'waypoints' into v_redrawn from routes r where r.id = v_route;
    update routes r set
      user_id = p_author_id,
      club_id = p_club_id,
      name = p_item ->> 'name',
      description = v_description,
      waypoints = p_item -> 'waypoints',
      distance_m = (p_item ->> 'distance_m')::numeric,
      elevation_m = (p_item ->> 'elevation_m')::numeric,
      surface = coalesce(p_item ->> 'surface', 'road'),
      is_public = true,
      updated_at = now()
     where r.id = v_route
       and (r.user_id, r.club_id, r.name, r.description, r.waypoints, r.distance_m, r.elevation_m, r.surface,
            r.is_public)
           is distinct from
           (p_author_id, p_club_id, p_item ->> 'name', v_description, p_item -> 'waypoints',
            round((p_item ->> 'distance_m')::numeric, 2), round((p_item ->> 'elevation_m')::numeric, 2),
            coalesce(p_item ->> 'surface', 'road'), true);
    get diagnostics v_rows = row_count;
    v_written := v_written + v_rows;
  else
    insert into routes (user_id, club_id, name, description, waypoints, distance_m, elevation_m, surface, is_public)
    values (p_author_id, p_club_id, p_item ->> 'name', v_description, p_item -> 'waypoints',
            (p_item ->> 'distance_m')::numeric, (p_item ->> 'elevation_m')::numeric,
            coalesce(p_item ->> 'surface', 'road'), true)
    returning id into v_route;
    perform private.official_catalogue_point('race_course', v_slug, v_route);
    v_created := true;
  end if;

  if v_listing.organiser_club_id is null then
    update race_listings l set organiser_club_id = p_club_id, is_verified = true where l.id = v_listing.id;
    insert into race_listing_audit (listing_id, club_id, actor_id, action)
    values (v_listing.id, p_club_id, p_author_id, 'claim');
    v_written := v_written + 1;
  end if;

  if v_listing.route_id is distinct from v_route
     or v_listing.course_source is distinct from 'traced'
     or v_redrawn then
    perform private.apply_race_course_link(v_listing.id, p_club_id, v_route, 'traced', p_author_id, 'link');
    v_written := v_written + 1;
  end if;

  return query select v_route,
    case when v_created then 'created' when v_written = 0 then 'unchanged' else 'updated' end;
end;
$$;

-- ── The loader ──────────────────────────────────────────────────────────────

create or replace function private.load_official_catalogue(
  p_catalogue jsonb,
  p_club_id uuid,
  p_author_id uuid,
  p_now timestamptz default now()
)
returns table (kind text, slug text, target_id uuid, action text)
language plpgsql
security definer
set search_path = public, private, pg_temp
set timezone = 'UTC'
as $$
#variable_conflict use_column
declare
  v_section text;
  v_item jsonb;
  v_courses_on boolean;
  v_res record;
  v_row record;
  v_rows int;
begin
  if not private.is_official_publisher(p_club_id, p_author_id) then
    raise exception 'load_official_catalogue: % is not an active owner or admin of the verified public club %',
      p_author_id, p_club_id
      using errcode = '42501';
  end if;

  foreach v_section in array array['plans', 'gym_routines', 'challenges', 'race_courses'] loop
    if jsonb_typeof(p_catalogue -> v_section) is distinct from 'array' then
      raise exception 'load_official_catalogue: the catalogue has no % list', v_section using errcode = '22023';
    end if;
    if exists (
      select 1 from jsonb_array_elements(p_catalogue -> v_section) e
       where coalesce(e ->> 'slug', '') !~ '^[a-z0-9]+(-[a-z0-9]+)*$' or char_length(e ->> 'slug') > 100
    ) or (select count(distinct e ->> 'slug') from jsonb_array_elements(p_catalogue -> v_section) e)
         <> jsonb_array_length(p_catalogue -> v_section) then
      raise exception 'load_official_catalogue: every % slug must be a unique lowercase slug', v_section
        using errcode = '22023';
    end if;
  end loop;

  perform pg_advisory_xact_lock(hashtext('private.load_official_catalogue'));

  -- Plans
  for v_item in select * from jsonb_array_elements(p_catalogue -> 'plans') loop
    select * into v_res from private.official_catalogue_plan(v_item, p_club_id, p_author_id);
    kind := 'training_plan'; slug := v_item ->> 'slug'; target_id := v_res.target_id; action := v_res.action;
    return next;
  end loop;

  for v_row in
    select i.slug, p.id
      from private.official_catalogue_items i
      join training_plans p on p.id = i.target_id
     where i.kind = 'training_plan'
       and not exists (select 1 from jsonb_array_elements(p_catalogue -> 'plans') e where e ->> 'slug' = i.slug)
       and (p.is_public_template or p.club_id is not null)
       for update of p
  loop
    update training_plans p set is_public_template = false, club_id = null, updated_at = now() where p.id = v_row.id;
    kind := 'training_plan'; slug := v_row.slug; target_id := v_row.id; action := 'retired';
    return next;
  end loop;

  -- Gym routines
  for v_item in select * from jsonb_array_elements(p_catalogue -> 'gym_routines') loop
    select * into v_res from private.official_catalogue_routine(v_item, p_club_id, p_author_id);
    kind := 'gym_routine'; slug := v_item ->> 'slug'; target_id := v_res.target_id; action := v_res.action;
    return next;
  end loop;

  for v_row in
    select i.slug, r.id
      from private.official_catalogue_items i
      join gym_routines r on r.id = i.target_id
     where i.kind = 'gym_routine'
       and not exists (select 1 from jsonb_array_elements(p_catalogue -> 'gym_routines') e where e ->> 'slug' = i.slug)
       and (r.is_public_template or r.club_id is not null)
       for update of r
  loop
    update gym_routines r set is_public_template = false, club_id = null, last_modified_at = now()
     where r.id = v_row.id;
    kind := 'gym_routine'; slug := v_row.slug; target_id := v_row.id; action := 'retired';
    return next;
  end loop;

  -- Challenges
  for v_item in select * from jsonb_array_elements(p_catalogue -> 'challenges') loop
    for v_res in select * from private.official_catalogue_challenge(v_item, p_club_id, p_author_id, p_now) loop
      kind := 'challenge'; slug := v_res.slug; target_id := v_res.target_id; action := v_res.action;
      return next;
    end loop;
  end loop;

  for v_row in
    select i.slug, c.id
      from private.official_catalogue_items i
      join challenges c on c.id = i.target_id
     where i.kind = 'challenge'
       and not exists (select 1 from jsonb_array_elements(p_catalogue -> 'challenges') e
                        where e ->> 'slug' = split_part(i.slug, '@', 1))
       and c.is_public
       and c.ends_at > p_now
       for update of c
  loop
    update challenges c set is_public = false where c.id = v_row.id;
    kind := 'challenge'; slug := v_row.slug; target_id := v_row.id; action := 'retired';
    return next;
  end loop;

  -- Race courses, only while the flag is on
  select coalesce((select f.enabled from private.feature_flags f where f.name = 'official_race_courses'), false)
    into v_courses_on;

  for v_item in select * from jsonb_array_elements(p_catalogue -> 'race_courses') loop
    if v_courses_on then
      select * into v_res from private.official_catalogue_race_course(v_item, p_club_id, p_author_id);
      target_id := v_res.target_id; action := v_res.action;
    else
      target_id := null; action := 'gated';
    end if;
    kind := 'race_course'; slug := v_item ->> 'slug';
    return next;
  end loop;

  if v_courses_on then
    for v_row in
      select i.slug, r.id, r.is_public
        from private.official_catalogue_items i
        join routes r on r.id = i.target_id
       where i.kind = 'race_course'
         and not exists (select 1 from jsonb_array_elements(p_catalogue -> 'race_courses') e where e ->> 'slug' = i.slug)
         for update of r
    loop
      v_rows := 0;
      for v_res in
        select l.id, l.organiser_club_id from race_listings l where l.route_id = v_row.id for update
      loop
        perform private.apply_race_course_link(v_res.id, v_res.organiser_club_id, null, null, p_author_id, 'unlink');
        v_rows := v_rows + 1;
      end loop;
      if v_row.is_public then
        update routes r set is_public = false, updated_at = now() where r.id = v_row.id;
        v_rows := v_rows + 1;
      end if;
      if v_rows > 0 then
        kind := 'race_course'; slug := v_row.slug; target_id := v_row.id; action := 'retired';
        return next;
      end if;
    end loop;
  end if;
end;
$$;

comment on function private.load_official_catalogue(jsonb, uuid, uuid, timestamptz) is
  'Publishes the official content catalogue (scripts/official/catalogue/) as the official club: library plans, '
  'library gym routines, per-period challenge boards and, while official_race_courses is on, traced race '
  'courses. Idempotent (unchanged writes nothing), retires instead of deleting, holds a disputed takedown. '
  'Service role only; refuses an author who is not an official publisher of the club (decisions § 2446).';

revoke execute on function private.official_plan_design_from_payload(jsonb) from public, anon, authenticated;
revoke execute on function private.official_plan_design_stored(uuid) from public, anon, authenticated;
revoke execute on function private.official_routine_design_from_payload(jsonb) from public, anon, authenticated;
revoke execute on function private.official_routine_design_stored(uuid) from public, anon, authenticated;
revoke execute on function private.official_catalogue_point(text, text, uuid) from public, anon, authenticated;
revoke execute on function private.official_catalogue_plan(jsonb, uuid, uuid) from public, anon, authenticated;
revoke execute on function private.official_catalogue_routine(jsonb, uuid, uuid) from public, anon, authenticated;
revoke execute on function private.official_catalogue_challenge(jsonb, uuid, uuid, timestamptz)
  from public, anon, authenticated;
revoke execute on function private.official_catalogue_race_course(jsonb, uuid, uuid) from public, anon, authenticated;
revoke execute on function private.load_official_catalogue(jsonb, uuid, uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function private.load_official_catalogue(jsonb, uuid, uuid, timestamptz) to service_role;

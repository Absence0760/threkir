-- An official park_courses challenge carries its park region (issue #1313).
--
-- `scripts/official/lib/official_catalogue.mjs` now accepts a
-- `park_region_code` on a challenge item (ISO 3166-2, required for the
-- `park_courses` metric and refused for every other), so the yearly park
-- passport ("Run 10 Virginia park courses in {period}") can be published by
-- the release like any other official board. This replaces the per-board
-- helper `private.official_catalogue_challenge` (live body 20271211000004)
-- so the board writes `challenges.park_region_code`, compares it in the
-- `unchanged` test, and refuses an item whose region and metric disagree.
-- `private.load_official_catalogue` calls the helper by name and is
-- unchanged, so idempotence, `held`, the retire pass and the
-- started-board rule (terms frozen once the window opens, region included)
-- carry over as they are.
--
-- Locks (docs/backend/migration_locks.md): a function replacement only.

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
  v_region text := p_item ->> 'park_region_code';
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

  if (coalesce(p_item ->> 'metric', '') = 'park_courses') <> (v_region is not null) then
    raise exception 'load_official_catalogue: challenge % must carry a park_region_code exactly when its metric is park_courses',
      v_base
      using errcode = '22023';
  end if;

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
                              park_region_code, starts_at, ends_at, is_public)
      values (p_author_id, p_club_id, v_title, v_description, p_item ->> 'metric', 'individual',
              (p_item ->> 'goal_value')::numeric, p_item ->> 'activity_type', v_region, v_start, v_end, true)
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
        park_region_code = v_region,
        starts_at = v_start,
        ends_at = v_end,
        is_public = true
       where c.id = v_row.id
         and (c.creator_id, c.club_id, c.title, c.description, c.metric, c.scope, c.goal_value, c.activity_type,
              c.park_region_code, c.starts_at, c.ends_at, c.is_public)
             is distinct from
             (p_author_id, p_club_id, v_title, v_description, p_item ->> 'metric', 'individual',
              (p_item ->> 'goal_value')::numeric, p_item ->> 'activity_type', v_region, v_start, v_end, true);
    end if;
    get diagnostics v_rows = row_count;
    return query select v_slug, v_row.id, case when v_rows = 0 then 'unchanged' else 'updated' end;
  end loop;
end;
$$;

revoke execute on function private.official_catalogue_challenge(jsonb, uuid, uuid, timestamptz)
  from public, anon, authenticated;

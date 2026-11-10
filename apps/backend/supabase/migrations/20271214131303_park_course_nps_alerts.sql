-- NPS closures, flagged for review (issue #1313 Phase 6, decisions § 2453).
--
-- A daily Edge Function (`park-closures-sweep`) reads the NPS Data API's
-- alerts for every active National Park Service park that has a course
-- (`parks.nps_park_code`, migration 20271214131302) and records each alert
-- that may affect a course here, as a flag for an operator. Nothing here
-- changes `park_courses.status`: an NPS alert is free text written for
-- visitors, so a person reads it and closes the course, or dismisses the flag,
-- at /admin/park-alerts.
--
--   * park_course_nps_alerts: one row per (course, NPS alert id). Written
--     only by record_park_nps_alerts as the service role; read by admins
--     through admin_park_nps_alerts, since a row names the reviewing admin.
--   * park_nps_sweep_targets(): the parks and courses the sweep asks about.
--   * record_park_nps_alerts(park, flags, seen ids): upserts a park's flags.
--     An alert whose text changed goes back to pending; one NPS no longer
--     lists is stamped `gone_at` (the sweep only calls this for a park whose
--     alerts it read, so an NPS outage never reads as an alert gone).
--   * admin_park_nps_alerts(status) / admin_review_park_nps_alert(id, action,
--     note): the review queue. `close` closes the course through
--     admin_set_park_course_status (logged, its pending reports resolved) and
--     marks every pending flag on the course reviewed, in one transaction.
--   * invoke_park_closures_sweep() + a daily pg_cron schedule, fail-closed on
--     configuration like the other sweeps: with either Vault entry missing
--     (`park_closures_sweep_url`, `cron_secret`) it calls nothing. The
--     function itself does nothing without NPS_API_KEY.
--
-- Locks (docs/backend/migration_locks.md): a new table, new functions and a
-- cron entry; no existing table is altered.

create table public.park_course_nps_alerts (
  id              bigint generated always as identity primary key,
  park_course_id  uuid not null references public.park_courses (id) on delete cascade,
  alert_id        text not null
                    constraint park_course_nps_alerts_alert_id_len check (char_length(alert_id) between 1 and 64),
  category        text not null
                    constraint park_course_nps_alerts_category_len check (char_length(category) <= 60),
  title           text not null
                    constraint park_course_nps_alerts_title_len check (char_length(title) between 1 and 300),
  description     text not null default ''
                    constraint park_course_nps_alerts_description_len check (char_length(description) <= 2000),
  url             text
                    constraint park_course_nps_alerts_url_chk
                    check (url is null or (char_length(url) <= 500 and url ~ '^https://')),
  match           text not null
                    constraint park_course_nps_alerts_match_check check (match in ('named', 'park_wide')),
  review_status   text not null default 'pending'
                    constraint park_course_nps_alerts_review_status_check
                    check (review_status in ('pending', 'reviewed', 'dismissed')),
  reviewed_by     uuid references auth.users (id) on delete set null,
  reviewed_at     timestamptz,
  first_seen_at   timestamptz not null default now(),
  last_seen_at    timestamptz not null default now(),
  gone_at         timestamptz,
  constraint park_course_nps_alerts_course_alert_key unique (park_course_id, alert_id)
);

create index park_course_nps_alerts_pending_idx
  on public.park_course_nps_alerts (first_seen_at)
  where review_status = 'pending';
create index park_course_nps_alerts_reviewed_by_idx
  on public.park_course_nps_alerts (reviewed_by)
  where reviewed_by is not null;

comment on table public.park_course_nps_alerts is
  'An NPS alert that may affect a park course, for operator review at /admin/park-alerts. Written by the '
  'park-closures-sweep Edge Function through record_park_nps_alerts; never changes a course by itself '
  '(decisions § 2453).';

alter table public.park_course_nps_alerts enable row level security;
revoke all on public.park_course_nps_alerts from public, anon, authenticated;
grant select, insert, update, delete on public.park_course_nps_alerts to service_role;

-- ── The sweep's two calls ───────────────────────────────────────────────────

create or replace function public.park_nps_sweep_targets()
returns table (park_id uuid, nps_park_code text, courses jsonb)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select pk.id, pk.nps_park_code,
         jsonb_agg(jsonb_build_object('id', pc.id, 'name', gs.name) order by pc.slug)
    from parks pk
    join park_courses pc on pc.park_id = pk.id and pc.status <> 'closed'
    join global_segments gs on gs.id = pc.global_segment_id
   where pk.is_active and pk.agency = 'nps' and pk.nps_park_code is not null
   group by pk.id, pk.nps_park_code
   order by pk.nps_park_code;
$$;

revoke execute on function public.park_nps_sweep_targets() from public, anon, authenticated;
grant execute on function public.park_nps_sweep_targets() to service_role;

create or replace function public.record_park_nps_alerts(
  p_park_id uuid,
  p_flags jsonb,
  p_seen_alert_ids text[]
)
returns table (created integer, seen integer, gone integer)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_flag jsonb;
  v_created integer := 0;
  v_seen integer := 0;
  v_gone integer := 0;
  v_row record;
begin
  if jsonb_typeof(p_flags) is distinct from 'array' or p_seen_alert_ids is null then
    raise exception 'record_park_nps_alerts: flags must be a list and the seen ids given' using errcode = '22023';
  end if;
  if not exists (select 1 from parks where id = p_park_id and agency = 'nps') then
    raise exception 'record_park_nps_alerts: % is not a National Park Service park', p_park_id using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_flags) f
     where not exists (select 1 from park_courses pc
                        where pc.id = (f ->> 'course_id')::uuid and pc.park_id = p_park_id)
  ) then
    raise exception 'record_park_nps_alerts: a flag names a course outside the park' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_flags) f
     where not (f ->> 'alert_id' = any (p_seen_alert_ids))
  ) then
    raise exception 'record_park_nps_alerts: a flag names an alert the sweep did not see' using errcode = '22023';
  end if;

  for v_flag in select * from jsonb_array_elements(p_flags) loop
    insert into park_course_nps_alerts as a
      (park_course_id, alert_id, category, title, description, url, match)
    values (
      (v_flag ->> 'course_id')::uuid, v_flag ->> 'alert_id', coalesce(v_flag ->> 'category', ''),
      v_flag ->> 'title', coalesce(v_flag ->> 'description', ''), nullif(v_flag ->> 'url', ''), v_flag ->> 'match'
    )
    on conflict (park_course_id, alert_id) do update set
      category = excluded.category,
      title = excluded.title,
      description = excluded.description,
      url = excluded.url,
      match = excluded.match,
      last_seen_at = now(),
      gone_at = null,
      review_status = case
        when (a.title, a.description, a.category) is distinct from
             (excluded.title, excluded.description, excluded.category) then 'pending'
        else a.review_status
      end,
      reviewed_by = case
        when (a.title, a.description, a.category) is distinct from
             (excluded.title, excluded.description, excluded.category) then null
        else a.reviewed_by
      end,
      reviewed_at = case
        when (a.title, a.description, a.category) is distinct from
             (excluded.title, excluded.description, excluded.category) then null
        else a.reviewed_at
      end
    returning (xmax = 0) as inserted into v_row;
    if v_row.inserted then
      v_created := v_created + 1;
    else
      v_seen := v_seen + 1;
    end if;
  end loop;

  update park_course_nps_alerts a
     set gone_at = now()
    from park_courses pc
   where pc.id = a.park_course_id
     and pc.park_id = p_park_id
     and a.gone_at is null
     and not (a.alert_id = any (p_seen_alert_ids));
  get diagnostics v_gone = row_count;

  return query select v_created, v_seen, v_gone;
end;
$$;

revoke execute on function public.record_park_nps_alerts(uuid, jsonb, text[]) from public, anon, authenticated;
grant execute on function public.record_park_nps_alerts(uuid, jsonb, text[]) to service_role;

-- ── The review queue ────────────────────────────────────────────────────────

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
     order by (a.gone_at is not null), a.first_seen_at, a.id
     limit 200;
end;
$$;

revoke execute on function public.admin_park_nps_alerts(text) from public, anon;
grant execute on function public.admin_park_nps_alerts(text) to authenticated;

create or replace function public.admin_review_park_nps_alert(
  p_id bigint,
  p_action text,
  p_note text default null
)
returns integer
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_admin uuid := auth.uid();
  v_course uuid;
  v_count integer;
begin
  if not private.is_admin(v_admin) then
    raise exception 'admin_review_park_nps_alert: not authorized' using errcode = '42501';
  end if;
  if p_action is null or p_action not in ('close', 'reviewed', 'dismissed') then
    raise exception 'admin_review_park_nps_alert: invalid action' using errcode = '22023';
  end if;

  select a.park_course_id into v_course from park_course_nps_alerts a where a.id = p_id for update;
  if not found then
    raise exception 'admin_review_park_nps_alert: alert not found' using errcode = '02000';
  end if;

  if p_action = 'close' then
    perform public.admin_set_park_course_status(v_course, 'closed', p_note);
    update park_course_nps_alerts a
       set review_status = 'reviewed', reviewed_by = v_admin, reviewed_at = now()
     where a.park_course_id = v_course and (a.review_status = 'pending' or a.id = p_id);
  else
    update park_course_nps_alerts a
       set review_status = p_action, reviewed_by = v_admin, reviewed_at = now()
     where a.id = p_id;
  end if;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.admin_review_park_nps_alert(bigint, text, text) from public, anon;
grant execute on function public.admin_review_park_nps_alert(bigint, text, text) to authenticated;

-- ── The daily schedule ──────────────────────────────────────────────────────

create or replace function public.invoke_park_closures_sweep()
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text;
  v_secret text;
begin
  select decrypted_secret into v_url
  from vault.decrypted_secrets where name = 'park_closures_sweep_url';
  select decrypted_secret into v_secret
  from vault.decrypted_secrets where name = 'cron_secret';
  if v_url is null or v_secret is null then
    return null;
  end if;

  return net.http_post(
    url := v_url,
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_secret,
      'Content-Type', 'application/json'
    ),
    timeout_milliseconds := 60000
  );
end;
$$;

revoke execute on function public.invoke_park_closures_sweep() from public, anon, authenticated;
grant execute on function public.invoke_park_closures_sweep() to service_role;

-- 11:41 UTC: early morning in the US, after NPS staff post overnight alerts.
select cron.schedule(
  'park-closures-sweep',
  '41 11 * * *',
  $$select public.invoke_park_closures_sweep()$$
);

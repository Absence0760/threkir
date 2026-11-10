-- Park course problem reports, part 3: filing, the operator's close and
-- reopen, the audit log and the reads (issue #1346, decisions § 2449). Part 1
-- (20271212000001) widened `reports`; part 2 (20271212000002) added the
-- `park_course_report` notification kind.
--
-- ── Filing ──────────────────────────────────────────────────────────────────
--
-- submit_park_course_report(course, reason, notes, contact_email, reporter)
-- is executable by the service role only. Park staff need no account, so the
-- `park-course-report` Edge Function is the one door: it verifies a JWT when
-- one is sent (and passes that user as the reporter), rate-limits per user or
-- per client address (check_rate_limit, the house per-IP pattern, which keeps
-- a hash and never the address), drops a filled honeypot, and calls this.
-- Nothing a client sends can reach the insert another way: anon and
-- authenticated hold no execute grant here and no write grant on `reports`
-- (20271021000040). Here, whatever the caller:
--   * the course must exist and its park be active;
--   * the reason is one of the four course reasons or 'other';
--   * the notes are required, 1 to 1000 characters after trimming, with
--     control characters other than line breaks and tabs removed, and at most
--     two links (link spam is the common shape of a bot filing);
--   * the contact email is optional, trimmed, at most 254 characters and
--     shaped like an address;
--   * at most 25 pending reports per course, from anyone, and at most 60
--     signed-out reports an hour across every course. These two caps hold
--     however many addresses a sender rotates through; a refusal is SQLSTATE
--     PT429, which PostgREST answers as HTTP 429;
--   * a signed-in reporter has one pending report per course (the existing
--     reports_no_duplicate_pending index), and a signed-out reporter one per
--     course per contact email.
--
-- ── A report changes nothing by itself ──────────────────────────────────────
--
-- A report flags the course for review, as Strava's hazard flag does. Nothing
-- here or in the auto-hide trigger touches park_courses: auto_hide_target
-- returns early for every kind but user, club and route, and a park course
-- has no shadow_hidden column. Only a site admin closes a course.
--
-- ── Notices ─────────────────────────────────────────────────────────────────
--
-- Every app admin gets a `park_course_report` notice on the first pending
-- report on a course (later ones join the queue entry it points at), and on
-- every land-manager request, which the permit decision on #1097 says is
-- honoured by closing the course within two business days.
--
-- ── The operator's action ───────────────────────────────────────────────────
--
-- admin_set_park_course_status(course, 'closed' | 'open', note): site admins
-- only. Closing sets status 'closed' with the note as status_note, which the
-- course page shows beside the closed banner; it needs a note, and refuses
-- the catalogue sync's own "Removed from the park catalogue." note, because
-- the sync reopens a closure carrying that note and never touches any other
-- (scripts/parks/README.md § Loading a park). Closing marks the course's
-- pending reports reviewed with the note as their resolution. Reopening sets
-- status 'open' and clears the note; it refuses a course that is not closed,
-- and a closure the catalogue made, which the catalogue would close again.
-- Every action is in the append-only park_course_status_actions log with the
-- admin's id, read through park_course_status_history.
--
-- ── Reads and retention ─────────────────────────────────────────────────────
--
--   * fetch_pending_reports gains land_manager_since, the oldest pending
--     land-manager request on the target, and sorts those targets after the
--     disputes and before the rest, oldest request first.
--   * fetch_reports_for_target gains contact_email and signed_out.
--   * private.report_target_page_id learns park_course (the course id).
--   * private.purge_stale_reports also clears a contact email 30 days after
--     its report was resolved, unless the report is on legal hold. The report
--     itself keeps the 6 / 12-month windows of § 2234.
--
-- Locks (docs/backend/migration_locks.md): a new table and its indexes (the
-- FKs take SHARE ROW EXCLUSIVE on park_courses, a bounded config table, and
-- on auth.users); new and replaced functions, which lock no relation.

set search_path = public, extensions;

-- ── 1. The audit log ────────────────────────────────────────────────────────

create table park_course_status_actions (
  id              bigint generated always as identity primary key,
  -- ON DELETE SET NULL with the slug kept beside it: the log outlives the
  -- course (the sync never deletes one, but an operator may).
  park_course_id  uuid references park_courses (id) on delete set null,
  course_slug     text not null,
  actor_id        uuid references auth.users (id) on delete set null,
  action          text not null,
  status_before   text not null,
  note            text,
  reports_resolved integer not null default 0,
  created_at      timestamptz not null default now(),
  constraint park_course_status_actions_action_check
    check (action in ('close', 'reopen')),
  constraint park_course_status_actions_note_len
    check (note is null or char_length(note) <= 500),
  constraint park_course_status_actions_slug_len
    check (char_length(course_slug) <= 80)
);

create index park_course_status_actions_course_idx
  on park_course_status_actions (park_course_id, created_at desc);
create index park_course_status_actions_actor_idx
  on park_course_status_actions (actor_id);

-- Read only through park_course_status_history (admins). No client policy and
-- no client grant: default-deny, and so append-only for every client.
alter table park_course_status_actions enable row level security;
revoke all on park_course_status_actions from public, anon, authenticated;
grant select, insert, update, delete on park_course_status_actions to service_role;

-- ── 2. Filing ───────────────────────────────────────────────────────────────

create or replace function submit_park_course_report(
  p_course_id uuid,
  p_reason text,
  p_notes text,
  p_contact_email text default null,
  p_reporter_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  c_course_reasons constant text[] :=
    array['course_hazard', 'course_closure', 'course_off_trail', 'land_manager_request', 'other'];
  c_pending_per_course constant integer := 25;
  c_signed_out_per_hour constant integer := 60;
  v_notes text;
  v_email text;
  v_had_pending boolean;
  v_id uuid;
begin
  if p_reason is null or not (p_reason = any (c_course_reasons)) then
    raise exception 'submit_park_course_report: invalid reason' using errcode = '22023';
  end if;

  v_notes := regexp_replace(
    regexp_replace(coalesce(p_notes, ''), E'[\\u0001-\\u0008\\u000B\\u000C\\u000E-\\u001F\\u007F]', '', 'g'),
    '^[[:space:]]+|[[:space:]]+$', '', 'g');
  if char_length(v_notes) = 0 then
    raise exception 'submit_park_course_report: notes required' using errcode = '22023';
  end if;
  if char_length(v_notes) > 1000 then
    raise exception 'submit_park_course_report: notes too long' using errcode = '22023';
  end if;
  if (select count(*) from regexp_matches(v_notes, 'https?://', 'gi')) > 2 then
    raise exception 'submit_park_course_report: too many links' using errcode = '22023';
  end if;

  v_email := nullif(regexp_replace(coalesce(p_contact_email, ''), '^[[:space:]]+|[[:space:]]+$', '', 'g'), '');
  if v_email is not null and (
    char_length(v_email) > 254
    or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
  ) then
    raise exception 'submit_park_course_report: invalid contact email' using errcode = '22023';
  end if;

  if not exists (
    select 1 from park_courses pc join parks p on p.id = pc.park_id
     where pc.id = p_course_id and p.is_active
  ) then
    raise exception 'submit_park_course_report: course not found' using errcode = '02000';
  end if;

  if p_reporter_id is not null and not exists (select 1 from auth.users u where u.id = p_reporter_id) then
    raise exception 'submit_park_course_report: unknown reporter' using errcode = '42501';
  end if;

  -- Serialise filings on one course so the two caps below are exact under
  -- concurrent submissions.
  perform pg_advisory_xact_lock(hashtextextended('park_course_report:' || p_course_id::text, 0));

  select exists (
    select 1 from reports r
     where r.target_kind = 'park_course' and r.target_id = p_course_id and r.status = 'pending'
  ) into v_had_pending;

  if (select count(*) from reports r
       where r.target_kind = 'park_course' and r.target_id = p_course_id and r.status = 'pending')
     >= c_pending_per_course then
    raise exception 'submit_park_course_report: rate limited'
      using errcode = 'PT429', hint = 'This course already has many reports waiting for review.';
  end if;

  if p_reporter_id is null then
    perform pg_advisory_xact_lock(hashtextextended('park_course_report:signed_out', 0));
    if (select count(*) from reports r
         where r.signed_out and r.created_at > now() - interval '1 hour')
       >= c_signed_out_per_hour then
      raise exception 'submit_park_course_report: rate limited'
        using errcode = 'PT429', hint = 'Too many reports right now. Try again later.';
    end if;
    if v_email is not null and exists (
      select 1 from reports r
       where r.target_kind = 'park_course' and r.target_id = p_course_id and r.status = 'pending'
         and r.signed_out and lower(r.contact_email) = lower(v_email)
    ) then
      raise exception 'submit_park_course_report: already reported' using errcode = '23505';
    end if;
  end if;

  begin
    insert into reports (reporter_id, target_kind, target_id, reason, notes, contact_email, signed_out)
    values (p_reporter_id, 'park_course', p_course_id, p_reason, v_notes, v_email, p_reporter_id is null)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'submit_park_course_report: already reported' using errcode = '23505';
  end;

  if p_reason = 'land_manager_request' or not v_had_pending then
    insert into notifications (user_id, actor_id, kind)
    select a.user_id, null, 'park_course_report' from app_admins a;
  end if;

  return v_id;
end;
$$;

revoke execute on function submit_park_course_report(uuid, text, text, text, uuid) from public, anon, authenticated;
grant execute on function submit_park_course_report(uuid, text, text, text, uuid) to service_role;

comment on function submit_park_course_report(uuid, text, text, text, uuid) is
  'Files a park course problem report (issue #1346, decisions § 2449). Service '
  'role only: the park-course-report Edge Function is the one caller. Validates '
  'the course, reason, notes and contact email; caps pending reports per course '
  '(25) and signed-out reports an hour (60), refusing with PT429; notifies every '
  'app admin on the first pending report on a course and on every land-manager '
  'request. Never changes the course.';

-- ── 3. The operator's close and reopen ──────────────────────────────────────

create or replace function admin_set_park_course_status(
  p_course_id uuid,
  p_status text,
  p_note text default null
)
returns integer
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  c_removed_note constant text := 'Removed from the park catalogue.';
  v_admin uuid := auth.uid();
  v_course record;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_resolved integer := 0;
begin
  if not private.is_admin(v_admin) then
    raise exception 'admin_set_park_course_status: not authorized' using errcode = '42501';
  end if;
  if p_status is null or p_status not in ('closed', 'open') then
    raise exception 'admin_set_park_course_status: invalid status' using errcode = '22023';
  end if;
  if v_note is not null and char_length(v_note) > 500 then
    raise exception 'admin_set_park_course_status: note too long' using errcode = '22023';
  end if;

  select pc.id, pc.slug, pc.status, pc.status_note into v_course
    from park_courses pc where pc.id = p_course_id
    for update;
  if not found then
    raise exception 'admin_set_park_course_status: course not found' using errcode = '02000';
  end if;

  if p_status = 'closed' then
    if v_note is null then
      raise exception 'admin_set_park_course_status: a closure needs a note' using errcode = '22023';
    end if;
    if v_note = c_removed_note then
      raise exception 'admin_set_park_course_status: that note is the catalogue''s own' using errcode = '22023';
    end if;
    update park_courses
       set status = 'closed', status_note = v_note, status_checked_at = now()
     where id = p_course_id;

    update reports
       set status = 'reviewed', resolution = v_note, reviewed_by = v_admin, reviewed_at = now()
     where target_kind = 'park_course' and target_id = p_course_id and status = 'pending';
    get diagnostics v_resolved = row_count;
  else
    if v_course.status <> 'closed' then
      raise exception 'admin_set_park_course_status: the course is not closed' using errcode = '22023';
    end if;
    if v_course.status_note is not distinct from c_removed_note then
      raise exception 'admin_set_park_course_status: the catalogue closed this course'
        using errcode = '22023',
              hint = 'Add the course back to its park manifest; the next release reopens it.';
    end if;
    update park_courses
       set status = 'open', status_note = null, status_checked_at = now()
     where id = p_course_id;
  end if;

  insert into park_course_status_actions
    (park_course_id, course_slug, actor_id, action, status_before, note, reports_resolved)
  values
    (p_course_id, v_course.slug, v_admin,
     case p_status when 'closed' then 'close' else 'reopen' end,
     v_course.status, v_note, v_resolved);

  return v_resolved;
end;
$$;

revoke execute on function admin_set_park_course_status(uuid, text, text) from public, anon;
grant execute on function admin_set_park_course_status(uuid, text, text) to authenticated;

create or replace function park_course_status_history(p_course_id uuid)
returns table (
  id bigint,
  action text,
  actor_id uuid,
  status_before text,
  note text,
  reports_resolved integer,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, private, pg_temp
as $$
begin
  if not private.is_admin(auth.uid()) then
    raise exception 'park_course_status_history: not authorized' using errcode = '42501';
  end if;
  return query
    select a.id, a.action, a.actor_id, a.status_before, a.note, a.reports_resolved, a.created_at
      from park_course_status_actions a
     where a.park_course_id = p_course_id
     order by a.created_at desc, a.id desc;
end;
$$;

revoke execute on function park_course_status_history(uuid) from public, anon;
grant execute on function park_course_status_history(uuid) to authenticated;

-- ── 4. Admin reads ──────────────────────────────────────────────────────────

-- Body from 20271202000003 plus park_course.
create or replace function private.report_target_page_id(p_kind text, p_id uuid)
returns uuid
language sql
stable
set search_path = public, pg_temp
as $$
  select case p_kind
    when 'user'          then (select up.id       from user_profiles up  where up.id = p_id)
    when 'club'          then (select c.id        from clubs c           where c.id = p_id)
    when 'route'         then (select rt.id       from routes rt         where rt.id = p_id)
    when 'run'           then (select ru.id       from runs ru           where ru.id = p_id)
    when 'comment'       then (select rc.run_id   from run_comments rc   where rc.id = p_id)
    when 'club_post'     then (select cp.club_id  from club_posts cp     where cp.id = p_id)
    when 'route_review'  then (select rr.route_id from route_reviews rr  where rr.id = p_id)
    when 'training_plan' then (select tp.id       from training_plans tp where tp.id = p_id)
    when 'gym_routine'   then (select g.id        from gym_routines g    where g.id = p_id)
    when 'challenge'     then (select ch.id       from challenges ch     where ch.id = p_id)
    when 'race_listing'  then (select l.id        from race_listings l   where l.id = p_id)
    when 'park_course'   then (select pc.id       from park_courses pc   where pc.id = p_id)
    else null
  end;
$$;

revoke execute on function private.report_target_page_id(text, uuid) from public, anon, authenticated;

-- Body from 20271202000003 plus land_manager_since. The return type grows,
-- so drop and re-create.
drop function fetch_pending_reports();

create function fetch_pending_reports()
returns table (
  target_kind        text,
  target_id          uuid,
  report_count       bigint,
  reporter_count     bigint,
  reasons            jsonb,
  latest_at          timestamptz,
  shadow_hidden      boolean,
  page_id            uuid,
  organiser_dispute  boolean,
  organiser_clubs    jsonb,
  rename_deadline_at timestamptz,
  land_manager_since timestamptz
)
language plpgsql
stable
security definer
set search_path = public, private
as $$
begin
  if not private.is_admin(auth.uid()) then
    raise exception 'fetch_pending_reports: not authorized'
      using errcode = '42501';
  end if;

  return query
    with pending as (
      select r.target_kind as tk, r.target_id as tid,
             r.reporter_id as rid, r.reason as rsn, r.created_at as cat,
             r.organiser_club_id as ocid
      from reports r
      where r.status = 'pending'
    ),
    by_reason as (
      select g.tk, g.tid, jsonb_object_agg(g.rsn, g.n) as reasons
      from (
        select p.tk, p.tid, p.rsn, count(*) as n
        from pending p
        group by p.tk, p.tid, p.rsn
      ) g
      group by g.tk, g.tid
    ),
    by_club as (
      select x.tk, x.tid,
             jsonb_agg(jsonb_build_object(
               'id', c.id, 'name', c.name, 'slug', c.slug, 'is_verified', c.is_verified
             ) order by x.first_at) as clubs
      from (
        select p.tk, p.tid, p.ocid, min(p.cat) as first_at
        from pending p
        where p.ocid is not null
        group by p.tk, p.tid, p.ocid
      ) x
      join clubs c on c.id = x.ocid
      group by x.tk, x.tid
    ),
    targets as (
      select
        p.tk,
        p.tid,
        count(*)                      as report_count,
        -- One pending row per (reporter, target) is unique-indexed, so each
        -- pending orphan is a distinct deleted (or signed-out) reporter.
        count(distinct p.rid) + count(*) filter (where p.rid is null)
                                      as reporter_count,
        max(p.cat)                    as latest_at,
        bool_or(p.rsn = 'organiser_dispute') as dispute,
        min(p.cat) filter (where p.rsn = 'land_manager_request') as lm_since
      from pending p
      group by p.tk, p.tid
    )
    select
      t.tk,
      t.tid,
      t.report_count,
      t.reporter_count,
      br.reasons,
      t.latest_at,
      private.report_target_shadow_hidden(t.tk, t.tid),
      private.report_target_page_id(t.tk, t.tid),
      t.dispute,
      coalesce(bc.clubs, '[]'::jsonb),
      case when t.dispute then private.organiser_dispute_deadline(t.tk, t.tid) end,
      t.lm_since
    from targets t
    join by_reason br on br.tk = t.tk and br.tid = t.tid
    left join by_club bc on bc.tk = t.tk and bc.tid = t.tid
    order by t.dispute desc, (t.lm_since is not null) desc, t.lm_since asc nulls last, t.latest_at desc;
end;
$$;

revoke execute on function fetch_pending_reports() from public, anon;
grant execute on function fetch_pending_reports() to authenticated;

-- Body from 20271202000003 plus contact_email and signed_out. The return
-- shape grows, so drop and re-create.
drop function fetch_reports_for_target(text, uuid);

create function fetch_reports_for_target(p_target_kind text, p_target_id uuid)
returns table (
  id uuid,
  reporter_id uuid,
  reason text,
  notes text,
  status text,
  created_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by uuid,
  resolution text,
  snapshot_body text,
  snapshot_author_id uuid,
  snapshot_sent_at timestamptz,
  legal_hold boolean,
  purge_after timestamptz,
  snapshot_original_body text,
  organiser_club_id uuid,
  organiser_club_name text,
  organiser_club_slug text,
  organiser_club_verified boolean,
  contact_email text,
  signed_out boolean
)
language plpgsql
stable
security definer
set search_path = public, private
as $$
begin
  if not private.is_admin(auth.uid()) then
    raise exception 'fetch_reports_for_target: not authorized'
      using errcode = '42501';
  end if;

  return query
    select r.id, r.reporter_id, r.reason, r.notes, r.status,
           r.created_at, r.reviewed_at, r.reviewed_by, r.resolution,
           r.snapshot_body, r.snapshot_author_id, r.snapshot_sent_at,
           r.legal_hold,
           private.report_purge_after(r.status, r.reviewed_at, r.legal_hold),
           r.snapshot_original_body,
           r.organiser_club_id, c.name, c.slug, c.is_verified,
           r.contact_email, r.signed_out
    from reports r
    left join clubs c on c.id = r.organiser_club_id
    where r.target_kind = p_target_kind
      and r.target_id = p_target_id
    order by r.created_at desc;
end;
$$;

revoke execute on function fetch_reports_for_target(text, uuid) from public, anon;
grant execute on function fetch_reports_for_target(text, uuid) to authenticated, service_role;

-- ── 5. Retention: the contact email goes 30 days after resolution ──────────

create or replace function private.report_contact_retention()
returns interval
language sql
immutable
set search_path = public, pg_temp
as $$
  select interval '30 days';
$$;

revoke execute on function private.report_contact_retention() from public, anon, authenticated;

comment on function private.report_contact_retention() is
  'How long a resolved report keeps the contact email its reporter gave '
  '(decisions § 2449): long enough for the operator to answer, then cleared by '
  'purge_stale_reports(). The report itself keeps report_retention_window().';

-- Body from 20271021000040 plus the contact-email step, which runs before the
-- delete so a report about to go is not first rewritten.
create or replace function private.purge_stale_reports()
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_deleted bigint;
  v_cleared bigint;
begin
  if not coalesce(
    (select f.enabled from private.feature_flags f where f.name = 'reports_retention_purge'),
    false
  ) then
    return;
  end if;

  with deleted as (
    delete from reports r
    where r.status in ('reviewed', 'dismissed')
      and not r.legal_hold
      and private.report_purge_after(r.status, r.reviewed_at, r.legal_hold) < now()
    returning 1
  )
  select count(*) into v_deleted from deleted;
  if v_deleted > 0 then
    raise notice 'purge_stale_reports: removed % row(s)', v_deleted;
  end if;

  with cleared as (
    update reports r
       set contact_email = null
     where r.contact_email is not null
       and r.status in ('reviewed', 'dismissed')
       and not r.legal_hold
       and r.reviewed_at < now() - private.report_contact_retention()
    returning 1
  )
  select count(*) into v_cleared from cleared;
  if v_cleared > 0 then
    raise notice 'purge_stale_reports: cleared % contact email(s)', v_cleared;
  end if;
end;
$$;

revoke all on function private.purge_stale_reports() from public, anon, authenticated;

comment on function private.purge_stale_reports() is
  'GDPR Art 5(1)(e) storage limitation for reports: deletes resolved, '
  'unheld reports (and their direct-message snapshots) once '
  'private.report_retention_window() has passed since reviewed_at, and clears '
  'a resolved, unheld report''s contact_email once '
  'private.report_contact_retention() has. Never touches a pending or '
  'legal_hold report. Gated on private.feature_flags reports_retention_purge '
  '(absent = off), seeded on by 20271022000001. Scheduled by pg_cron '
  '`purge-stale-reports` (03:59 UTC daily). decisions § 2231, § 2234, § 2449.';

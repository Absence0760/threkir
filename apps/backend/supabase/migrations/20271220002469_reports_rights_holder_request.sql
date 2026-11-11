-- Park course reports: a rights holder's request (decisions § 2469, closing
-- the gap § 2460 recorded).
--
-- The owner of a name, a trade mark or course data a park course may use, who
-- is not a verified club, could only file under 'other': no reason of its own,
-- no priority, no deadline, and refused once a course held 25 pending
-- reports. 'rights_holder_request' is routed like 'land_manager_request':
--
--   * reports_reason_check and reports_park_course_check take it, and a park
--     course is the only target that does;
--   * submit_park_course_report accepts it, requires a contact email for it
--     (a rights holder's request is answered by hand, so one with no address
--     could never be answered), neither counts it toward nor refuses it by
--     the 25-pending cap, and notifies every app admin on each one;
--   * fetch_pending_reports gains rights_holder_since, the oldest pending
--     rights-holder request on the target, and sorts those targets with the
--     land-manager ones, after disputes, oldest request first.
--
-- The answer is due within two business days, as a land-manager request's
-- is; the admin queue computes the deadline (course_report.ts). Nothing here
-- closes a course: an admin decides, with admin_set_park_course_status.
--
-- Locks (docs/backend/migration_locks.md): one table, `reports`, which is not
-- on the high-volume list. Both CHECKs are re-added NOT VALID (a brief ACCESS
-- EXCLUSIVE, no scan) and validated in 20271220012469 under SHARE UPDATE
-- EXCLUSIVE. Every existing row satisfies them: the lists only widen. The
-- functions are replaced, which locks no relation.

set search_path = public, extensions;

alter table reports drop constraint reports_reason_check;
alter table reports
  add constraint reports_reason_check
  check (reason in (
    'spam', 'harassment', 'inappropriate', 'impersonation', 'other', 'organiser_dispute',
    'course_hazard', 'course_closure', 'course_off_trail', 'land_manager_request',
    'rights_holder_request'
  ))
  not valid;

alter table reports drop constraint reports_park_course_check;
alter table reports
  add constraint reports_park_course_check
  check (
    (target_kind <> 'park_course'
      or reason in ('course_hazard', 'course_closure', 'course_off_trail', 'land_manager_request',
                    'rights_holder_request', 'other'))
    and (reason not in ('course_hazard', 'course_closure', 'course_off_trail', 'land_manager_request',
                        'rights_holder_request')
      or target_kind = 'park_course')
    and (contact_email is null or target_kind = 'park_course')
    and (not signed_out or (target_kind = 'park_course' and reporter_id is null))
  )
  not valid;

-- Body from 20271213000003 plus the rights-holder reason, its required email,
-- its exemption from the per-course cap and its notice.
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
    array['course_hazard', 'course_closure', 'course_off_trail', 'land_manager_request',
          'rights_holder_request', 'other'];
  -- The requests that carry a two-business-day promise: never counted toward
  -- or refused by the per-course cap, and each one notifies the admins.
  c_deadline_reasons constant text[] := array['land_manager_request', 'rights_holder_request'];
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
  if v_email is null and p_reason = 'rights_holder_request' then
    raise exception 'submit_park_course_report: contact email required' using errcode = '22023';
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

  if not (p_reason = any (c_deadline_reasons)) and (select count(*) from reports r
       where r.target_kind = 'park_course' and r.target_id = p_course_id and r.status = 'pending'
         and not (r.reason = any (c_deadline_reasons)))
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

  if p_reason = any (c_deadline_reasons) or not v_had_pending then
    insert into notifications (user_id, actor_id, kind)
    select a.user_id, null, 'park_course_report' from app_admins a;
  end if;

  return v_id;
end;
$$;

revoke execute on function submit_park_course_report(uuid, text, text, text, uuid) from public, anon, authenticated;
grant execute on function submit_park_course_report(uuid, text, text, text, uuid) to service_role;

comment on function submit_park_course_report(uuid, text, text, text, uuid) is
  'Files a park course problem report (issue #1346, decisions § 2449, § 2469). '
  'Service role only: the park-course-report Edge Function is the one caller. '
  'Validates the course, reason, notes and contact email (required for a '
  'rights-holder request); caps pending reports per course (25, not counting '
  'land-manager or rights-holder requests, which it never refuses) and '
  'signed-out reports an hour (60), refusing with PT429; notifies every app '
  'admin on the first pending report on a course and on every land-manager or '
  'rights-holder request. Never changes the course.';

-- Body from 20271213000003 plus rights_holder_since. The return type grows,
-- so drop and re-create.
drop function fetch_pending_reports();

create function fetch_pending_reports()
returns table (
  target_kind         text,
  target_id           uuid,
  report_count        bigint,
  reporter_count      bigint,
  reasons             jsonb,
  latest_at           timestamptz,
  shadow_hidden       boolean,
  page_id             uuid,
  organiser_dispute   boolean,
  organiser_clubs     jsonb,
  rename_deadline_at  timestamptz,
  land_manager_since  timestamptz,
  rights_holder_since timestamptz
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
        min(p.cat) filter (where p.rsn = 'land_manager_request') as lm_since,
        min(p.cat) filter (where p.rsn = 'rights_holder_request') as rh_since
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
      t.lm_since,
      t.rh_since
    from targets t
    join by_reason br on br.tk = t.tk and br.tid = t.tid
    left join by_club bc on bc.tk = t.tk and bc.tid = t.tid
    -- least() ignores a null, so a target with either request sorts by its
    -- oldest one.
    order by t.dispute desc,
             (coalesce(t.lm_since, t.rh_since) is not null) desc,
             least(t.lm_since, t.rh_since) asc nulls last,
             t.latest_at desc;
end;
$$;

revoke execute on function fetch_pending_reports() from public, anon;
grant execute on function fetch_pending_reports() to authenticated;

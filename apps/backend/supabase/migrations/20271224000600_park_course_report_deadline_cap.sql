-- A flood of ordinary signed-out reports can no longer lock out the
-- land-manager and rights-holder intake (audit of PR #1359, Medium).
--
-- submit_park_course_report counted every signed-out report into one global
-- 60-an-hour bucket, deadline reasons included, so six addresses at the Edge
-- Function's 10 an hour (or any callers sharing its `unknown` address bucket)
-- spent the hour and the next rights holder or land manager, whose request
-- carries a two-business-day promise (decisions § 2469), was answered 429.
-- The signed-out cap is now two buckets, each with its own advisory lock:
-- ordinary reasons keep 60 an hour and count only themselves; the two
-- deadline reasons get 120 an hour of their own, so they cannot be used to
-- flood either. The 25-pending-a-course cap still leaves the deadline reasons
-- out. The Edge Function's per-address limit splits the same way
-- (park-course-report/lib.ts addressBucket).
--
-- Body from 20271220002469 with the cap split.
--
-- Locks: a function only; no table lock.

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
  -- Signed-out reports an hour, counted apart: the deadline requests have a
  -- bucket of their own, so a flood of ordinary reports cannot spend it, and
  -- a flood of deadline requests cannot spend the ordinary one.
  c_signed_out_per_hour constant integer := 60;
  c_signed_out_deadline_per_hour constant integer := 120;
  v_deadline boolean := p_reason = any (c_deadline_reasons);
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

  if not v_deadline and (select count(*) from reports r
       where r.target_kind = 'park_course' and r.target_id = p_course_id and r.status = 'pending'
         and not (r.reason = any (c_deadline_reasons)))
     >= c_pending_per_course then
    raise exception 'submit_park_course_report: rate limited'
      using errcode = 'PT429', hint = 'This course already has many reports waiting for review.';
  end if;

  if p_reporter_id is null then
    perform pg_advisory_xact_lock(hashtextextended(
      case when v_deadline then 'park_course_report:signed_out:deadline'
           else 'park_course_report:signed_out' end, 0));
    if (select count(*) from reports r
         where r.signed_out and r.created_at > now() - interval '1 hour'
           and (r.reason = any (c_deadline_reasons)) = v_deadline)
       >= (case when v_deadline then c_signed_out_deadline_per_hour else c_signed_out_per_hour end) then
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

  if v_deadline or not v_had_pending then
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
  'land-manager or rights-holder requests, which that cap never refuses) and '
  'signed-out reports an hour in two buckets (60 ordinary reports, 120 '
  'land-manager or rights-holder requests, neither counting the other), '
  'refusing with PT429; notifies every app admin on the first pending report '
  'on a course and on every land-manager or rights-holder request. Never '
  'changes the course.';

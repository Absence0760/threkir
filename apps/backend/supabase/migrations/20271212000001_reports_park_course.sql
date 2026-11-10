-- Park course problem reports, part 1: the reports table (issue #1346,
-- decisions § 2449).
--
-- A runner or a land manager reports a problem with a park course: a hazard,
-- a closure, the line leaving the designated trail, a request from the land
-- manager, or something else. The report lands in the existing `reports`
-- table (20260908_001), so it shares the moderation queue, the legal hold,
-- the retention purge and the reporter's own export:
--
--   * target_kind gains 'park_course'.
--   * reason gains 'course_hazard', 'course_closure', 'course_off_trail' and
--     'land_manager_request'. A park course takes those four or 'other'; the
--     four are taken by a park course only (reports_park_course_check). The
--     general submit_report() keeps its own hard-coded lists, so it refuses
--     the new kind and reasons without being re-emitted.
--   * contact_email: an optional address the reporter gives so the operator
--     can answer, park course reports only, shape-checked and at most 254
--     characters. Cleared when a signed-in reporter's account is deleted
--     (trigger below) and 30 days after the report is resolved
--     (private.purge_stale_reports, 20271212000003).
--   * signed_out: the report was filed without an account. reporter_id is
--     then null, which already reads as "Deleted account" in the queue; the
--     flag lets the queue say "Not signed in" instead. Only a park course
--     report may be filed signed out.
--
-- Filing, the admin close and reopen, and the notices are in 20271212000003.
--
-- Locks (docs/backend/migration_locks.md): one table, `reports`, which is not
-- on the high-volume list. ADD COLUMN of a nullable column, and of a boolean
-- with a constant default, is catalogue-only. Every CHECK is added NOT VALID
-- (brief ACCESS EXCLUSIVE, no scan) and validated in 20271212000004 under
-- SHARE UPDATE EXCLUSIVE, which also builds the index the signed-out cap
-- reads. Every existing row satisfies the widened lists, and none carries a
-- contact email or the signed-out flag.

alter table reports add column contact_email text;
alter table reports add column signed_out boolean not null default false;

alter table reports drop constraint reports_reason_check;
alter table reports
  add constraint reports_reason_check
  check (reason in (
    'spam', 'harassment', 'inappropriate', 'impersonation', 'other', 'organiser_dispute',
    'course_hazard', 'course_closure', 'course_off_trail', 'land_manager_request'
  ))
  not valid;

alter table reports drop constraint reports_target_kind_check;
alter table reports
  add constraint reports_target_kind_check
  check (target_kind in (
    'user', 'club', 'route', 'comment', 'club_post', 'run', 'route_review', 'direct_message',
    'training_plan', 'gym_routine', 'challenge', 'race_listing',
    'park_course'
  ))
  not valid;

-- A park course takes the course reasons or 'other'; the course reasons
-- belong to a park course; a contact email and the signed-out flag only ride
-- a park course report, and a signed-out report names no reporter.
alter table reports
  add constraint reports_park_course_check
  check (
    (target_kind <> 'park_course'
      or reason in ('course_hazard', 'course_closure', 'course_off_trail', 'land_manager_request', 'other'))
    and (reason not in ('course_hazard', 'course_closure', 'course_off_trail', 'land_manager_request')
      or target_kind = 'park_course')
    and (contact_email is null or target_kind = 'park_course')
    and (not signed_out or (target_kind = 'park_course' and reporter_id is null))
  )
  not valid;

alter table reports
  add constraint reports_contact_email_shape
  check (
    contact_email is null
    or (char_length(contact_email) <= 254 and contact_email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')
  )
  not valid;

comment on column reports.contact_email is
  'An address a park course reporter gave for a reply (20271212000001). Personal '
  'data: cleared when the reporter''s account is deleted and 30 days after the '
  'report is resolved (private.purge_stale_reports). Park course reports only.';

comment on column reports.signed_out is
  'The report was filed without an account (a park course report only; '
  'reporter_id is then null). Lets the queue tell a signed-out reporter from a '
  'deleted account.';

-- A deleted reporter's report is kept as evidence with reporter_id set null
-- (20271021000040); the address they gave goes with the account, since
-- nothing else would ever let them reach it again. Fires on the FK's own SET
-- NULL action, which runs as an UPDATE of reporter_id.
create or replace function private.reports_clear_contact_on_reporter_delete()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if old.reporter_id is not null and new.reporter_id is null then
    new.contact_email := null;
  end if;
  return new;
end;
$$;

revoke execute on function private.reports_clear_contact_on_reporter_delete() from public, anon, authenticated;

create trigger reports_clear_contact_on_reporter_delete
  before update of reporter_id on reports
  for each row execute function private.reports_clear_contact_on_reporter_delete();

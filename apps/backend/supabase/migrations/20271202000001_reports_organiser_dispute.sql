-- Organiser name disputes, part 1: the reports table (issue #1363, decisions
-- § 2441).
--
-- A verified organiser's owner or admin reports a club, route, training plan,
-- gym routine, challenge or race listing as impersonating their organisation
-- or copying their content. The report lands in the existing `reports` table
-- (20260908_001) with a new reason and the reporting club:
--
--   * reason 'organiser_dispute' joins reports_reason_check.
--   * target_kind gains 'training_plan', 'gym_routine', 'challenge' and
--     'race_listing'. Those four take ONLY the dispute reason
--     (reports_organiser_dispute_check); the general submit_report() keeps
--     its own hard-coded lists, so it refuses both the new reason and the new
--     kinds without being re-emitted.
--   * organiser_club_id names the verified club the report speaks for. Only
--     a dispute may carry one. ON DELETE SET NULL keeps the report as
--     evidence when the club is deleted.
--
-- Who may file, the no-auto-hide rule and the review actions are in
-- 20271202000003.
--
-- Locks (docs/backend/migration_locks.md): one table. ADD COLUMN of a
-- nullable column with no default is catalogue-only; the FK and every CHECK
-- are added NOT VALID (brief ACCESS EXCLUSIVE, no scan) and validated in
-- 20271202000004 under SHARE UPDATE EXCLUSIVE, which also builds the FK's
-- covering index. Every existing row satisfies the widened lists, and none
-- carries an organiser club.

alter table reports add column organiser_club_id uuid;

alter table reports
  add constraint reports_organiser_club_id_fkey
  foreign key (organiser_club_id) references clubs (id) on delete set null
  not valid;

alter table reports drop constraint reports_reason_check;
alter table reports
  add constraint reports_reason_check
  check (reason in ('spam', 'harassment', 'inappropriate', 'impersonation', 'other', 'organiser_dispute'))
  not valid;

alter table reports drop constraint reports_target_kind_check;
alter table reports
  add constraint reports_target_kind_check
  check (target_kind in (
    'user', 'club', 'route', 'comment', 'club_post', 'run', 'route_review', 'direct_message',
    'training_plan', 'gym_routine', 'challenge', 'race_listing'
  ))
  not valid;

-- A dispute names a disputable kind; the four content kinds added here take
-- nothing but a dispute; only a dispute carries an organiser club.
alter table reports
  add constraint reports_organiser_dispute_check
  check (
    (reason <> 'organiser_dispute'
      or target_kind in ('club', 'route', 'training_plan', 'gym_routine', 'challenge', 'race_listing'))
    and (target_kind not in ('training_plan', 'gym_routine', 'challenge', 'race_listing')
      or reason = 'organiser_dispute')
    and (organiser_club_id is null or reason = 'organiser_dispute')
  )
  not valid;

comment on column reports.organiser_club_id is
  'The verified club an organiser_dispute report speaks for (20271202000001). '
  'Null on every other reason. ON DELETE SET NULL keeps the report as evidence.';

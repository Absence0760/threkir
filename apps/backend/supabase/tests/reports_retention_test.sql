-- Pins 20271021000040 (decisions § 2231): a reporter's account deletion keeps
-- their reports pseudonymised, the moderation queue still counts them, an
-- orphaned report never helps auto-hide, the legal hold is admin-only, and the
-- gated purge deletes only resolved, unheld reports past their window — and
-- nothing at all while the flag is off.

begin;
select plan(39);

-- ─── Fixtures ────────────────────────────────────────────────────────────
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('e7000000-0000-0000-0000-0000000000ad', 'authenticated', 'authenticated', 'admin@retain.local',  '', now(), now()),
  ('e7000000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'victim@retain.local', '', now(), now()),
  ('e7000000-0000-0000-0000-00000000000b', 'authenticated', 'authenticated', 'harass@retain.local', '', now(), now()),
  ('e7000000-0000-0000-0000-00000000000c', 'authenticated', 'authenticated', 'other@retain.local',  '', now(), now()),
  ('e7000000-0000-0000-0000-0000000000e1', 'authenticated', 'authenticated', 'vet1@retain.local',   '', now(), now()),
  ('e7000000-0000-0000-0000-0000000000e2', 'authenticated', 'authenticated', 'vet2@retain.local',   '', now(), now()),
  ('e7000000-0000-0000-0000-0000000000e3', 'authenticated', 'authenticated', 'vet3@retain.local',   '', now(), now());

insert into user_profiles (id, display_name) values
  ('e7000000-0000-0000-0000-00000000000b', 'Harasser'),
  ('e7000000-0000-0000-0000-00000000000c', 'Other')
on conflict (id) do nothing;

insert into app_admins (user_id) values ('e7000000-0000-0000-0000-0000000000ad');

-- The harasser's message to the victim.
insert into direct_messages (id, sender_id, recipient_id, body, created_at) values
  ('e7000000-0000-0000-0000-0000000000d1', 'e7000000-0000-0000-0000-00000000000b',
   'e7000000-0000-0000-0000-00000000000a', 'threat', '2026-10-01T10:00:00Z');

select tests.confirm_consent();

-- ─── Schema ──────────────────────────────────────────────────────────────
select col_is_null('public', 'reports', 'reporter_id', 'reports.reporter_id is nullable');
select is(
  (select confdeltype::text from pg_constraint where conname = 'reports_reporter_id_fkey'),
  'n',
  'reports.reporter_id is ON DELETE SET NULL');
select is(
  (select convalidated from pg_constraint where conname = 'reports_reporter_id_fkey'),
  true,
  'the re-pointed reporter FK is validated');
select col_default_is('public', 'reports', 'legal_hold', 'false', 'legal_hold defaults to false');
select col_not_null('public', 'reports', 'legal_hold', 'legal_hold is not null');

-- ─── The victim reports the message and the harasser, then deletes ──────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select lives_ok(
  $$select submit_report('direct_message', 'e7000000-0000-0000-0000-0000000000d1', 'harassment', 'see message')$$,
  'the victim reports the message');
select lives_ok(
  $$select submit_report('user', 'e7000000-0000-0000-0000-00000000000b', 'harassment', null)$$,
  'the victim reports the harasser');

set local "request.jwt.claims" = '{"sub":"e7000000-0000-0000-0000-00000000000c","role":"authenticated"}';
select lives_ok(
  $$select submit_report('user', 'e7000000-0000-0000-0000-00000000000b', 'spam', null)$$,
  'a second, live reporter reports the harasser');

-- ── Client writes are gone; legal_hold included ─────────────────────────
set local "request.jwt.claims" = '{"sub":"e7000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select throws_ok(
  $$update reports set legal_hold = true where reporter_id = 'e7000000-0000-0000-0000-00000000000a'$$,
  '42501', null,
  'a reporter cannot set legal_hold on their own report');
select throws_ok(
  $$insert into reports (reporter_id, target_kind, target_id, reason, legal_hold)
    values ('e7000000-0000-0000-0000-00000000000a', 'user', 'e7000000-0000-0000-0000-00000000000c', 'spam', true)$$,
  '42501', null,
  'a client cannot insert a pre-held report');
select throws_ok(
  $$delete from reports where reporter_id = 'e7000000-0000-0000-0000-00000000000a'$$,
  '42501', null,
  'a reporter cannot delete their own report');
select throws_ok(
  $$select set_report_legal_hold((select id from reports where reporter_id = 'e7000000-0000-0000-0000-00000000000a' limit 1), true)$$,
  '42501', null,
  'a non-admin cannot call set_report_legal_hold');
select is(
  has_function_privilege('anon', 'public.set_report_legal_hold(uuid, boolean)', 'execute'),
  false,
  'anon holds no EXECUTE on set_report_legal_hold');
select is(
  has_function_privilege('authenticated', 'private.purge_stale_reports()', 'execute'),
  false,
  'no client can run the purge');

set local role postgres;
delete from auth.users where id = 'e7000000-0000-0000-0000-00000000000a';

select is(
  (select count(*)::int from reports
    where target_id in ('e7000000-0000-0000-0000-0000000000d1', 'e7000000-0000-0000-0000-00000000000b')
      and reporter_id is null),
  2,
  'both of the deleted reporter''s reports survive, reporter nulled');
select is(
  (select snapshot_body from reports where target_id = 'e7000000-0000-0000-0000-0000000000d1'),
  'threat',
  'the direct-message snapshot survives the reporter''s deletion');
select is(
  (select snapshot_author_id from reports where target_id = 'e7000000-0000-0000-0000-0000000000d1'),
  'e7000000-0000-0000-0000-00000000000b'::uuid,
  'the snapshot still names the reported sender');

-- ── The admin queue still lists and counts them ─────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7000000-0000-0000-0000-0000000000ad","role":"authenticated"}';
select is(
  (select report_count from fetch_pending_reports()
    where target_kind = 'direct_message' and target_id = 'e7000000-0000-0000-0000-0000000000d1'),
  1::bigint,
  'the orphaned message report is still in the queue');
select is(
  (select reporter_count from fetch_pending_reports()
    where target_kind = 'direct_message' and target_id = 'e7000000-0000-0000-0000-0000000000d1'),
  1::bigint,
  'a deleted reporter still counts as one reporter');
select is(
  (select (report_count, reporter_count)::text from fetch_pending_reports()
    where target_kind = 'user' and target_id = 'e7000000-0000-0000-0000-00000000000b'),
  '(2,2)',
  'one live and one deleted reporter count as two reports and two reporters');
select is(
  (select count(*)::int from fetch_reports_for_target('user', 'e7000000-0000-0000-0000-00000000000b')
    where reporter_id is null),
  1,
  'the detail read returns the orphaned report with a null reporter');

-- ── Legal hold through the admin path ───────────────────────────────────
select is(
  set_report_legal_hold(
    (select id from fetch_reports_for_target('direct_message', 'e7000000-0000-0000-0000-0000000000d1')), true),
  true,
  'an admin places a legal hold');
select is(
  (select legal_hold from fetch_reports_for_target('direct_message', 'e7000000-0000-0000-0000-0000000000d1')),
  true,
  'the detail read shows the hold');
select throws_ok(
  $$select set_report_legal_hold('e7000000-0000-0000-0000-ffffffffffff', true)$$,
  'P0002', null,
  'an unknown report id answers not found');

-- ── An orphaned report never helps auto-hide ────────────────────────────
set local role postgres;
set local "request.jwt.claims" = '';
insert into runs (user_id, started_at, distance_m, duration_s, source, is_public, metadata)
select v.uid, now(), 1000, 300, 'app', true, '{"activity_type":"run"}'::jsonb
from (values
  ('e7000000-0000-0000-0000-0000000000e1'::uuid),
  ('e7000000-0000-0000-0000-0000000000e2'::uuid),
  ('e7000000-0000-0000-0000-0000000000e3'::uuid)
) as v(uid), generate_series(1, 5);

insert into reports (reporter_id, target_kind, target_id, reason, status)
values ('e7000000-0000-0000-0000-0000000000e3', 'user', 'e7000000-0000-0000-0000-00000000000c', 'spam', 'pending');
delete from auth.users where id = 'e7000000-0000-0000-0000-0000000000e3';
insert into reports (reporter_id, target_kind, target_id, reason, status)
values
  ('e7000000-0000-0000-0000-0000000000e1', 'user', 'e7000000-0000-0000-0000-00000000000c', 'spam', 'pending'),
  ('e7000000-0000-0000-0000-0000000000e2', 'user', 'e7000000-0000-0000-0000-00000000000c', 'spam', 'pending');

select is(
  (select shadow_hidden from user_profiles where id = 'e7000000-0000-0000-0000-00000000000c'),
  false,
  'two vetted reporters plus a deleted one do not trip the three-reporter auto-hide');

-- ─── The purge ───────────────────────────────────────────────────────────
-- Fixtures against one target so the counts below see nothing else.
insert into reports (id, reporter_id, target_kind, target_id, reason, status, created_at, reviewed_at, legal_hold) values
  ('e7000000-0000-0000-0000-0000000000f1', null, 'club', 'e7000000-0000-0000-0000-00000000c1ab', 'spam', 'dismissed', now() - interval '8 months',  now() - interval '7 months',  false),
  ('e7000000-0000-0000-0000-0000000000f2', null, 'club', 'e7000000-0000-0000-0000-00000000c1ab', 'spam', 'dismissed', now() - interval '6 months',  now() - interval '5 months',  false),
  ('e7000000-0000-0000-0000-0000000000f3', null, 'club', 'e7000000-0000-0000-0000-00000000c1ab', 'spam', 'reviewed',  now() - interval '8 months',  now() - interval '7 months',  false),
  ('e7000000-0000-0000-0000-0000000000f4', null, 'club', 'e7000000-0000-0000-0000-00000000c1ab', 'spam', 'reviewed',  now() - interval '14 months', now() - interval '13 months', false),
  ('e7000000-0000-0000-0000-0000000000f5', null, 'club', 'e7000000-0000-0000-0000-00000000c1ab', 'spam', 'pending',   now() - interval '3 years',   null,                         false),
  ('e7000000-0000-0000-0000-0000000000f6', null, 'club', 'e7000000-0000-0000-0000-00000000c1ab', 'spam', 'reviewed',  now() - interval '3 years',   now() - interval '2 years',   true),
  ('e7000000-0000-0000-0000-0000000000f7', null, 'club', 'e7000000-0000-0000-0000-00000000c1ab', 'spam', 'dismissed', now() - interval '3 years',   null,                         false);
insert into reports (id, reporter_id, target_kind, target_id, reason, status, created_at, reviewed_at,
                     snapshot_body, snapshot_author_id, snapshot_sent_at) values
  ('e7000000-0000-0000-0000-0000000000f8', null, 'direct_message', 'e7000000-0000-0000-0000-00000000d0d0', 'harassment', 'dismissed',
   now() - interval '8 months', now() - interval '7 months', 'old words', 'e7000000-0000-0000-0000-00000000000b', now() - interval '9 months');

select is(private.report_retention_window('dismissed'), interval '6 months', 'no action taken: 6 months');
select is(private.report_retention_window('reviewed'), interval '12 months', 'action taken: 12 months');
select is(private.report_retention_window('pending'), null::interval, 'an open report has no window');

select is(
  (select enabled from private.feature_flags where name = 'reports_retention_purge'),
  true,
  'the purge ships switched on (20271022000001)');

delete from private.feature_flags where name = 'reports_retention_purge';
select private.purge_stale_reports();
select is(
  (select count(*)::int from reports where id::text like 'e7000000-0000-0000-0000-0000000000f_'),
  8,
  'flag absent: the purge deletes nothing');

insert into private.feature_flags (name, enabled) values ('reports_retention_purge', false);
select private.purge_stale_reports();
select is(
  (select count(*)::int from reports where id::text like 'e7000000-0000-0000-0000-0000000000f_'),
  8,
  'flag present but off: the purge deletes nothing');

update private.feature_flags set enabled = true where name = 'reports_retention_purge';
select private.purge_stale_reports();
select is(
  (select array_agg(right(id::text, 2) order by id) from reports where id::text like 'e7000000-0000-0000-0000-0000000000f_'),
  array['f2', 'f3', 'f5', 'f6', 'f7'],
  'flag on: only resolved reports past their window are deleted (f1 dismissed 7mo, f4 reviewed 13mo, f8 dismissed 7mo)');
select is(
  (select count(*)::int from reports where snapshot_body = 'old words'),
  0,
  'a purged direct-message report takes its snapshot with it');
select is(
  (select count(*)::int from reports where reporter_id is null and target_id = 'e7000000-0000-0000-0000-0000000000d1'),
  1,
  'the held, pending message report is untouched');

-- ─── The Resolved list never hides the reports closest to deletion ──────
-- A long-overdue dismissed report (the purge is off, so it is still here) on
-- its own target must be the first row even at a cap of one.
insert into reports (reporter_id, target_kind, target_id, reason, status, created_at, reviewed_at) values
  (null, 'club', 'e7000000-0000-0000-0000-00000000c2ab', 'spam', 'dismissed', now() - interval '10 years', now() - interval '10 years'),
  (null, 'club', 'e7000000-0000-0000-0000-00000000c3ab', 'spam', 'reviewed',  now(),                      now());
update private.feature_flags set enabled = false where name = 'reports_retention_purge';

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7000000-0000-0000-0000-0000000000ad","role":"authenticated"}';
select is(
  (select target_id from fetch_resolved_reports(1)),
  'e7000000-0000-0000-0000-00000000c2ab'::uuid,
  'the capped Resolved list leads with the earliest purge date, not the latest resolution');
select is(
  (select held_count from fetch_resolved_reports() where target_id = 'e7000000-0000-0000-0000-00000000c1ab'),
  1::bigint,
  'the Resolved list counts held reports per target');
set local role postgres;

-- ─── The cron registration ───────────────────────────────────────────────
select is(
  (select count(*)::int from cron.job where jobname = 'purge-stale-reports'),
  1,
  'pg_cron entry purge-stale-reports is registered');
select is(
  (select schedule from cron.job where jobname = 'purge-stale-reports'),
  '59 3 * * *',
  'purge-stale-reports runs daily at 03:59 UTC');
select is(
  (select command from cron.job where jobname = 'purge-stale-reports'),
  'select private.purge_stale_reports()',
  'purge-stale-reports calls the gated purge');

select * from finish();
rollback;

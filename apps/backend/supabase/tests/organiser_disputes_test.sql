-- Pins 20271202000001..4: organiser name disputes (issue #1363, decisions
-- § 2441).
--
-- Only an active owner or admin of a verified, public, unhidden club files a
-- dispute; an unverified club's owner, a plain member and anon are refused,
-- and the general submit_report() refuses the reason. A dispute never
-- auto-hides, even from three vetted reporters. Disputed targets sort first
-- in the admin queue, which names the reporting club. Only a site admin acts:
-- hide (shadow_hidden for a club or route, unpublish plus a republish lock
-- for a template, a released claim for a race listing), a rename notice with
-- a deadline, or dismiss. Every action is logged with the reviewer, and both
-- sides are notified with no actor and read their side without the reviewer.

begin;
select plan(63);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('d15e0000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'od-org-owner@od.local', '', now(), now()),
  ('d15e0000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'od-org-admin@od.local', '', now(), now()),
  ('d15e0000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'od-org-member@od.local', '', now(), now()),
  ('d15e0000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'od-unverified@od.local', '', now(), now()),
  ('d15e0000-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'od-fan@od.local', '', now(), now()),
  ('d15e0000-0000-0000-0000-000000000006', 'authenticated', 'authenticated', 'od-site-admin@od.local', '', now(), now()),
  ('d15e0000-0000-0000-0000-000000000007', 'authenticated', 'authenticated', 'od-org2-owner@od.local', '', now(), now()),
  ('d15e0000-0000-0000-0000-000000000008', 'authenticated', 'authenticated', 'od-org3-owner@od.local', '', now(), now())
on conflict (id) do nothing;

select tests.confirm_consent();

insert into app_admins (user_id) values ('d15e0000-0000-0000-0000-000000000006');

-- V, V2, V3: verified organisers. U: an unverified club. F: the fan club.
insert into clubs (id, owner_id, name, slug, is_public, is_verified)
values
  ('d15e1111-0000-0000-0000-000000000001', 'd15e0000-0000-0000-0000-000000000001', 'OD Marathon', 'od-marathon', true, true),
  ('d15e1111-0000-0000-0000-000000000002', 'd15e0000-0000-0000-0000-000000000004', 'OD Unverified', 'od-unverified', true, false),
  ('d15e1111-0000-0000-0000-000000000003', 'd15e0000-0000-0000-0000-000000000005', 'OD Marathon Fans', 'od-marathon-fans', true, false),
  ('d15e1111-0000-0000-0000-000000000004', 'd15e0000-0000-0000-0000-000000000007', 'OD Second Org', 'od-second-org', true, true),
  ('d15e1111-0000-0000-0000-000000000005', 'd15e0000-0000-0000-0000-000000000008', 'OD Third Org', 'od-third-org', true, true);

insert into club_members (club_id, user_id, role, status)
values
  ('d15e1111-0000-0000-0000-000000000001', 'd15e0000-0000-0000-0000-000000000001', 'owner', 'active'),
  ('d15e1111-0000-0000-0000-000000000001', 'd15e0000-0000-0000-0000-000000000002', 'admin', 'active'),
  ('d15e1111-0000-0000-0000-000000000001', 'd15e0000-0000-0000-0000-000000000003', 'member', 'active'),
  ('d15e1111-0000-0000-0000-000000000002', 'd15e0000-0000-0000-0000-000000000004', 'owner', 'active'),
  ('d15e1111-0000-0000-0000-000000000003', 'd15e0000-0000-0000-0000-000000000005', 'owner', 'active'),
  ('d15e1111-0000-0000-0000-000000000004', 'd15e0000-0000-0000-0000-000000000007', 'owner', 'active'),
  ('d15e1111-0000-0000-0000-000000000005', 'd15e0000-0000-0000-0000-000000000008', 'owner', 'active')
on conflict (club_id, user_id) do update set role = excluded.role, status = excluded.status;

-- The fan's copies.
insert into routes (id, user_id, name, waypoints, distance_m, is_public)
values ('d15e2222-0000-0000-0000-000000000001', 'd15e0000-0000-0000-0000-000000000005',
        'OD Marathon Course', '[{"lat":40.0,"lng":-73.0},{"lat":40.01,"lng":-73.0}]', 42195, true),
       ('d15e2222-0000-0000-0000-000000000002', 'd15e0000-0000-0000-0000-000000000001',
        'OD Org Own Route', '[{"lat":40.0,"lng":-73.0},{"lat":40.01,"lng":-73.0}]', 5000, true);

insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, status,
                            is_template, is_public_template)
values ('d15e3333-0000-0000-0000-000000000001', 'd15e0000-0000-0000-0000-000000000005',
        'OD Marathon Official Plan', 'distance_full', 42195, '2036-01-01', '2036-04-01', 'completed', true, true),
       ('d15e3333-0000-0000-0000-000000000002', 'd15e0000-0000-0000-0000-000000000005',
        'OD Private Plan', 'distance_full', 42195, '2036-01-01', '2036-04-01', 'active', false, false);

insert into gym_routines (id, author_id, is_public_template, title, exercise_count)
values ('d15e4444-0000-0000-0000-000000000001', 'd15e0000-0000-0000-0000-000000000005', true, 'OD Marathon Strength', 0);

insert into challenges (id, creator_id, title, metric, scope, goal_value, starts_at, ends_at, is_public)
values ('d15e5555-0000-0000-0000-000000000001', 'd15e0000-0000-0000-0000-000000000005',
        'OD Marathon Challenge', 'distance', 'individual', 100000, now(), now() + interval '30 days', true);

-- A listing claimed by the second organiser, and one nobody claimed.
insert into race_listings (id, provider, provider_race_id, name, race_date, distance_m, is_verified, organiser_club_id)
values
  ('d15e6666-0000-0000-0000-000000000001', 'manual', null, 'OD Marathon 2036', '2036-06-01', 42195, true,
   'd15e1111-0000-0000-0000-000000000004'),
  ('d15e6666-0000-0000-0000-000000000002', 'manual', null, 'OD Unclaimed 10K', '2036-06-02', 10000, false, null);

-- Three vetted reporters (five public runs each): the owners of V, V2, V3.
insert into runs (user_id, started_at, distance_m, duration_s, source, is_public, metadata)
select v.uid, now(), 1000, 300, 'app', true, '{"activity_type":"run"}'::jsonb
from (values
  ('d15e0000-0000-0000-0000-000000000001'::uuid),
  ('d15e0000-0000-0000-0000-000000000007'::uuid),
  ('d15e0000-0000-0000-0000-000000000008'::uuid)
) as v(uid), generate_series(1, 5);

-- ── the gate ────────────────────────────────────────────────────────────────

set local role anon;
select throws_ok(
  $$ select submit_organiser_dispute('club', 'd15e1111-0000-0000-0000-000000000003', 'd15e1111-0000-0000-0000-000000000001') $$,
  '42501', null, 'anon cannot file a dispute');
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"d15e0000-0000-0000-0000-000000000004","role":"authenticated"}';
select throws_ok(
  $$ select submit_organiser_dispute('club', 'd15e1111-0000-0000-0000-000000000003', 'd15e1111-0000-0000-0000-000000000002') $$,
  '42501', 'only an owner or admin of a verified club can report a naming dispute',
  'an unverified club''s owner is refused');
select throws_ok(
  $$ select submit_organiser_dispute('club', 'd15e1111-0000-0000-0000-000000000003', 'd15e1111-0000-0000-0000-000000000001') $$,
  '42501', 'only an owner or admin of a verified club can report a naming dispute',
  'nobody can file for a club they do not administer');
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"d15e0000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok(
  $$ select submit_organiser_dispute('club', 'd15e1111-0000-0000-0000-000000000003', 'd15e1111-0000-0000-0000-000000000001') $$,
  '42501', 'only an owner or admin of a verified club can report a naming dispute',
  'a plain member of a verified club is refused');
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"d15e0000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok(
  $$ select submit_report('club', 'd15e1111-0000-0000-0000-000000000003', 'organiser_dispute') $$,
  '22023', null, 'the general report path refuses the dispute reason');
select throws_ok(
  $$ select submit_report('training_plan', 'd15e3333-0000-0000-0000-000000000001', 'spam') $$,
  '22023', null, 'the general report path refuses the new content kinds');
select throws_ok(
  $$ select submit_organiser_dispute('club', 'd15e1111-0000-0000-0000-000000000001', 'd15e1111-0000-0000-0000-000000000001') $$,
  '22023', null, 'an organiser cannot dispute its own club');
select throws_ok(
  $$ select submit_organiser_dispute('route', 'd15e2222-0000-0000-0000-000000000002', 'd15e1111-0000-0000-0000-000000000001') $$,
  '22023', null, 'an organiser cannot dispute its own content');
select throws_ok(
  $$ select submit_organiser_dispute('training_plan', 'd15e3333-0000-0000-0000-000000000002', 'd15e1111-0000-0000-0000-000000000001') $$,
  '02000', null, 'a private plan cannot be disputed (the organiser cannot have seen it)');
select throws_ok(
  $$ select submit_organiser_dispute('race_listing', 'd15e6666-0000-0000-0000-000000000002', 'd15e1111-0000-0000-0000-000000000001') $$,
  '02000', null, 'an unclaimed race listing is claimed, not disputed');
select throws_ok(
  $$ select submit_organiser_dispute('run', 'd15e2222-0000-0000-0000-000000000001', 'd15e1111-0000-0000-0000-000000000001') $$,
  '22023', null, 'a run is not a disputable kind');
select throws_ok(
  $$ insert into reports (reporter_id, target_kind, target_id, reason, organiser_club_id)
     values ('d15e0000-0000-0000-0000-000000000001', 'club', 'd15e1111-0000-0000-0000-000000000003',
             'organiser_dispute', 'd15e1111-0000-0000-0000-000000000001') $$,
  '42501', null, 'no direct insert into reports');

select lives_ok(
  $$ select submit_organiser_dispute('club', 'd15e1111-0000-0000-0000-000000000003',
       'd15e1111-0000-0000-0000-000000000001', 'This fan club uses our race name.') $$,
  'the verified club''s owner files against the fan club');
select lives_ok(
  $$ select submit_organiser_dispute('training_plan', 'd15e3333-0000-0000-0000-000000000001', 'd15e1111-0000-0000-0000-000000000001') $$,
  'the owner files against a copied plan template');
select lives_ok(
  $$ select submit_organiser_dispute('gym_routine', 'd15e4444-0000-0000-0000-000000000001', 'd15e1111-0000-0000-0000-000000000001') $$,
  'the owner files against a copied routine');
select lives_ok(
  $$ select submit_organiser_dispute('race_listing', 'd15e6666-0000-0000-0000-000000000001', 'd15e1111-0000-0000-0000-000000000001') $$,
  'the owner files against a race claimed by another club');
select throws_ok(
  $$ select submit_organiser_dispute('club', 'd15e1111-0000-0000-0000-000000000003', 'd15e1111-0000-0000-0000-000000000001') $$,
  '23505', null, 'a second pending dispute on the same target is refused');
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"d15e0000-0000-0000-0000-000000000002","role":"authenticated"}';
select lives_ok(
  $$ select submit_organiser_dispute('challenge', 'd15e5555-0000-0000-0000-000000000001', 'd15e1111-0000-0000-0000-000000000001') $$,
  'a verified club''s admin files too');
reset role;

select is(
  (select (reason, organiser_club_id)::text from reports
    where target_kind = 'club' and target_id = 'd15e1111-0000-0000-0000-000000000003'),
  ('organiser_dispute', 'd15e1111-0000-0000-0000-000000000001')::text,
  'the report records the reason and the reporting club');
select is(
  (select action from organiser_dispute_actions
    where target_kind = 'club' and target_id = 'd15e1111-0000-0000-0000-000000000003'),
  'filed', 'the filing is logged');
select is(
  (select string_agg(target_kind || ':' || target_owner_id, ',' order by target_kind)
     from organiser_dispute_actions
    where action = 'filed' and organiser_club_id = 'd15e1111-0000-0000-0000-000000000001'),
  'challenge:d15e0000-0000-0000-0000-000000000005,club:d15e0000-0000-0000-0000-000000000005,'
  'gym_routine:d15e0000-0000-0000-0000-000000000005,race_listing:d15e0000-0000-0000-0000-000000000007,'
  'training_plan:d15e0000-0000-0000-0000-000000000005',
  'each filing records who answers for the target (a claimed race: the claiming club''s owner)');
select ok(
  not exists (select 1 from notifications where kind = 'organiser_dispute'
               and user_id = 'd15e0000-0000-0000-0000-000000000005'),
  'filing notifies nobody');

-- ── no automation ───────────────────────────────────────────────────────────

-- Two more vetted organisers dispute the fan club: three vetted reporters.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"d15e0000-0000-0000-0000-000000000007","role":"authenticated"}';
select lives_ok(
  $$ select submit_organiser_dispute('club', 'd15e1111-0000-0000-0000-000000000003', 'd15e1111-0000-0000-0000-000000000004') $$,
  'a second organiser files against the fan club');
reset role;
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"d15e0000-0000-0000-0000-000000000008","role":"authenticated"}';
select lives_ok(
  $$ select submit_organiser_dispute('club', 'd15e1111-0000-0000-0000-000000000003', 'd15e1111-0000-0000-0000-000000000005') $$,
  'a third organiser files against the fan club');
reset role;

select is(
  (select count(distinct reporter_id)::int from reports
    where target_kind = 'club' and target_id = 'd15e1111-0000-0000-0000-000000000003' and status = 'pending'),
  3, 'three vetted reporters have a pending dispute on the fan club');
select is(
  (select shadow_hidden from clubs where id = 'd15e1111-0000-0000-0000-000000000003'),
  false, 'three vetted disputes do not auto-hide the club');

-- A general report from a vetted reporter is not tipped over the threshold
-- by the disputes beside it.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"d15e0000-0000-0000-0000-000000000003","role":"authenticated"}';
select lives_ok(
  $$ select submit_report('club', 'd15e1111-0000-0000-0000-000000000003', 'impersonation') $$,
  'a member files a general impersonation report');
reset role;
select is(
  (select shadow_hidden from clubs where id = 'd15e1111-0000-0000-0000-000000000003'),
  false, 'disputes never count toward a general auto-hide');

-- ── the queue ───────────────────────────────────────────────────────────────

-- Every filing above shares one transaction's now(); space them out in the
-- order they were filed.
update reports set created_at = now() - interval '3 minutes'
 where reporter_id = 'd15e0000-0000-0000-0000-000000000001';
update reports set created_at = now() - interval '2 minutes'
 where reporter_id = 'd15e0000-0000-0000-0000-000000000007';
update reports set created_at = now() - interval '1 minute'
 where reporter_id = 'd15e0000-0000-0000-0000-000000000008';

-- A general report filed after every dispute, on another target.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"d15e0000-0000-0000-0000-000000000003","role":"authenticated"}';
select lives_ok(
  $$ select submit_report('user', 'd15e0000-0000-0000-0000-000000000005', 'spam') $$,
  'a newer general report on a profile');
reset role;
update reports set created_at = now() + interval '1 hour'
 where target_kind = 'user' and target_id = 'd15e0000-0000-0000-0000-000000000005';

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"d15e0000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok(
  $$ select * from fetch_pending_reports() $$, '42501', null, 'a non-admin cannot read the queue');
select throws_ok(
  $$ select resolve_organiser_dispute('club', 'd15e1111-0000-0000-0000-000000000003', 'takedown') $$,
  '42501', null, 'a verified organiser cannot act on its own dispute');
select throws_ok(
  $$ select * from organiser_dispute_history('club', 'd15e1111-0000-0000-0000-000000000003') $$,
  '42501', null, 'a non-admin cannot read the dispute log');
select throws_ok(
  $$ select 1 from organiser_dispute_actions $$, '42501', null, 'the log is not readable by a client');
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"d15e0000-0000-0000-0000-000000000006","role":"authenticated"}';
select ok(
  (select bool_and(organiser_dispute) from (
     select organiser_dispute from fetch_pending_reports()
      where target_id in ('d15e1111-0000-0000-0000-000000000003', 'd15e3333-0000-0000-0000-000000000001',
                          'd15e4444-0000-0000-0000-000000000001', 'd15e5555-0000-0000-0000-000000000001',
                          'd15e6666-0000-0000-0000-000000000001')) q),
  'every disputed target is flagged in the queue');
select ok(
  (select min(rn) filter (where target_id = 'd15e0000-0000-0000-0000-000000000005')
          > max(rn) filter (where organiser_dispute)
     from (select target_id, organiser_dispute, row_number() over () as rn from fetch_pending_reports()) q),
  'disputed targets sort before a newer general report');
select is(
  (select jsonb_path_query_array(organiser_clubs, '$[*].name')::text from fetch_pending_reports()
    where target_kind = 'club' and target_id = 'd15e1111-0000-0000-0000-000000000003'),
  '["OD Marathon", "OD Second Org", "OD Third Org"]',
  'the queue names every reporting club, first filing first');
select is(
  (select (organiser_club_name, organiser_club_verified)::text from fetch_reports_for_target('club', 'd15e1111-0000-0000-0000-000000000003')
    where reporter_id = 'd15e0000-0000-0000-0000-000000000001'),
  ('OD Marathon', true)::text, 'the detail shows the reporter''s verified organisation');

-- ── actions ─────────────────────────────────────────────────────────────────

select throws_ok(
  $$ select resolve_organiser_dispute('club', 'd15e1111-0000-0000-0000-000000000003', 'delete') $$,
  '22023', null, 'an unknown action is refused');
select throws_ok(
  $$ select resolve_organiser_dispute('club', 'd15e1111-0000-0000-0000-000000000003', 'rename_notice', null, 90) $$,
  '22023', null, 'a deadline past 60 days is refused');
select throws_ok(
  $$ select resolve_organiser_dispute('route', 'd15e2222-0000-0000-0000-000000000001', 'takedown') $$,
  'P0002', null, 'a target with no pending dispute cannot be acted on');

-- The general triage closes the member's report and leaves the disputes.
select is(
  resolve_target_reports('club', 'd15e1111-0000-0000-0000-000000000003', 'dismissed', null),
  1, 'the general triage resolves only the general report');
select is(
  (select count(*)::int from fetch_reports_for_target('club', 'd15e1111-0000-0000-0000-000000000003')
    where reason = 'organiser_dispute' and status = 'pending'),
  3, 'the general triage leaves the disputes pending');

-- Rename notice on the fan club: reports stay pending, deadline in force.
select lives_ok(
  $$ select resolve_organiser_dispute('club', 'd15e1111-0000-0000-0000-000000000003', 'rename_notice',
       'Please rename the club so it is not mistaken for the race.', 21) $$,
  'a site admin sends a rename notice');
select is(
  (select count(*)::int from fetch_reports_for_target('club', 'd15e1111-0000-0000-0000-000000000003')
    where reason = 'organiser_dispute' and status = 'pending'),
  3, 'a rename notice leaves the disputes pending');
select ok(
  (select rename_deadline_at between now() + interval '20 days' and now() + interval '22 days'
     from fetch_pending_reports() where target_kind = 'club' and target_id = 'd15e1111-0000-0000-0000-000000000003'),
  'the queue shows the rename deadline');

-- Hide the copied plan: unpublished, and the owner cannot republish it.
select is(
  resolve_organiser_dispute('training_plan', 'd15e3333-0000-0000-0000-000000000001', 'takedown', 'Copied verbatim.'),
  1, 'hiding the plan resolves its dispute report');
-- Release the race claim.
select is(
  resolve_organiser_dispute('race_listing', 'd15e6666-0000-0000-0000-000000000001', 'takedown'),
  1, 'hiding the race listing resolves its dispute report');
-- Hide the copied challenge.
select is(
  resolve_organiser_dispute('challenge', 'd15e5555-0000-0000-0000-000000000001', 'takedown'),
  1, 'hiding the challenge resolves its dispute report');
-- Dismiss the routine dispute.
select is(
  resolve_organiser_dispute('gym_routine', 'd15e4444-0000-0000-0000-000000000001', 'dismiss', 'Generic name.'),
  1, 'dismissing resolves the routine''s dispute report');
select ok(
  (select count(*) = 3 from organiser_dispute_history('club', 'd15e1111-0000-0000-0000-000000000003')
    where action = 'rename_notice' and actor_id = 'd15e0000-0000-0000-0000-000000000006'),
  'the rename notice is logged once per reporting club with the reviewer');
reset role;

select is(
  (select is_public_template from training_plans where id = 'd15e3333-0000-0000-0000-000000000001'),
  false, 'the hidden plan is unpublished');
select is(
  (select (organiser_club_id is null and not is_verified)::text from race_listings where id = 'd15e6666-0000-0000-0000-000000000001'),
  'true', 'hiding a race listing releases its claim');
select is(
  (select status from reports where target_kind = 'gym_routine' and target_id = 'd15e4444-0000-0000-0000-000000000001'),
  'dismissed', 'the routine dispute is dismissed');

-- A client can only publish a plan through publish_plan_to_library, which
-- makes a new library copy; the lock is on the copy itself, for any writer.
select throws_ok(
  $$ update training_plans set is_public_template = true where id = 'd15e3333-0000-0000-0000-000000000001' $$,
  '42501', 'organiser_dispute_takedown', 'the taken-down plan copy cannot be republished');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"d15e0000-0000-0000-0000-000000000005","role":"authenticated"}';
select throws_ok(
  $$ update challenges set is_public = true where id = 'd15e5555-0000-0000-0000-000000000001' $$,
  '42501', 'organiser_dispute_takedown', 'the owner cannot republish a challenge taken down');

-- ── both sides, no reviewer ─────────────────────────────────────────────────

select ok(
  (select count(*) >= 1 from notifications where kind = 'organiser_dispute' and actor_id is null),
  'the owner is notified, with no actor');
select is(
  (select (action, deadline_at is not null, organiser_club_name)::text from my_organiser_disputes()
    where side = 'owner' and target_kind = 'club' and organiser_club_id = 'd15e1111-0000-0000-0000-000000000001'),
  ('rename_notice', true, 'OD Marathon')::text,
  'the owner reads the rename notice and its deadline');
select ok(
  not exists (select 1 from my_organiser_disputes() where side = 'owner' and action = 'filed'),
  'the owner never sees a filing on its own');
reset role;

-- Notified: the second organiser, whose claim was released.
select ok(
  exists (select 1 from notifications where kind = 'organiser_dispute'
           and user_id = 'd15e0000-0000-0000-0000-000000000007'),
  'the owner of a released race claim is notified');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"d15e0000-0000-0000-0000-000000000002","role":"authenticated"}';
select is(
  (select action from my_organiser_disputes()
    where side = 'organiser' and target_kind = 'training_plan'),
  'takedown', 'the reporting club''s admin reads the outcome');
select is(
  (select count(*)::int from notifications where kind = 'organiser_dispute'
    and club_id = 'd15e1111-0000-0000-0000-000000000001' and actor_id is null),
  5, 'the reporting club''s admin is notified of each action, with no actor');
reset role;

-- ── lifting a takedown ──────────────────────────────────────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"d15e0000-0000-0000-0000-000000000006","role":"authenticated"}';
select ok(
  admin_unhide_target('training_plan', 'd15e3333-0000-0000-0000-000000000001'),
  'a site admin lifts the plan takedown');
reset role;

select lives_ok(
  $$ update training_plans set is_public_template = true where id = 'd15e3333-0000-0000-0000-000000000001' $$,
  'once lifted, the copy may be published again');

select * from finish();
rollback;

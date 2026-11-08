-- Pins 20271120000004: club verification requests (issue #1190 § 2,
-- decisions § 2398).
--
-- Only the club owner submits, withdraws and mails the email proof; an admin
-- of the club reads the request but cannot act; a plain member and a stranger
-- read nothing. Only a site admin approves, rejects and revokes, and approving
-- without proof needs a note. The Edge Function's writer and the re-check list
-- are service_role only. The email challenge's token is single use. A client
-- write still cannot set is_verified, and a verified club renamed, re-slugged
-- or moved to another domain loses the badge. Three failed re-checks lapse an
-- approval. Every action lands in the append-only audit log and every status
-- change notifies the club's owner and admins.

begin;
select plan(76);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('c7e00000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'cv-owner@cv.local', '', now(), now()),
  ('c7e00000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'cv-admin@cv.local', '', now(), now()),
  ('c7e00000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'cv-member@cv.local', '', now(), now()),
  ('c7e00000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'cv-stranger@cv.local', '', now(), now()),
  ('c7e00000-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'cv-site-admin@cv.local', '', now(), now())
on conflict (id) do nothing;

select tests.confirm_consent();

insert into app_admins (user_id) values ('c7e00000-0000-0000-0000-000000000005');

-- A: the organiser's club, with a website. B: a club with no website.
insert into clubs (id, owner_id, name, slug, is_public, website_url)
values
  ('c7e11111-0000-0000-0000-000000000001', 'c7e00000-0000-0000-0000-000000000001',
   'CV Marathon', 'cv-marathon', true, 'https://www.CV-Marathon.example.org/about'),
  ('c7e11111-0000-0000-0000-000000000002', 'c7e00000-0000-0000-0000-000000000001',
   'CV No Site', 'cv-no-site', true, null),
  ('c7e11111-0000-0000-0000-000000000003', 'c7e00000-0000-0000-0000-000000000001',
   'CV Withdrawn', 'cv-withdrawn', true, 'https://withdrawn.example.com');

insert into club_members (club_id, user_id, role, status)
values
  ('c7e11111-0000-0000-0000-000000000001', 'c7e00000-0000-0000-0000-000000000002', 'admin', 'active'),
  ('c7e11111-0000-0000-0000-000000000001', 'c7e00000-0000-0000-0000-000000000003', 'member', 'active')
on conflict (club_id, user_id) do update set role = excluded.role, status = excluded.status;

-- ── domain normalisation ────────────────────────────────────────────────────

select is(private.club_website_domain('https://www.CV-Marathon.example.org/about'), 'cv-marathon.example.org',
  'the claimed domain is the website host, lower-cased, without www. or a path');
select is(private.club_website_domain('https://user:pw@sub.example.com:8443/x?y#z'), 'sub.example.com',
  'credentials and port are not part of the domain');
select is(private.club_website_domain('https://192.168.0.1/'), null::text, 'an IP literal is not a domain');
select is(private.club_website_domain('ftp://example.com/'), null::text, 'only http(s) websites carry a domain');

-- ── submit ──────────────────────────────────────────────────────────────────

set local role anon;
select throws_ok(
  $$ select submit_club_verification('c7e11111-0000-0000-0000-000000000001', 'CV Org') $$,
  '42501', null, 'anon cannot submit');
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c7e00000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok(
  $$ select submit_club_verification('c7e11111-0000-0000-0000-000000000001', 'CV Org') $$,
  '42501', 'only the club owner can request verification', 'a club admin cannot submit (owner only)');
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c7e00000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok(
  $$ select submit_club_verification('c7e11111-0000-0000-0000-000000000002', 'CV Org') $$,
  '22023', 'club_website_required', 'a club with no website cannot submit');
select throws_ok(
  $$ select submit_club_verification('c7e11111-0000-0000-0000-000000000001', '   ') $$,
  '22023', 'organisation_required', 'the organisation is required');
select lives_ok(
  $$ select submit_club_verification('c7e11111-0000-0000-0000-000000000001', 'CV Marathon Org', 'We run it') $$,
  'the owner submits');
select throws_ok(
  $$ select submit_club_verification('c7e11111-0000-0000-0000-000000000001', 'CV Marathon Org') $$,
  '22023', 'request_already_pending', 'a second pending request is refused');
select is(
  (select domain from club_verification_requests where club_id = 'c7e11111-0000-0000-0000-000000000001'),
  'cv-marathon.example.org', 'the request records the website domain');
select ok(
  (select token ~ '^[0-9a-f]{32}$' from club_verification_requests where club_id = 'c7e11111-0000-0000-0000-000000000001'),
  'the request carries a random 128-bit proof token');
select throws_ok(
  $$ insert into club_verification_requests (club_id, organisation, domain)
     values ('c7e11111-0000-0000-0000-000000000002', 'x', 'example.com') $$,
  '42501', null, 'no direct insert');
select throws_ok(
  $$ select 1 from club_verification_email_challenges $$,
  '42501', null, 'the email challenge table is not readable by a client');
reset role;

-- ── reads ───────────────────────────────────────────────────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c7e00000-0000-0000-0000-000000000002","role":"authenticated"}';
select is((select count(*)::int from club_verification_requests), 1, 'a club admin reads the club''s request');
select is((select count(*)::int from club_verification_audit), 1, 'a club admin reads the club''s audit');
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c7e00000-0000-0000-0000-000000000003","role":"authenticated"}';
select is((select count(*)::int from club_verification_requests), 0, 'a plain member reads no request');
select is((select count(*)::int from club_verification_audit), 0, 'a plain member reads no audit');
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c7e00000-0000-0000-0000-000000000004","role":"authenticated"}';
select is((select count(*)::int from club_verification_requests), 0, 'a stranger reads no request');
select throws_ok(
  $$ select * from club_verification_queue('pending') $$,
  '42501', null, 'a non-admin cannot read the review queue');
select throws_ok(
  $$ select * from club_verification_audit_log('c7e11111-0000-0000-0000-000000000001') $$,
  '42501', null, 'a non-admin cannot read the audit log RPC');
reset role;

set local role anon;
select throws_ok($$ select 1 from club_verification_requests $$, '42501', null, 'anon cannot read requests');
reset role;

-- ── the email proof ─────────────────────────────────────────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c7e00000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok(
  $$ select send_club_verification_email(
       (select id from club_verification_requests where club_id = 'c7e11111-0000-0000-0000-000000000001'), 'admin') $$,
  '42501', 'only the club owner can send a verification email', 'a club admin cannot send the email proof');
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c7e00000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok(
  $$ select send_club_verification_email(
       (select id from club_verification_requests where club_id = 'c7e11111-0000-0000-0000-000000000001'), 'a@b') $$,
  '22023', 'invalid_email_local_part', 'a local part cannot name another domain');
select lives_ok(
  $$ select send_club_verification_email(
       (select id from club_verification_requests where club_id = 'c7e11111-0000-0000-0000-000000000001'), 'Hostmaster') $$,
  'the owner sends the email proof');
reset role;

select is(
  (select payload->>'email' from jobs where kind = 'club_verification_email' order by id desc limit 1),
  'hostmaster@cv-marathon.example.org', 'the job addresses the local part at the request domain');
select ok(
  (select (payload->>'token') ~ '^[0-9a-f]{48}$' from jobs where kind = 'club_verification_email' order by id desc limit 1),
  'the job carries a 192-bit token');
select is(
  (select token_hash from club_verification_email_challenges),
  (select sha256(convert_to(payload->>'token', 'UTF8')) from jobs where kind = 'club_verification_email' order by id desc limit 1),
  'only the token hash is stored');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c7e00000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok(
  $$ select send_club_verification_email(
       (select id from club_verification_requests where club_id = 'c7e11111-0000-0000-0000-000000000001'), 'admin') $$,
  'a second send replaces the challenge');
select lives_ok(
  $$ select send_club_verification_email(
       (select id from club_verification_requests where club_id = 'c7e11111-0000-0000-0000-000000000001'), 'admin') $$,
  'a third send in a day is allowed');
select throws_ok(
  $$ select send_club_verification_email(
       (select id from club_verification_requests where club_id = 'c7e11111-0000-0000-0000-000000000001'), 'admin') $$,
  '22023', 'email_rate_limited', 'a fourth send in a day is refused');
reset role;

set local role anon;
select is((select outcome from confirm_club_verification_email(repeat('0', 48))), 'invalid',
  'a wrong token is invalid');
select is((select outcome from confirm_club_verification_email('not-a-token')), 'invalid',
  'a malformed token is invalid');
reset role;

-- Only the latest send's token is live.
select is(
  (select count(*)::int from club_verification_email_challenges
    where token_hash = (select sha256(convert_to(payload->>'token', 'UTF8')) from jobs
                         where kind = 'club_verification_email' order by id asc limit 1)),
  0, 'a replaced challenge''s token no longer matches');

create temporary table cv_token as
  select payload->>'token' as token from jobs where kind = 'club_verification_email'
  order by id desc limit 1;
grant select on cv_token to anon;

set local role anon;
select is((select outcome from confirm_club_verification_email((select token from cv_token))), 'confirmed',
  'anyone holding the mailed token confirms it');
select is((select outcome from confirm_club_verification_email((select token from cv_token))), 'invalid',
  'the token is single use');
reset role;

select is(
  (select proof_method || ' ' || proof_detail from club_verification_requests
    where club_id = 'c7e11111-0000-0000-0000-000000000001'),
  'email admin@cv-marathon.example.org', 'the request records the email proof and its address');

-- ── the Edge Function writer ────────────────────────────────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c7e00000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok(
  $$ select record_club_verification_check(
       (select id from club_verification_requests where club_id = 'c7e11111-0000-0000-0000-000000000001'),
       'dns_txt', true) $$,
  '42501', null, 'a client cannot record a proof check');
select throws_ok(
  $$ select * from club_verifications_due_for_recheck(10) $$,
  '42501', null, 'a client cannot read the re-check list');
reset role;

-- ── review ──────────────────────────────────────────────────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c7e00000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok(
  $$ select approve_club_verification(
       (select id from club_verification_requests where club_id = 'c7e11111-0000-0000-0000-000000000001')) $$,
  '42501', null, 'the club owner cannot approve their own request');
update clubs set is_verified = true where id = 'c7e11111-0000-0000-0000-000000000001';
reset role;
select is((select is_verified from clubs where id = 'c7e11111-0000-0000-0000-000000000001'), false,
  'a direct client update still cannot verify a club');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c7e00000-0000-0000-0000-000000000005","role":"authenticated"}';
select is((select count(*)::int from club_verification_queue('pending')), 1, 'a site admin reads the pending queue');
select throws_ok(
  $$ select reject_club_verification(
       (select request_id from club_verification_queue('pending') where club_id = 'c7e11111-0000-0000-0000-000000000001'), '  ') $$,
  '22023', 'reason_required', 'rejecting needs a reason');
select lives_ok(
  $$ select approve_club_verification(
       (select request_id from club_verification_queue('pending') where club_id = 'c7e11111-0000-0000-0000-000000000001')) $$,
  'a site admin approves a request with proof');
reset role;

select is((select is_verified from clubs where id = 'c7e11111-0000-0000-0000-000000000001'), true,
  'approval verifies the club (through the JWT-authenticated definer RPC)');
select is(
  (select array_agg(user_id order by user_id)::text from notifications
    where kind = 'club_verification' and club_id = 'c7e11111-0000-0000-0000-000000000001'),
  '{c7e00000-0000-0000-0000-000000000001,c7e00000-0000-0000-0000-000000000002}',
  'approval notifies the owner and the active admin, not the member');
select is(
  (select count(*)::int from notifications
    where kind = 'club_verification' and actor_id is not null),
  0, 'the notification names no reviewer');

-- ── the lock ────────────────────────────────────────────────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c7e00000-0000-0000-0000-000000000001","role":"authenticated"}';
update clubs set description = 'still us' where id = 'c7e11111-0000-0000-0000-000000000001';
reset role;
select is((select is_verified from clubs where id = 'c7e11111-0000-0000-0000-000000000001'), true,
  'an edit that is not the name, slug or domain keeps the badge');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c7e00000-0000-0000-0000-000000000001","role":"authenticated"}';
update clubs set website_url = 'https://cv-marathon.example.org/new-page' where id = 'c7e11111-0000-0000-0000-000000000001';
reset role;
select is((select is_verified from clubs where id = 'c7e11111-0000-0000-0000-000000000001'), true,
  'a new page on the same domain keeps the badge');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c7e00000-0000-0000-0000-000000000001","role":"authenticated"}';
update clubs set website_url = 'https://cv-marathon-official.example.net' where id = 'c7e11111-0000-0000-0000-000000000001';
reset role;
select is((select is_verified from clubs where id = 'c7e11111-0000-0000-0000-000000000001'), false,
  'moving a verified club to another domain drops the badge');
select is(
  (select status || ' ' || close_reason from club_verification_requests
    where club_id = 'c7e11111-0000-0000-0000-000000000001'),
  'lapsed domain_changed', 'the approval lapses with the reason');

-- Re-verify through a second request, then rename.
update clubs set website_url = 'https://cv-marathon.example.org' where id = 'c7e11111-0000-0000-0000-000000000001';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c7e00000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok(
  $$ select submit_club_verification('c7e11111-0000-0000-0000-000000000001', 'CV Marathon Org') $$,
  'the owner resubmits after a lapse');
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c7e00000-0000-0000-0000-000000000005","role":"authenticated"}';
select throws_ok(
  $$ select approve_club_verification(
       (select request_id from club_verification_queue('pending') where club_id = 'c7e11111-0000-0000-0000-000000000001')) $$,
  '22023', 'manual_review_note_required', 'approving without proof needs a note');
select lives_ok(
  $$ select approve_club_verification(
       (select request_id from club_verification_queue('pending') where club_id = 'c7e11111-0000-0000-0000-000000000001'),
       'Linked from their official site footer') $$,
  'a site admin approves on manual review with a note');
reset role;
select is(
  (select proof_method from club_verification_requests
    where club_id = 'c7e11111-0000-0000-0000-000000000001' and status = 'approved'),
  'manual', 'a manual approval records the manual method');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c7e00000-0000-0000-0000-000000000002","role":"authenticated"}';
update clubs set name = 'CV Marathon Fans' where id = 'c7e11111-0000-0000-0000-000000000001';
reset role;
select is((select is_verified from clubs where id = 'c7e11111-0000-0000-0000-000000000001'), false,
  'renaming a verified club drops the badge');
select is(
  (select count(*)::int from club_verification_requests
    where club_id = 'c7e11111-0000-0000-0000-000000000001' and status = 'lapsed' and close_reason = 'name_changed'),
  1, 'the rename is the recorded reason');

-- ── re-check and lapse (service_role) ───────────────────────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c7e00000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok(
  $$ select submit_club_verification('c7e11111-0000-0000-0000-000000000001', 'CV Marathon Org') $$,
  'a third request');
reset role;

set local role service_role;
select is(
  record_club_verification_check(
    (select id from club_verification_requests where club_id = 'c7e11111-0000-0000-0000-000000000001' and status = 'pending'),
    'dns_txt', true, 'TXT _threkir-verification.cv-marathon.example.org'),
  'verified', 'a passing DNS check records the proof');
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c7e00000-0000-0000-0000-000000000005","role":"authenticated"}';
select lives_ok(
  $$ select approve_club_verification(
       (select request_id from club_verification_queue('pending') where club_id = 'c7e11111-0000-0000-0000-000000000001')) $$,
  'approved on DNS proof');
reset role;

update club_verification_requests set last_checked_at = now() - interval '2 days'
 where club_id = 'c7e11111-0000-0000-0000-000000000001' and status = 'approved';

set local role service_role;
select is((select count(*)::int from club_verifications_due_for_recheck(10)), 1,
  'an approval proven by DNS and not checked for a day is due');
select is(
  record_club_verification_check(
    (select id from club_verification_requests where club_id = 'c7e11111-0000-0000-0000-000000000001' and status = 'approved'),
    'dns_txt', false, 'no record'),
  'not_found', 'one failed re-check counts');
select is(
  record_club_verification_check(
    (select id from club_verification_requests where club_id = 'c7e11111-0000-0000-0000-000000000001' and status = 'approved'),
    'dns_txt', false, 'no record'),
  'not_found', 'two failed re-checks count');
select is(
  record_club_verification_check(
    (select id from club_verification_requests where club_id = 'c7e11111-0000-0000-0000-000000000001' and status = 'approved'),
    'dns_txt', false, 'no record'),
  'lapsed', 'the third failed re-check lapses the approval');
reset role;
select is((select is_verified from clubs where id = 'c7e11111-0000-0000-0000-000000000001'), false,
  'a lapsed proof drops the badge');

-- ── revoke ──────────────────────────────────────────────────────────────────

-- A club verified before this flow, with no request.
set local role service_role;
update clubs set is_verified = true where id = 'c7e11111-0000-0000-0000-000000000002';
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c7e00000-0000-0000-0000-000000000005","role":"authenticated"}';
select is(
  (select count(*)::int from club_verification_queue('verified') where club_id = 'c7e11111-0000-0000-0000-000000000002' and request_id is null),
  1, 'a club verified before the flow is listed with no request');
select throws_ok(
  $$ select revoke_club_verification('c7e11111-0000-0000-0000-000000000002', '') $$,
  '22023', 'reason_required', 'revoking needs a reason');
select lives_ok(
  $$ select revoke_club_verification('c7e11111-0000-0000-0000-000000000002', 'Impersonation report upheld') $$,
  'a site admin revokes a badge');
reset role;
select is((select is_verified from clubs where id = 'c7e11111-0000-0000-0000-000000000002'), false,
  'revoking drops the badge');

-- ── withdraw ────────────────────────────────────────────────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c7e00000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok(
  $$ select submit_club_verification('c7e11111-0000-0000-0000-000000000003', 'Withdrawn Org') $$,
  'the owner submits for a second club');
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c7e00000-0000-0000-0000-000000000004","role":"authenticated"}';
select throws_ok(
  $$ select withdraw_club_verification(
       (select request_id from club_verification_queue('pending') where club_id = 'c7e11111-0000-0000-0000-000000000003')) $$,
  '42501', null, 'a stranger cannot withdraw');
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c7e00000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok(
  $$ select withdraw_club_verification(
       (select id from club_verification_requests where club_id = 'c7e11111-0000-0000-0000-000000000003')) $$,
  'the owner withdraws a pending request');
reset role;
select is(
  (select status from club_verification_requests where club_id = 'c7e11111-0000-0000-0000-000000000003'),
  'withdrawn', 'the request is withdrawn');

-- ── the audit log ───────────────────────────────────────────────────────────

select is(
  (select array_agg(distinct action order by action)::text from club_verification_audit
    where club_id = 'c7e11111-0000-0000-0000-000000000001'),
  '{approve,email_sent,lapse,proof_failed,proof_verified,submit}',
  'every action on the club is audited');
select throws_ok(
  $$ update club_verification_audit set detail = 'edited' $$,
  '42501', 'club_verification_audit is append-only', 'the audit log cannot be edited');
select throws_ok(
  $$ delete from club_verification_audit $$,
  '42501', 'club_verification_audit is append-only', 'the audit log cannot be deleted');

select * from finish();
rollback;

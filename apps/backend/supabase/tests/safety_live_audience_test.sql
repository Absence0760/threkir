-- Safety-contacts-only live audience (20270821000001, decisions § 1964).
--
-- Principals:
--   O  the runner (owner)
--   C  an app-user safety contact, confirmed in-app (contact_user_id = C)
--   E  an email-only safety contact, confirmed by link, with SMS opted in
--   P  a pending (unconfirmed) contact address
--   F  a follower of O, not a contact
--   S  a stranger
--   anon
-- Pins: the gate stores a safety stub as plain private while closed; a safety
-- stub is never public and nobody but O reads its pings through the table,
-- before or after an escalation; the escalation mints one link per confirmed
-- contact and hands each contact only their own; a link admits its own run
-- while it is live and stops on every exit (gate closed, concluded, saved,
-- contact removed, expired); a public stub mints nothing.

begin;

select plan(37);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('5afe0000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'o@safeaud.local', '', now(), now()),
  ('5afe0000-0000-0000-0000-00000000000c', 'authenticated', 'authenticated', 'c@safeaud.local', '', now(), now()),
  ('5afe0000-0000-0000-0000-00000000000f', 'authenticated', 'authenticated', 'f@safeaud.local', '', now(), now()),
  ('5afe0000-0000-0000-0000-0000000000a5', 'authenticated', 'authenticated', 's@safeaud.local', '', now(), now());

select tests.confirm_consent();

update user_profiles set display_name = 'Sam Safe'
 where id = '5afe0000-0000-0000-0000-00000000000a';

insert into user_follows (follower_id, followee_id)
values ('5afe0000-0000-0000-0000-00000000000f', '5afe0000-0000-0000-0000-00000000000a');

insert into user_settings (user_id, prefs)
values ('5afe0000-0000-0000-0000-00000000000a',
        '{"safety_overdue_minutes": 30, "safety_off_route_alerts": true}')
on conflict (user_id) do update set prefs = excluded.prefs;

insert into safety_contacts (id, owner_id, contact_email) values
  ('5afec000-0000-0000-0000-00000000000c', '5afe0000-0000-0000-0000-00000000000a', 'c@safeaud.local'),
  ('5afec000-0000-0000-0000-00000000000e', '5afe0000-0000-0000-0000-00000000000a', 'e@safeaud.local'),
  ('5afec000-0000-0000-0000-0000000000a0', '5afe0000-0000-0000-0000-00000000000a', 'p@safeaud.local');

update safety_contacts set confirmed_at = now(), contact_user_id = '5afe0000-0000-0000-0000-00000000000c'
 where id = '5afec000-0000-0000-0000-00000000000c';
update safety_contacts set confirmed_at = now(), contact_phone = '+447700900123', sms_opt_in_at = now()
 where id = '5afec000-0000-0000-0000-00000000000e';

delete from private.feature_flags where name = 'safety_audience';

-- ── Gate closed ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"5afe0000-0000-0000-0000-00000000000a","role":"authenticated"}';

-- (1)
select is(public.safety_audience_enabled(), false,
  'the gate reads closed while no flag row exists');

insert into runs (id, user_id, started_at, duration_s, distance_m, source, activity_type, is_public, safety_audience, metadata)
values ('5afe1000-0000-0000-0000-000000000001', '5afe0000-0000-0000-0000-00000000000a',
        now() - interval '45 minutes', 0, 0, 'app', 'run', false, true, '{"in_progress": true}');

-- (2)
select is(
  (select safety_audience from runs where id = '5afe1000-0000-0000-0000-000000000001'),
  false,
  'a safety stub written while the gate is closed is stored as plain private');

reset role;
insert into private.feature_flags (name, enabled) values ('safety_audience', true)
  on conflict (name) do update set enabled = true;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"5afe0000-0000-0000-0000-00000000000a","role":"authenticated"}';

-- (3)
select is(public.safety_audience_enabled(), true, 'the gate reads open once the flag row is on');

-- The safety stub, 45 minutes silent: the overdue window is 30.
insert into runs (id, user_id, started_at, duration_s, distance_m, source, activity_type, is_public, safety_audience, metadata)
values ('5afe1000-0000-0000-0000-000000000002', '5afe0000-0000-0000-0000-00000000000a',
        now() - interval '45 minutes', 0, 0, 'app', 'run', false, true, '{"in_progress": true}');

-- (4)
select is(
  (select safety_audience from runs where id = '5afe1000-0000-0000-0000-000000000002'),
  true,
  'with the gate open the stub keeps the safety audience');

insert into live_run_pings (run_id, user_id, at, lat, lng, distance_m, elapsed_s)
values ('5afe1000-0000-0000-0000-000000000002', '5afe0000-0000-0000-0000-00000000000a',
        now() - interval '40 minutes', 51.5, -0.12, 800, 300);

-- (5)
select is(
  (select count(*)::int from live_run_pings where run_id = '5afe1000-0000-0000-0000-000000000002'),
  1, 'the runner reads their own pings');

-- ── Before any escalation, nobody else reads them ──
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

-- (6)
select is(
  (select count(*)::int from live_run_pings where run_id = '5afe1000-0000-0000-0000-000000000002'),
  0, 'anon reads no pings of a safety stub');

-- (7)
select is(
  (select count(*)::int from public_runs where id = '5afe1000-0000-0000-0000-000000000002'),
  0, 'a safety stub is not in public_runs');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"5afe0000-0000-0000-0000-0000000000a5","role":"authenticated"}';

-- (8)
select is(
  (select count(*)::int from live_run_pings where run_id = '5afe1000-0000-0000-0000-000000000002'),
  0, 'a stranger reads no pings of a safety stub');

set local "request.jwt.claims" = '{"sub":"5afe0000-0000-0000-0000-00000000000f","role":"authenticated"}';

-- (9)
select is(
  (select count(*)::int from live_run_pings where run_id = '5afe1000-0000-0000-0000-000000000002'),
  0, 'a follower reads no pings of a safety stub');

set local "request.jwt.claims" = '{"sub":"5afe0000-0000-0000-0000-00000000000c","role":"authenticated"}';

-- (10)
select is(
  (select count(*)::int from live_run_pings where run_id = '5afe1000-0000-0000-0000-000000000002'),
  0, 'even a confirmed app-user contact reads nothing through the table');

-- (11)
select throws_ok(
  $$select count(*) from private.run_safety_links$$,
  '42501', null,
  'no client role reads the link table');

-- ── The overdue scan escalates and mints one link per confirmed contact ──
reset role;
delete from public.jobs;
select public.enqueue_safety_overdue_emails();

-- (12)
select is(
  (select is_public from runs where id = '5afe1000-0000-0000-0000-000000000002'),
  false, 'the escalation never flips the run public');

-- (13)
select is(
  (select count(*)::int from private.run_safety_links where run_id = '5afe1000-0000-0000-0000-000000000002'),
  2, 'one link per confirmed contact, none for the pending one');

-- (14)
select is(
  (select count(*)::int
     from public.jobs j
     join safety_contacts sc
       on sc.owner_id = '5afe0000-0000-0000-0000-00000000000a'
      and lower(sc.contact_email) = lower(j.payload->>'contact_email')
     join private.run_safety_links l
       on l.contact_id = sc.id and l.run_id = '5afe1000-0000-0000-0000-000000000002'
    where j.kind = 'safety_email'
      and j.payload->>'template' = 'overdue'
      and j.payload->>'run_id' = '5afe1000-0000-0000-0000-000000000002'
      and j.payload->>'view_token' = l.token::text),
  2, 'each contact''s overdue email carries that contact''s own link');

-- (15)
select is(
  (select count(distinct j.payload->>'view_token')::int from public.jobs j
    where j.kind = 'safety_email'
      and j.payload->>'run_id' = '5afe1000-0000-0000-0000-000000000002'),
  2, 'no two contacts share a link');

-- (16)
select is(
  (select j.payload->>'view_token' from public.jobs j
    where j.kind = 'safety_sms'
      and j.payload->>'run_id' = '5afe1000-0000-0000-0000-000000000002'),
  (select l.token::text from private.run_safety_links l
    where l.run_id = '5afe1000-0000-0000-0000-000000000002'
      and l.contact_id = '5afec000-0000-0000-0000-00000000000e'),
  'the SMS leg carries the opted-in contact''s own link');

create temporary table tok as
select l.token from private.run_safety_links l
 where l.run_id = '5afe1000-0000-0000-0000-000000000002'
   and l.contact_id = '5afec000-0000-0000-0000-00000000000e';
grant select on tok to anon, authenticated;

-- ── A link admits its own run, to anyone holding it ──
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

-- (17)
select is(
  (select count(*)::int from public.safety_live_pings(
     '5afe1000-0000-0000-0000-000000000002', (select token from tok))),
  1, 'the email-only contact reads the pings through their link');

-- (18)
select is(
  (select owner_name from public.safety_live_run(
     '5afe1000-0000-0000-0000-000000000002', (select token from tok))),
  'Sam Safe', 'the link reads the run and names the runner');

-- (19)
select is(
  (select count(*)::int from public.safety_live_pings(
     '5afe1000-0000-0000-0000-000000000002', (select token from tok), now() - interval '41 minutes')),
  1, 'the poll returns what arrived after the cursor');

-- (20)
select is(
  (select count(*)::int from public.safety_live_pings(
     '5afe1000-0000-0000-0000-000000000002', '5afe9999-0000-0000-0000-000000000000')),
  0, 'a wrong token reads nothing');

-- (21)
select is(
  (select count(*)::int from public.safety_live_pings(
     '5afe1000-0000-0000-0000-000000000001', (select token from tok))),
  0, 'a link does not admit another run of the same runner');

-- (22)
select is(
  (select count(*)::int from live_run_pings where run_id = '5afe1000-0000-0000-0000-000000000002'),
  0, 'after the escalation anon still reads nothing through the table');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"5afe0000-0000-0000-0000-00000000000f","role":"authenticated"}';

-- (23)
select is(
  (select count(*)::int from live_run_pings where run_id = '5afe1000-0000-0000-0000-000000000002'),
  0, 'after the escalation a follower still reads nothing');

set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

-- (24)
select throws_ok(
  $$select public.safety_audience_enabled()$$,
  '42501', null,
  'anon cannot read the gate');

-- ── Every exit closes the link ──
reset role;
update private.feature_flags set enabled = false where name = 'safety_audience';
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

-- (25)
select is(
  (select count(*)::int from public.safety_live_pings(
     '5afe1000-0000-0000-0000-000000000002', (select token from tok))),
  0, 'closing the gate closes every link');

reset role;
update private.feature_flags set enabled = true where name = 'safety_audience';
update runs set concluded_at = now() where id = '5afe1000-0000-0000-0000-000000000002';
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

-- (26)
select is(
  (select count(*)::int from public.safety_live_run(
     '5afe1000-0000-0000-0000-000000000002', (select token from tok))),
  0, 'a concluded broadcast closes the link');

reset role;
update runs set concluded_at = null where id = '5afe1000-0000-0000-0000-000000000002';
update runs set metadata = '{}'::jsonb where id = '5afe1000-0000-0000-0000-000000000002';
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

-- (27)
select is(
  (select count(*)::int from public.safety_live_run(
     '5afe1000-0000-0000-0000-000000000002', (select token from tok))),
  0, 'a saved run closes the link');

reset role;
update runs set metadata = '{"in_progress": true, "safety_escalated_at": "2026-01-01T00:00:00Z"}'::jsonb
 where id = '5afe1000-0000-0000-0000-000000000002';
update private.run_safety_links set created_at = now() - interval '49 hours'
 where token = (select token from tok);
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

-- (28)
select is(
  (select count(*)::int from public.safety_live_run(
     '5afe1000-0000-0000-0000-000000000002', (select token from tok))),
  0, 'a link older than 48 hours admits nothing');

reset role;
select cleanup_stale_live_run_pings();

-- (29)
select is(
  (select count(*)::int from private.run_safety_links where token = (select token from tok)),
  0, 'the 48 h sweep deletes an expired link');

-- (30)
select is(
  (select count(*)::int from private.run_safety_links
    where run_id = '5afe1000-0000-0000-0000-000000000002'
      and contact_id = '5afec000-0000-0000-0000-00000000000c'),
  1, 'the sweep keeps a live link');

delete from safety_contacts where id = '5afec000-0000-0000-0000-00000000000c';

-- (31)
select is(
  (select count(*)::int from private.run_safety_links
    where contact_id = '5afec000-0000-0000-0000-00000000000c'),
  0, 'removing a contact revokes their link');

-- ── A public stub mints nothing ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"5afe0000-0000-0000-0000-00000000000a","role":"authenticated"}';
insert into runs (id, user_id, started_at, duration_s, distance_m, source, activity_type, is_public, metadata)
values ('5afe1000-0000-0000-0000-000000000003', '5afe0000-0000-0000-0000-00000000000a',
        now() - interval '45 minutes', 0, 0, 'app', 'run', true, '{"in_progress": true}');
reset role;
delete from public.jobs;
select public.enqueue_safety_overdue_emails();

-- (32)
select is(
  (select count(*)::int from public.jobs
    where kind = 'safety_email' and payload->>'run_id' = '5afe1000-0000-0000-0000-000000000003'),
  1, 'a public live share still escalates to the remaining contact');

-- (33)
select is(
  (select count(*)::int from public.jobs
    where payload->>'run_id' = '5afe1000-0000-0000-0000-000000000003' and payload ? 'view_token'),
  0, 'a public live share needs no link and gets none');

-- (34)
select is(
  (select count(*)::int from private.run_safety_links where run_id = '5afe1000-0000-0000-0000-000000000003'),
  0, 'no link is minted for a public stub');

-- ── The off-route escalation mints them too ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"5afe0000-0000-0000-0000-00000000000a","role":"authenticated"}';
insert into runs (id, user_id, started_at, duration_s, distance_m, source, activity_type, is_public, safety_audience, metadata)
values ('5afe1000-0000-0000-0000-000000000004', '5afe0000-0000-0000-0000-00000000000a',
        now() - interval '10 minutes', 0, 0, 'app', 'run', false, true, '{"in_progress": true}');
reset role;
delete from public.jobs;
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"5afe0000-0000-0000-0000-00000000000a","role":"authenticated"}';

-- (35)
select is(public.escalate_run_off_route('5afe1000-0000-0000-0000-000000000004'), true,
  'the runner escalates their own off-route safety stub');

reset role;

-- (36)
select is(
  (select j.payload->>'view_token' from public.jobs j
    where j.kind = 'safety_email' and j.payload->>'template' = 'off_route'
      and j.payload->>'run_id' = '5afe1000-0000-0000-0000-000000000004'),
  (select l.token::text from private.run_safety_links l
    where l.run_id = '5afe1000-0000-0000-0000-000000000004'
      and l.contact_id = '5afec000-0000-0000-0000-00000000000e'),
  'the off-route email carries the contact''s own link');

-- (37)
select is(
  (select is_public from runs where id = '5afe1000-0000-0000-0000-000000000004'),
  false, 'the off-route escalation never flips the run public');

select * from finish();
rollback;

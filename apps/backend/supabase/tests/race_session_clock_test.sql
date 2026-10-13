-- Pins migration 20270728000003 (decisions § R6SQL-4): race_sessions'
-- started_at and finished_at are the database clock for a client caller and
-- cannot be rewritten afterwards; the service role keeps what it writes.
--
--   1.   GO ignores a future started_at the host device sent.
--   2-3. The service role backdates started_at on GO and while running.
--   4-5. While running, a client neither re-stamps started_at on an unrelated
--        update nor rewrites it directly.
--   6.   End ignores the finished_at the host device sent.
--   7-8. After the finish, a client cannot move finished_at or started_at.
--   9.   The service role can still backdate finished_at after the finish.
--   10.  A client inserting a race straight into running gets server time.

begin;
select plan(10);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('e7282000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'clock-owner@evt.local', '', now(), now());

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

insert into clubs (id, owner_id, name, slug, is_public)
values ('e7282000-0000-0000-0000-0000000000c1',
        'e7282000-0000-0000-0000-000000000001', 'Clock Club', 'race-clock-c', true);

insert into events (id, club_id, title, starts_at, author_id, is_public)
values
  ('e7282000-0000-0000-0000-0000000000e1', 'e7282000-0000-0000-0000-0000000000c1',
   'Client race', '2026-09-01 08:00+00', 'e7282000-0000-0000-0000-000000000001', true),
  ('e7282000-0000-0000-0000-0000000000e2', 'e7282000-0000-0000-0000-0000000000c1',
   'Operator race', '2026-09-02 08:00+00', 'e7282000-0000-0000-0000-000000000001', true),
  ('e7282000-0000-0000-0000-0000000000e3', 'e7282000-0000-0000-0000-0000000000c1',
   'Straight-to-running race', '2026-09-03 08:00+00', 'e7282000-0000-0000-0000-000000000001', true);

insert into race_sessions (event_id, instance_start, status)
values
  ('e7282000-0000-0000-0000-0000000000e1', '2026-09-01 08:00+00', 'armed'),
  ('e7282000-0000-0000-0000-0000000000e2', '2026-09-02 08:00+00', 'armed');

-- ── 1: GO is server time ────────────────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7282000-0000-0000-0000-000000000001","role":"authenticated"}';

update race_sessions set status = 'running', started_at = now() + interval '1 hour'
 where event_id = 'e7282000-0000-0000-0000-0000000000e1';

select is(
  (select started_at from race_sessions
    where event_id = 'e7282000-0000-0000-0000-0000000000e1'),
  now(),
  'GO ignores a future started_at sent by the host device'
);

-- ── 2-3: the service role backdates ─────────────────────────────────────────
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

update race_sessions set status = 'running', started_at = '2026-09-02 08:00+00'
 where event_id = 'e7282000-0000-0000-0000-0000000000e2';

select is(
  (select started_at from race_sessions
    where event_id = 'e7282000-0000-0000-0000-0000000000e2'),
  '2026-09-02 08:00+00'::timestamptz,
  'the service role keeps the started_at it writes on GO'
);

update race_sessions set started_at = '2026-01-01 08:00+00'
 where event_id = 'e7282000-0000-0000-0000-0000000000e1';

select is(
  (select started_at from race_sessions
    where event_id = 'e7282000-0000-0000-0000-0000000000e1'),
  '2026-01-01 08:00+00'::timestamptz,
  'the service role can backdate started_at while the race is running'
);

-- ── 4-5: started_at is fixed while running ──────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7282000-0000-0000-0000-000000000001","role":"authenticated"}';

update race_sessions set is_auto_approve = false
 where event_id = 'e7282000-0000-0000-0000-0000000000e1';

select is(
  (select started_at from race_sessions
    where event_id = 'e7282000-0000-0000-0000-0000000000e1'),
  '2026-01-01 08:00+00'::timestamptz,
  'an unrelated update while running does not re-stamp started_at'
);

update race_sessions set started_at = '2026-06-01 08:00+00'
 where event_id = 'e7282000-0000-0000-0000-0000000000e1';

select is(
  (select started_at from race_sessions
    where event_id = 'e7282000-0000-0000-0000-0000000000e1'),
  '2026-01-01 08:00+00'::timestamptz,
  'a client cannot rewrite started_at while the race is running'
);

-- ── 6: End is server time ───────────────────────────────────────────────────
update race_sessions set status = 'finished', finished_at = now() + interval '1 day'
 where event_id = 'e7282000-0000-0000-0000-0000000000e1';

select is(
  (select finished_at from race_sessions
    where event_id = 'e7282000-0000-0000-0000-0000000000e1'),
  now(),
  'End ignores a finished_at sent by the host device'
);

-- ── 7-8: both stamps are fixed after the finish ─────────────────────────────
update race_sessions set finished_at = now() + interval '30 days'
 where event_id = 'e7282000-0000-0000-0000-0000000000e1';

select is(
  (select finished_at from race_sessions
    where event_id = 'e7282000-0000-0000-0000-0000000000e1'),
  now(),
  'a client cannot move finished_at, and with it the 24 h result window'
);

update race_sessions set started_at = '2026-06-01 08:00+00'
 where event_id = 'e7282000-0000-0000-0000-0000000000e1';

select is(
  (select started_at from race_sessions
    where event_id = 'e7282000-0000-0000-0000-0000000000e1'),
  '2026-01-01 08:00+00'::timestamptz,
  'a client cannot move started_at after the finish'
);

-- ── 9: the service role still can ──────────────────────────────────────────
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

update race_sessions set finished_at = '2026-01-01 12:00+00'
 where event_id = 'e7282000-0000-0000-0000-0000000000e1';

select is(
  (select finished_at from race_sessions
    where event_id = 'e7282000-0000-0000-0000-0000000000e1'),
  '2026-01-01 12:00+00'::timestamptz,
  'the service role can backdate finished_at after the finish'
);

-- ── 10: straight into running ───────────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7282000-0000-0000-0000-000000000001","role":"authenticated"}';

insert into race_sessions (event_id, instance_start, status, started_at)
values ('e7282000-0000-0000-0000-0000000000e3', '2026-09-03 08:00+00', 'running',
        '2026-09-03 07:00+00');

select is(
  (select started_at from race_sessions
    where event_id = 'e7282000-0000-0000-0000-0000000000e3'),
  now(),
  'a client inserting a running race gets the server''s started_at'
);

select * from finish();
rollback;

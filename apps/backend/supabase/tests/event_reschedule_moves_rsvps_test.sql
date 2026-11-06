-- Pins migration 20271111000001 (decisions § 2351, issue #1300 BUG-015):
-- editing an event's start moves the RSVPs, waitlist entries and paid orders
-- of its upcoming occurrences onto the matching new occurrence, leaves past
-- occurrences alone, does nothing on an edit that leaves the start as it was,
-- and aborts the edit when a row cannot follow.
--
-- Series fixtures are anchored on M, the Monday 00:00 UTC of the week the test
-- runs in, so M and every week before it are past and M + 7 days onwards is
-- upcoming whatever the day.
--   e1  one-off 2099-03-07 09:00 UTC: a paid going seat + a waitlist entry,
--       moved by the organiser's own session to 2099-03-09 18:30.
--   e2  weekly Mondays 00:00 UTC from M - 21 days, moved 90 minutes later.
--   e3  the same series restarted on Wednesday M + 9 days.
--   e4  one-off edited without touching the start.
--   e5  one-off in 2020, moved: its rows are history.
--   e6  one-off whose per-occurrence price cannot be re-saved (the host has
--       no payout account), so the move refuses and the edit with it.

begin;
select plan(17);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaa2351-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'move-org@rsvp.local', '', now(), now()),
  ('aaaa2351-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'move-a@rsvp.local', '', now(), now()),
  ('aaaa2351-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'move-b@rsvp.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public)
values ('bbbb2351-0000-0000-0000-000000000001', 'aaaa2351-0000-0000-0000-000000000001',
        'Reschedule Club', 'reschedule-club-2351', true);

create function pg_temp.m() returns timestamptz language sql stable as $$
  select date_trunc('week', now() at time zone 'UTC') at time zone 'UTC';
$$;

create function pg_temp.z(p timestamptz) returns text language sql immutable as $$
  select to_char(p at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI"Z"');
$$;

create function pg_temp.keys(p_event uuid, p_user uuid) returns text language sql as $$
  select coalesce(string_agg(pg_temp.z(instance_start), ' ' order by instance_start), '')
    from event_attendees where event_id = p_event and user_id = p_user;
$$;

insert into events (id, club_id, title, starts_at, author_id, host_user_id, recurrence_freq, timezone)
values
  ('cccc2351-0000-0000-0000-000000000001', 'bbbb2351-0000-0000-0000-000000000001', 'e1',
   '2099-03-07 09:00+00', 'aaaa2351-0000-0000-0000-000000000001',
   'aaaa2351-0000-0000-0000-000000000001', null, 'UTC'),
  ('cccc2351-0000-0000-0000-000000000002', 'bbbb2351-0000-0000-0000-000000000001', 'e2',
   pg_temp.m() - interval '21 days', 'aaaa2351-0000-0000-0000-000000000001',
   'aaaa2351-0000-0000-0000-000000000001', 'weekly', 'UTC'),
  ('cccc2351-0000-0000-0000-000000000003', 'bbbb2351-0000-0000-0000-000000000001', 'e3',
   pg_temp.m() - interval '21 days', 'aaaa2351-0000-0000-0000-000000000001',
   'aaaa2351-0000-0000-0000-000000000001', 'weekly', 'UTC'),
  ('cccc2351-0000-0000-0000-000000000004', 'bbbb2351-0000-0000-0000-000000000001', 'e4',
   '2099-04-04 09:00:42+00', 'aaaa2351-0000-0000-0000-000000000001',
   'aaaa2351-0000-0000-0000-000000000001', null, 'UTC'),
  ('cccc2351-0000-0000-0000-000000000005', 'bbbb2351-0000-0000-0000-000000000001', 'e5',
   '2020-05-02 09:00+00', 'aaaa2351-0000-0000-0000-000000000001',
   'aaaa2351-0000-0000-0000-000000000001', null, 'UTC'),
  ('cccc2351-0000-0000-0000-000000000006', 'bbbb2351-0000-0000-0000-000000000001', 'e6',
   '2099-05-02 09:00+00', 'aaaa2351-0000-0000-0000-000000000001',
   'aaaa2351-0000-0000-0000-000000000001', null, 'UTC');

insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                          amount_cents, platform_fee_cents, status)
values ('dddd2351-0000-0000-0000-000000000001', 'cccc2351-0000-0000-0000-000000000001',
        '2099-03-07 09:00+00', 'aaaa2351-0000-0000-0000-000000000002',
        'aaaa2351-0000-0000-0000-000000000001', 2000, 100, 'paid');

insert into event_attendees (event_id, user_id, instance_start, status, order_id) values
  ('cccc2351-0000-0000-0000-000000000001', 'aaaa2351-0000-0000-0000-000000000002',
   '2099-03-07 09:00+00', 'going', 'dddd2351-0000-0000-0000-000000000001');

insert into event_attendees (event_id, user_id, instance_start, status) values
  ('cccc2351-0000-0000-0000-000000000001', 'aaaa2351-0000-0000-0000-000000000003', '2099-03-07 09:00+00', 'waitlisted'),
  ('cccc2351-0000-0000-0000-000000000002', 'aaaa2351-0000-0000-0000-000000000002', pg_temp.m() - interval '14 days', 'going'),
  ('cccc2351-0000-0000-0000-000000000002', 'aaaa2351-0000-0000-0000-000000000002', pg_temp.m() + interval '7 days', 'going'),
  ('cccc2351-0000-0000-0000-000000000002', 'aaaa2351-0000-0000-0000-000000000003', pg_temp.m() + interval '14 days', 'waitlisted'),
  ('cccc2351-0000-0000-0000-000000000003', 'aaaa2351-0000-0000-0000-000000000002', pg_temp.m() - interval '14 days', 'going'),
  ('cccc2351-0000-0000-0000-000000000003', 'aaaa2351-0000-0000-0000-000000000002', pg_temp.m() + interval '7 days', 'going'),
  ('cccc2351-0000-0000-0000-000000000003', 'aaaa2351-0000-0000-0000-000000000003', pg_temp.m() + interval '14 days', 'going'),
  ('cccc2351-0000-0000-0000-000000000004', 'aaaa2351-0000-0000-0000-000000000002', '2099-04-04 09:00:42+00', 'going'),
  ('cccc2351-0000-0000-0000-000000000005', 'aaaa2351-0000-0000-0000-000000000002', '2020-05-02 09:00+00', 'going'),
  ('cccc2351-0000-0000-0000-000000000006', 'aaaa2351-0000-0000-0000-000000000002', '2099-05-02 09:00+00', 'going');

-- A per-occurrence price a host could set while their payout account was
-- live; the account has since gone, so the pricing trigger refuses to re-save
-- the row anywhere.
alter table event_pricing disable trigger event_pricing_requires_charges;
insert into event_pricing (event_id, instance_start, price_cents)
values ('cccc2351-0000-0000-0000-000000000006', '2099-05-02 09:00+00', 1500);
alter table event_pricing enable trigger event_pricing_requires_charges;

select has_trigger('public', 'events', 'events_move_rescheduled_rows',
  'events carries the trigger that moves upcoming rows with the start');

-- ── e1: a one-off moved from the organiser's own session ───────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaa2351-0000-0000-0000-000000000001","role":"authenticated"}';

select lives_ok(
  $$ update events set starts_at = '2099-03-09 18:30+00'
      where id = 'cccc2351-0000-0000-0000-000000000001' $$,
  'the organiser moves a one-off with a paid seat on it');

reset role;
reset "request.jwt.claims";

select is(pg_temp.keys('cccc2351-0000-0000-0000-000000000001', 'aaaa2351-0000-0000-0000-000000000002'),
  '2099-03-09T18:30Z', 'the paid going seat follows the one-off to its new start');
select is(pg_temp.keys('cccc2351-0000-0000-0000-000000000001', 'aaaa2351-0000-0000-0000-000000000003'),
  '2099-03-09T18:30Z', 'so does the waitlist entry');
select is((select status from event_attendees
            where event_id = 'cccc2351-0000-0000-0000-000000000001'
              and user_id = 'aaaa2351-0000-0000-0000-000000000003'),
  'waitlisted', 'the waitlist entry keeps its place in the queue, not a seat');
select is((select pg_temp.z(instance_start) from event_orders
            where id = 'dddd2351-0000-0000-0000-000000000001'),
  '2099-03-09T18:30Z', 'the paid order moves with its seat, past the ledger lock');
select is((select status from event_orders where id = 'dddd2351-0000-0000-0000-000000000001'),
  'paid', 'and stays paid');
select is(coalesce(current_setting('threkir.event_reschedule', true), ''), '',
  'the reschedule flag the ledger lock honours is cleared after the move');

-- ── e2: a series moved 90 minutes later ────────────────────────────────────

update events set starts_at = starts_at + interval '90 minutes'
 where id = 'cccc2351-0000-0000-0000-000000000002';

select is(pg_temp.keys('cccc2351-0000-0000-0000-000000000002', 'aaaa2351-0000-0000-0000-000000000002'),
  pg_temp.z(pg_temp.m() - interval '14 days') || ' '
    || pg_temp.z(pg_temp.m() + interval '7 days 90 minutes'),
  'an upcoming series RSVP moves to the same session at the new time; the past one stays');
select is(pg_temp.keys('cccc2351-0000-0000-0000-000000000002', 'aaaa2351-0000-0000-0000-000000000003'),
  pg_temp.z(pg_temp.m() + interval '14 days 90 minutes'),
  'an upcoming series waitlist entry moves the same way');

-- ── e3: a running series restarted from a later Wednesday ──────────────────

update events set starts_at = pg_temp.m() + interval '9 days'
 where id = 'cccc2351-0000-0000-0000-000000000003';

select is(pg_temp.keys('cccc2351-0000-0000-0000-000000000003', 'aaaa2351-0000-0000-0000-000000000002'),
  pg_temp.z(pg_temp.m() - interval '14 days') || ' ' || pg_temp.z(pg_temp.m() + interval '9 days'),
  'the next session pairs with the restarted series'' first, not its sixth');
select is(pg_temp.keys('cccc2351-0000-0000-0000-000000000003', 'aaaa2351-0000-0000-0000-000000000003'),
  pg_temp.z(pg_temp.m() + interval '16 days'),
  'and the one after with its second');

-- ── e4: an edit that leaves the start alone ────────────────────────────────

update events set description = 'Bring a head torch', starts_at = starts_at
 where id = 'cccc2351-0000-0000-0000-000000000004';

select is((select instance_start from event_attendees
            where event_id = 'cccc2351-0000-0000-0000-000000000004'),
  '2099-04-04 09:00:42+00'::timestamptz,
  'a description edit keeps the RSVP on its instant, seconds and all');

-- ── e5: a past one-off ─────────────────────────────────────────────────────

update events set starts_at = '2020-05-03 09:00+00'
 where id = 'cccc2351-0000-0000-0000-000000000005';

select is(pg_temp.keys('cccc2351-0000-0000-0000-000000000005', 'aaaa2351-0000-0000-0000-000000000002'),
  '2020-05-02T09:00Z', 'a past occurrence''s RSVP is history and stays where it was');

-- ── e6: a row that cannot follow aborts the edit ───────────────────────────

select throws_ok(
  $$ update events set starts_at = '2099-05-09 09:00+00'
      where id = 'cccc2351-0000-0000-0000-000000000006' $$,
  '23514', null,
  'an edit whose upcoming rows cannot all move is refused rather than strand them');
select is((select pg_temp.z(starts_at) from events where id = 'cccc2351-0000-0000-0000-000000000006'),
  '2099-05-02T09:00Z', 'the refused edit leaves the start as it was');
select is(pg_temp.keys('cccc2351-0000-0000-0000-000000000006', 'aaaa2351-0000-0000-0000-000000000002'),
  '2099-05-02T09:00Z', 'and the RSVP with it');

select * from finish();
rollback;

-- Pins migration 20271112000001 (decisions § 2356, issue #1300 BUG-005):
-- leaving a club (removed, left, or demoted out of `active`) deletes the
-- leaver's upcoming RSVPs and waitlist entries for the club's events they can
-- no longer see, promotes the waitlist into the freed seat, and leaves past
-- occurrences, still-visible public events, pending requests and paid seats
-- alone. Also holds `private.is_event_visible_to` to the events SELECT policy.
--
-- Users: o owner, a removed by the owner, b leaves on their own, c demoted,
-- p pending (rejected), w waitlisted behind a, k paid seat, s stranger.
-- Clubs: pub (public), priv (private), hid (public but shadow-hidden).
-- q holds a checkout in flight.
--   e1  pub, members-only, upcoming, capacity 1: a going, w waitlisted.
--   e2  pub, members-only, 2020 (past): a going.
--   e3  pub, public event, upcoming: a going, p maybe.
--   e4  priv, public event, upcoming: b going, c going.
--   e5  pub, members-only, upcoming: a waitlisted, p maybe, k going on a
--       paid order, q waitlisted with a pending order reserved for 15 min.
--   e6  hid, public event, upcoming (visibility matrix only).

begin;
select plan(19);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaa2356-0000-0000-0000-00000000000f', 'authenticated', 'authenticated', 'exit-o@rsvp.local', '', now(), now()),
  ('aaaa2356-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'exit-a@rsvp.local', '', now(), now()),
  ('aaaa2356-0000-0000-0000-00000000000b', 'authenticated', 'authenticated', 'exit-b@rsvp.local', '', now(), now()),
  ('aaaa2356-0000-0000-0000-00000000000c', 'authenticated', 'authenticated', 'exit-c@rsvp.local', '', now(), now()),
  ('aaaa2356-0000-0000-0000-0000000000a0', 'authenticated', 'authenticated', 'exit-p@rsvp.local', '', now(), now()),
  ('aaaa2356-0000-0000-0000-0000000000b0', 'authenticated', 'authenticated', 'exit-w@rsvp.local', '', now(), now()),
  ('aaaa2356-0000-0000-0000-0000000000c0', 'authenticated', 'authenticated', 'exit-k@rsvp.local', '', now(), now()),
  ('aaaa2356-0000-0000-0000-0000000000d0', 'authenticated', 'authenticated', 'exit-s@rsvp.local', '', now(), now()),
  ('aaaa2356-0000-0000-0000-0000000000e0', 'authenticated', 'authenticated', 'exit-q@rsvp.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public) values
  ('bbbb2356-0000-0000-0000-000000000001', 'aaaa2356-0000-0000-0000-00000000000f', 'Exit Pub', 'exit-pub-2356', true),
  ('bbbb2356-0000-0000-0000-000000000002', 'aaaa2356-0000-0000-0000-00000000000f', 'Exit Priv', 'exit-priv-2356', false),
  ('bbbb2356-0000-0000-0000-000000000003', 'aaaa2356-0000-0000-0000-00000000000f', 'Exit Hid', 'exit-hid-2356', true);
update clubs set shadow_hidden = true where id = 'bbbb2356-0000-0000-0000-000000000003';

insert into club_members (club_id, user_id, role, status) values
  ('bbbb2356-0000-0000-0000-000000000001', 'aaaa2356-0000-0000-0000-00000000000f', 'owner', 'active'),
  ('bbbb2356-0000-0000-0000-000000000001', 'aaaa2356-0000-0000-0000-00000000000a', 'member', 'active'),
  ('bbbb2356-0000-0000-0000-000000000001', 'aaaa2356-0000-0000-0000-0000000000a0', 'member', 'pending'),
  ('bbbb2356-0000-0000-0000-000000000001', 'aaaa2356-0000-0000-0000-0000000000b0', 'member', 'active'),
  ('bbbb2356-0000-0000-0000-000000000001', 'aaaa2356-0000-0000-0000-0000000000c0', 'member', 'active'),
  ('bbbb2356-0000-0000-0000-000000000001', 'aaaa2356-0000-0000-0000-0000000000e0', 'member', 'active'),
  ('bbbb2356-0000-0000-0000-000000000003', 'aaaa2356-0000-0000-0000-00000000000f', 'owner', 'active'),
  ('bbbb2356-0000-0000-0000-000000000003', 'aaaa2356-0000-0000-0000-00000000000a', 'member', 'active'),
  ('bbbb2356-0000-0000-0000-000000000002', 'aaaa2356-0000-0000-0000-00000000000f', 'owner', 'active'),
  ('bbbb2356-0000-0000-0000-000000000002', 'aaaa2356-0000-0000-0000-00000000000b', 'member', 'active'),
  ('bbbb2356-0000-0000-0000-000000000002', 'aaaa2356-0000-0000-0000-00000000000c', 'member', 'active')
on conflict (club_id, user_id) do nothing;

insert into events (id, club_id, title, starts_at, author_id, is_public, capacity) values
  ('cccc2356-0000-0000-0000-000000000001', 'bbbb2356-0000-0000-0000-000000000001', 'e1', '2099-03-07 09:00+00', 'aaaa2356-0000-0000-0000-00000000000f', false, 1),
  ('cccc2356-0000-0000-0000-000000000002', 'bbbb2356-0000-0000-0000-000000000001', 'e2', '2020-03-07 09:00+00', 'aaaa2356-0000-0000-0000-00000000000f', false, null),
  ('cccc2356-0000-0000-0000-000000000003', 'bbbb2356-0000-0000-0000-000000000001', 'e3', '2099-03-07 09:00+00', 'aaaa2356-0000-0000-0000-00000000000f', true, null),
  ('cccc2356-0000-0000-0000-000000000004', 'bbbb2356-0000-0000-0000-000000000002', 'e4', '2099-03-07 09:00+00', 'aaaa2356-0000-0000-0000-00000000000f', true, null),
  ('cccc2356-0000-0000-0000-000000000005', 'bbbb2356-0000-0000-0000-000000000001', 'e5', '2099-03-07 09:00+00', 'aaaa2356-0000-0000-0000-00000000000f', false, null),
  ('cccc2356-0000-0000-0000-000000000006', 'bbbb2356-0000-0000-0000-000000000003', 'e6', '2099-03-07 09:00+00', 'aaaa2356-0000-0000-0000-00000000000f', true, null);

insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                          amount_cents, platform_fee_cents, status)
values ('dddd2356-0000-0000-0000-000000000001', 'cccc2356-0000-0000-0000-000000000005',
        '2099-03-07 09:00+00', 'aaaa2356-0000-0000-0000-0000000000c0',
        'aaaa2356-0000-0000-0000-00000000000f', 2000, 100, 'paid');
insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                          amount_cents, platform_fee_cents, status, reserved_until)
values ('dddd2356-0000-0000-0000-000000000002', 'cccc2356-0000-0000-0000-000000000005',
        '2099-03-07 09:00+00', 'aaaa2356-0000-0000-0000-0000000000e0',
        'aaaa2356-0000-0000-0000-00000000000f', 2000, 100, 'pending', now() + interval '15 minutes');

insert into event_attendees (event_id, user_id, instance_start, status, order_id) values
  ('cccc2356-0000-0000-0000-000000000001', 'aaaa2356-0000-0000-0000-00000000000a', '2099-03-07 09:00+00', 'going', null),
  ('cccc2356-0000-0000-0000-000000000001', 'aaaa2356-0000-0000-0000-0000000000b0', '2099-03-07 09:00+00', 'going', null),
  ('cccc2356-0000-0000-0000-000000000002', 'aaaa2356-0000-0000-0000-00000000000a', '2020-03-07 09:00+00', 'going', null),
  ('cccc2356-0000-0000-0000-000000000003', 'aaaa2356-0000-0000-0000-00000000000a', '2099-03-07 09:00+00', 'going', null),
  ('cccc2356-0000-0000-0000-000000000003', 'aaaa2356-0000-0000-0000-0000000000a0', '2099-03-07 09:00+00', 'maybe', null),
  ('cccc2356-0000-0000-0000-000000000004', 'aaaa2356-0000-0000-0000-00000000000b', '2099-03-07 09:00+00', 'going', null),
  ('cccc2356-0000-0000-0000-000000000004', 'aaaa2356-0000-0000-0000-00000000000c', '2099-03-07 09:00+00', 'going', null),
  ('cccc2356-0000-0000-0000-000000000005', 'aaaa2356-0000-0000-0000-00000000000a', '2099-03-07 09:00+00', 'waitlisted', null),
  ('cccc2356-0000-0000-0000-000000000005', 'aaaa2356-0000-0000-0000-0000000000a0', '2099-03-07 09:00+00', 'maybe', null),
  ('cccc2356-0000-0000-0000-000000000005', 'aaaa2356-0000-0000-0000-0000000000c0', '2099-03-07 09:00+00', 'going', 'dddd2356-0000-0000-0000-000000000001'),
  ('cccc2356-0000-0000-0000-000000000005', 'aaaa2356-0000-0000-0000-0000000000e0', '2099-03-07 09:00+00', 'waitlisted', null);

create function pg_temp.rsvp(p_event uuid, p_user uuid) returns text language sql as $$
  select coalesce(string_agg(status, ',' order by instance_start), '')
    from event_attendees where event_id = p_event and user_id = p_user;
$$;

select is(pg_temp.rsvp('cccc2356-0000-0000-0000-000000000001', 'aaaa2356-0000-0000-0000-0000000000b0'),
  'waitlisted', 'fixture: w is waitlisted behind a on the capped e1');

-- ── the predicate agrees with the events SELECT policy ──
-- Every (event, viewer) pair: owner, active member, pending, stranger, over
-- public / private / shadow-hidden clubs and public / members-only events.
create temp table expected on commit drop as
select e.id as event_id, u.id as user_id, private.is_event_visible_to(e.id, u.id) as visible
  from events e
  cross join (values ('aaaa2356-0000-0000-0000-00000000000f'::uuid),
                     ('aaaa2356-0000-0000-0000-00000000000a'),
                     ('aaaa2356-0000-0000-0000-00000000000b'),
                     ('aaaa2356-0000-0000-0000-0000000000a0'),
                     ('aaaa2356-0000-0000-0000-0000000000d0')) u(id)
 where e.id::text like 'cccc2356-%';
create temp table seen (event_id uuid, user_id uuid) on commit drop;
grant select on expected to authenticated;
grant insert on seen to authenticated;

create function pg_temp.look(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into seen select e.id, p_user from events e where e.id::text like 'cccc2356-%';
  reset role;
end;
$$;

select pg_temp.look(user_id) from (select distinct user_id from expected) u;

select is(
  (select count(*)::int from expected x
    where x.visible is distinct from exists (
      select 1 from seen s where s.event_id = x.event_id and s.user_id = x.user_id)),
  0, 'is_event_visible_to agrees with the events SELECT policy for every viewer');
select ok(
  (select bool_or(visible) and not bool_and(visible) from expected),
  'the matrix covers both visible and hidden pairs');
select is(
  (select string_agg(x.user_id::text, ',' order by x.user_id) from expected x
    where x.event_id = 'cccc2356-0000-0000-0000-000000000006' and x.visible),
  'aaaa2356-0000-0000-0000-00000000000a,aaaa2356-0000-0000-0000-00000000000f',
  'a shadow-hidden club''s public event is seen by its owner and members only');

-- ── reject a pending request: a no-op ──
delete from club_members
 where club_id = 'bbbb2356-0000-0000-0000-000000000001'
   and user_id = 'aaaa2356-0000-0000-0000-0000000000a0';
select is(
  pg_temp.rsvp('cccc2356-0000-0000-0000-000000000005', 'aaaa2356-0000-0000-0000-0000000000a0')
    || '|' || pg_temp.rsvp('cccc2356-0000-0000-0000-000000000003', 'aaaa2356-0000-0000-0000-0000000000a0'),
  'maybe|maybe', 'rejecting a pending request touches none of its RSVPs');

-- ── the owner removes active member a ──
select set_config('request.jwt.claims',
  '{"sub":"aaaa2356-0000-0000-0000-00000000000f","role":"authenticated"}', true);
set local role authenticated;
delete from club_members
 where club_id = 'bbbb2356-0000-0000-0000-000000000001'
   and user_id = 'aaaa2356-0000-0000-0000-00000000000a';
reset role;

select is(pg_temp.rsvp('cccc2356-0000-0000-0000-000000000001', 'aaaa2356-0000-0000-0000-00000000000a'),
  '', 'removal drops the upcoming members-only RSVP');
select is(pg_temp.rsvp('cccc2356-0000-0000-0000-000000000001', 'aaaa2356-0000-0000-0000-0000000000b0'),
  'going', 'the freed seat is promoted to the next waitlisted member');
select is(pg_temp.rsvp('cccc2356-0000-0000-0000-000000000005', 'aaaa2356-0000-0000-0000-00000000000a'),
  '', 'removal drops the upcoming members-only waitlist entry');
select is(pg_temp.rsvp('cccc2356-0000-0000-0000-000000000002', 'aaaa2356-0000-0000-0000-00000000000a'),
  'going', 'a past occurrence''s RSVP is history and stays');
select is(pg_temp.rsvp('cccc2356-0000-0000-0000-000000000003', 'aaaa2356-0000-0000-0000-00000000000a'),
  'going', 'a public event in a public club stays: the leaver can still see it');

-- ── the owner removes k, who holds a paid seat ──
delete from club_members
 where club_id = 'bbbb2356-0000-0000-0000-000000000001'
   and user_id = 'aaaa2356-0000-0000-0000-0000000000c0';
select is(pg_temp.rsvp('cccc2356-0000-0000-0000-000000000005', 'aaaa2356-0000-0000-0000-0000000000c0'),
  'going', 'a seat backed by a paid order stays');
select is(
  (select status || ':' || instance_start::text from event_orders where id = 'dddd2356-0000-0000-0000-000000000001'),
  'paid:2099-03-07 09:00:00+00', 'the paid order is untouched');

-- ── the owner removes q mid-checkout ──
delete from club_members
 where club_id = 'bbbb2356-0000-0000-0000-000000000001'
   and user_id = 'aaaa2356-0000-0000-0000-0000000000e0';
select is(pg_temp.rsvp('cccc2356-0000-0000-0000-000000000005', 'aaaa2356-0000-0000-0000-0000000000e0'),
  'waitlisted', 'a row with a checkout still in flight stays');

-- ── b leaves the private club on their own ──
select set_config('request.jwt.claims',
  '{"sub":"aaaa2356-0000-0000-0000-00000000000b","role":"authenticated"}', true);
set local role authenticated;
delete from club_members
 where club_id = 'bbbb2356-0000-0000-0000-000000000002'
   and user_id = 'aaaa2356-0000-0000-0000-00000000000b';
reset role;
select is(pg_temp.rsvp('cccc2356-0000-0000-0000-000000000004', 'aaaa2356-0000-0000-0000-00000000000b'),
  '', 'leaving a private club drops the RSVP to its public event too');

-- ── c is demoted out of active ──
update club_members set status = 'rejected'
 where club_id = 'bbbb2356-0000-0000-0000-000000000002'
   and user_id = 'aaaa2356-0000-0000-0000-00000000000c';
select is(pg_temp.rsvp('cccc2356-0000-0000-0000-000000000004', 'aaaa2356-0000-0000-0000-00000000000c'),
  '', 'a status change out of active is an exit too');

-- ── a status change that stays active, and the owner's own RSVPs ──
insert into event_attendees (event_id, user_id, instance_start, status) values
  ('cccc2356-0000-0000-0000-000000000004', 'aaaa2356-0000-0000-0000-00000000000f', '2099-03-07 09:00+00', 'going');
update club_members set role = 'admin'
 where club_id = 'bbbb2356-0000-0000-0000-000000000002'
   and user_id = 'aaaa2356-0000-0000-0000-00000000000f';
select is(pg_temp.rsvp('cccc2356-0000-0000-0000-000000000004', 'aaaa2356-0000-0000-0000-00000000000f'),
  'going', 'a role change is not an exit');

-- ── the trigger function is not callable by clients ──
select ok(
  not has_function_privilege('authenticated', 'private.drop_rsvps_on_club_exit()', 'execute')
  and not has_function_privilege('anon', 'private.drop_rsvps_on_club_exit()', 'execute'),
  'drop_rsvps_on_club_exit is not executable by clients');
select ok(
  not has_function_privilege('authenticated', 'private.is_event_visible_to(uuid, uuid)', 'execute')
  and not has_function_privilege('anon', 'private.is_event_visible_to(uuid, uuid)', 'execute'),
  'is_event_visible_to is not executable by clients');

-- ── deleting the club cascades cleanly ──
select lives_ok(
  $$ delete from clubs where id = 'bbbb2356-0000-0000-0000-000000000002' $$,
  'a club delete cascading through its members still succeeds');

select * from finish();
rollback;

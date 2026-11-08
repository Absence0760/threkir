-- Pins migration 20271114002372 (decisions § 2379, issue #1300 BUG-004):
-- only someone who can see an event can RSVP to it, on every write path.
--
-- INSERT was already gated (20260629_001): the self-RSVP policy requires the
-- event to be readable, and the events SELECT policy reads only active
-- membership. The UPDATE policy had no WITH CHECK, so its USING clause
-- (`user_id = auth.uid()`) stood in for it, and `authenticated` holds the
-- column grant on `event_id`. A non-member could RSVP to a public event and
-- then PATCH the row's event_id to a members-only one; a removed member could
-- flip the status of a row the club-exit trigger had kept.
--
-- Users: o owner, m active member, p pending, r removed, s stranger.
-- Clubs: pub (public), priv (private).
--   e_mo    pub, members-only, upcoming
--   e_pub   pub, public event, upcoming
--   e_pub2  pub, public event, upcoming
--   e_past  pub, members-only, 2020: r went while a member
--   e_priv  priv, public event, upcoming

begin;
select plan(18);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaa2372-0000-0000-0000-00000000000f', 'authenticated', 'authenticated', 'mo-o@rsvp.local', '', now(), now()),
  ('aaaa2372-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'mo-m@rsvp.local', '', now(), now()),
  ('aaaa2372-0000-0000-0000-00000000000b', 'authenticated', 'authenticated', 'mo-p@rsvp.local', '', now(), now()),
  ('aaaa2372-0000-0000-0000-00000000000c', 'authenticated', 'authenticated', 'mo-r@rsvp.local', '', now(), now()),
  ('aaaa2372-0000-0000-0000-00000000000d', 'authenticated', 'authenticated', 'mo-s@rsvp.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public) values
  ('bbbb2372-0000-0000-0000-000000000001', 'aaaa2372-0000-0000-0000-00000000000f', 'MO Pub', 'mo-pub-2372', true),
  ('bbbb2372-0000-0000-0000-000000000002', 'aaaa2372-0000-0000-0000-00000000000f', 'MO Priv', 'mo-priv-2372', false);

insert into club_members (club_id, user_id, role, status) values
  ('bbbb2372-0000-0000-0000-000000000001', 'aaaa2372-0000-0000-0000-00000000000f', 'owner', 'active'),
  ('bbbb2372-0000-0000-0000-000000000001', 'aaaa2372-0000-0000-0000-00000000000a', 'member', 'active'),
  ('bbbb2372-0000-0000-0000-000000000001', 'aaaa2372-0000-0000-0000-00000000000b', 'member', 'pending'),
  ('bbbb2372-0000-0000-0000-000000000001', 'aaaa2372-0000-0000-0000-00000000000c', 'member', 'active'),
  ('bbbb2372-0000-0000-0000-000000000002', 'aaaa2372-0000-0000-0000-00000000000f', 'owner', 'active')
on conflict (club_id, user_id) do nothing;

insert into events (id, club_id, title, starts_at, author_id, is_public) values
  ('cccc2372-0000-0000-0000-000000000001', 'bbbb2372-0000-0000-0000-000000000001', 'e_mo',   '2099-03-07 09:00+00', 'aaaa2372-0000-0000-0000-00000000000f', false),
  ('cccc2372-0000-0000-0000-000000000002', 'bbbb2372-0000-0000-0000-000000000001', 'e_pub',  '2099-03-07 09:00+00', 'aaaa2372-0000-0000-0000-00000000000f', true),
  ('cccc2372-0000-0000-0000-000000000003', 'bbbb2372-0000-0000-0000-000000000001', 'e_pub2', '2099-03-08 09:00+00', 'aaaa2372-0000-0000-0000-00000000000f', true),
  ('cccc2372-0000-0000-0000-000000000004', 'bbbb2372-0000-0000-0000-000000000001', 'e_past', '2020-03-07 09:00+00', 'aaaa2372-0000-0000-0000-00000000000f', false),
  ('cccc2372-0000-0000-0000-000000000005', 'bbbb2372-0000-0000-0000-000000000002', 'e_priv', '2099-03-07 09:00+00', 'aaaa2372-0000-0000-0000-00000000000f', true);

-- r went to e_past while a member, then was removed. The club-exit trigger
-- (20271112000001) keeps a past occurrence's row as history.
insert into event_attendees (event_id, user_id, instance_start, status) values
  ('cccc2372-0000-0000-0000-000000000004', 'aaaa2372-0000-0000-0000-00000000000c', '2020-03-07 09:00+00', 'going');
delete from club_members
 where club_id = 'bbbb2372-0000-0000-0000-000000000001'
   and user_id = 'aaaa2372-0000-0000-0000-00000000000c';

create function pg_temp.rsvps(p_user uuid) returns text language sql as $$
  select coalesce(string_agg(e.title || ':' || a.status, ',' order by e.title), '')
    from event_attendees a join events e on e.id = a.event_id
   where a.user_id = p_user and e.id::text like 'cccc2372-%';
$$;
grant execute on function pg_temp.rsvps(uuid) to authenticated;

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

select is(pg_temp.rsvps('aaaa2372-0000-0000-0000-00000000000c'), 'e_past:going',
  'fixture: the removed member''s past RSVP survived the club exit');

-- ── INSERT: a members-only event refuses everyone but an active member ──

select pg_temp.act_as('aaaa2372-0000-0000-0000-00000000000d');
set local role authenticated;
select throws_ok(
  $$ insert into event_attendees (event_id, user_id, instance_start, status)
     values ('cccc2372-0000-0000-0000-000000000001', 'aaaa2372-0000-0000-0000-00000000000d', '2099-03-07 09:00+00', 'going') $$,
  '42501', null, 'a stranger is refused an RSVP to a members-only event');
select throws_ok(
  $$ insert into event_attendees (event_id, user_id, instance_start, status)
     values ('cccc2372-0000-0000-0000-000000000001', 'aaaa2372-0000-0000-0000-00000000000d', '2099-03-07 09:00+00', 'going')
     on conflict (event_id, user_id, instance_start) do update set status = excluded.status $$,
  '42501', null, 'the clients'' upsert form is refused the same way');
select throws_ok(
  $$ insert into event_attendees (event_id, user_id, instance_start, status)
     values ('cccc2372-0000-0000-0000-000000000005', 'aaaa2372-0000-0000-0000-00000000000d', '2099-03-07 09:00+00', 'going') $$,
  '42501', null, 'a stranger is refused an RSVP to a private club''s public event');
reset role;

select pg_temp.act_as('aaaa2372-0000-0000-0000-00000000000b');
set local role authenticated;
select throws_ok(
  $$ insert into event_attendees (event_id, user_id, instance_start, status)
     values ('cccc2372-0000-0000-0000-000000000001', 'aaaa2372-0000-0000-0000-00000000000b', '2099-03-07 09:00+00', 'going') $$,
  '42501', null, 'a pending member is refused an RSVP to a members-only event');
reset role;

select pg_temp.act_as('aaaa2372-0000-0000-0000-00000000000c');
set local role authenticated;
select throws_ok(
  $$ insert into event_attendees (event_id, user_id, instance_start, status)
     values ('cccc2372-0000-0000-0000-000000000001', 'aaaa2372-0000-0000-0000-00000000000c', '2099-03-07 09:00+00', 'going') $$,
  '42501', null, 'a removed member is refused an RSVP to a members-only event');
reset role;

-- The controls: an active member RSVPs to the members-only event, and the
-- stranger to a public one.
select pg_temp.act_as('aaaa2372-0000-0000-0000-00000000000a');
set local role authenticated;
insert into event_attendees (event_id, user_id, instance_start, status)
values ('cccc2372-0000-0000-0000-000000000001', 'aaaa2372-0000-0000-0000-00000000000a', '2099-03-07 09:00+00', 'going');
reset role;
select is(pg_temp.rsvps('aaaa2372-0000-0000-0000-00000000000a'), 'e_mo:going',
  'an active member RSVPs to the members-only event');

select pg_temp.act_as('aaaa2372-0000-0000-0000-00000000000d');
set local role authenticated;
insert into event_attendees (event_id, user_id, instance_start, status)
values ('cccc2372-0000-0000-0000-000000000002', 'aaaa2372-0000-0000-0000-00000000000d', '2099-03-07 09:00+00', 'going');
reset role;
select is(pg_temp.rsvps('aaaa2372-0000-0000-0000-00000000000d'), 'e_pub:going',
  'a stranger RSVPs to a public event in a public club');

-- ── UPDATE ──
-- A filtered update (every PostgREST PATCH) is held to the attendee SELECT
-- policy on the new row, so a move onto an event the caller cannot see was
-- already refused. An update with no WHERE is not: Postgres applies SELECT
-- policies to an UPDATE only when it reads columns, and the UPDATE policy had
-- no WITH CHECK of its own.

select pg_temp.act_as('aaaa2372-0000-0000-0000-00000000000d');
set local role authenticated;
select throws_ok(
  $$ update event_attendees set event_id = 'cccc2372-0000-0000-0000-000000000001'
      where event_id = 'cccc2372-0000-0000-0000-000000000002'
        and user_id = 'aaaa2372-0000-0000-0000-00000000000d' $$,
  '42501', null, 'a stranger is refused moving a public RSVP onto a members-only event');
select throws_ok(
  $$ update event_attendees set event_id = 'cccc2372-0000-0000-0000-000000000001' $$,
  '42501', null, 'the same move with no WHERE clause is refused too');
select throws_ok(
  $$ update event_attendees set event_id = 'cccc2372-0000-0000-0000-000000000003',
                                instance_start = '2099-03-08 09:00+00'
      where event_id = 'cccc2372-0000-0000-0000-000000000002'
        and user_id = 'aaaa2372-0000-0000-0000-00000000000d' $$,
  '42501', 'an RSVP''s event, user and occurrence are fixed: delete it and RSVP again',
  'an RSVP cannot be re-keyed onto another event, even a visible one');
reset role;
select is(pg_temp.rsvps('aaaa2372-0000-0000-0000-00000000000d'), 'e_pub:going',
  'after every attempt the stranger''s only RSVP is still the public one');

select pg_temp.act_as('aaaa2372-0000-0000-0000-00000000000a');
set local role authenticated;
select throws_ok(
  $$ update event_attendees set instance_start = '2099-04-07 09:00+00'
      where event_id = 'cccc2372-0000-0000-0000-000000000001'
        and user_id = 'aaaa2372-0000-0000-0000-00000000000a' $$,
  '42501', 'an RSVP''s event, user and occurrence are fixed: delete it and RSVP again',
  'a member cannot move an RSVP to another occurrence by update');
update event_attendees set status = 'maybe'
 where event_id = 'cccc2372-0000-0000-0000-000000000001'
   and user_id = 'aaaa2372-0000-0000-0000-00000000000a';
reset role;
select is(pg_temp.rsvps('aaaa2372-0000-0000-0000-00000000000a'), 'e_mo:maybe',
  'an active member changes their own members-only RSVP');

-- The removed member's kept row: re-answering it is RSVPing to an event they
-- can no longer see.
select pg_temp.act_as('aaaa2372-0000-0000-0000-00000000000c');
set local role authenticated;
select throws_ok(
  $$ update event_attendees set status = 'maybe' $$,
  '42501', null, 'a removed member is refused re-answering a kept members-only RSVP');
select throws_ok(
  $$ insert into event_attendees (event_id, user_id, instance_start, status)
     values ('cccc2372-0000-0000-0000-000000000004', 'aaaa2372-0000-0000-0000-00000000000c', '2020-03-07 09:00+00', 'maybe')
     on conflict (event_id, user_id, instance_start) do update set status = excluded.status $$,
  '42501', null, 'the upsert form is refused on the kept row as well');
reset role;
select is(pg_temp.rsvps('aaaa2372-0000-0000-0000-00000000000c'), 'e_past:going',
  'the kept row is unchanged after the refused writes');

select ok(
  not has_function_privilege('authenticated', 'private.event_attendees_key_fixed()', 'execute')
  and not has_function_privilege('anon', 'private.event_attendees_key_fixed()', 'execute'),
  'event_attendees_key_fixed is not executable by clients');

select * from finish();
rollback;

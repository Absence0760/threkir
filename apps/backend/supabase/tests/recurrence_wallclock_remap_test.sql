-- Pins migration 20270808000011 (decisions § 1918): the gated remap of
-- instance-keyed rows from a timezoned series' UTC-clock instants onto its
-- wall-clock ones, the transition window in which private.is_event_occurrence
-- accepts both on its lenient default (and only the wall-clock one when a
-- money path asks strictly), the window's close, and the single-shot dry run.
--
-- Series (all America/New_York unless noted; O = UTC-clock instants the old
-- expansion minted, N = wall-clock instants):
--   e1  Wednesdays 21:30 EDT from Wed 2 Sep 2026. O drops the first night and
--       sits on Tuesdays: O1 = 9 Sep 01:30Z (Tue 8th local), N1 = starts_at,
--       N2 = 10 Sep 01:30Z. The pairing that moves least is O(i) -> N(i + 1).
--   e2  MO/TU 21:30 EDT from Mon 19 Oct 2026: O offers Sun + Mon evenings,
--       N Mon + Tue. Every O(i) -> N(i + 1), and O(i)'s target is O(i + 1)'s
--       own instant, so a naive order collides on the primary key.
--   e3  monthly from Sun 31 Jan 2027 21:00 EST: the 28 Feb clamp, then EDT.
--   e4  Wednesdays 07:00 EDT across the 1 Nov 2026 fall-back.
--   e6  e1's shape, with a member who RSVP'd both an O instant and its target,
--       beside another member at the same O instant.
--   e7  a series in 'UTC', whose two clocks are the same.

begin;
select plan(41);

insert into auth.users (id, email, encrypted_password, email_confirmed_at, instance_id, aud, role)
values
  ('99999999-9999-9999-9999-99991918a001', 'org-1918@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('99999999-9999-9999-9999-99991918a002', 'a-1918@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('99999999-9999-9999-9999-99991918a003', 'b-1918@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('99999999-9999-9999-9999-99991918a004', 'c-1918@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
on conflict (id) do nothing;

insert into clubs (id, owner_id, name, slug, is_public, join_policy)
values ('dddddddd-0000-0000-1918-00000000000c', '99999999-9999-9999-9999-99991918a001',
        'Wall Clock 1918', 'wall-clock-1918', true, 'open');

insert into events (id, club_id, title, author_id, starts_at, recurrence_freq,
                    recurrence_byday, recurrence_until, recurrence_count, timezone)
values
  ('eeeeeeee-0000-0000-1918-000000000001', 'dddddddd-0000-0000-1918-00000000000c', 'e1',
   '99999999-9999-9999-9999-99991918a001', '2026-09-03T01:30:00Z', 'weekly',
   array['WE'], null, null, 'America/New_York'),
  ('eeeeeeee-0000-0000-1918-000000000002', 'dddddddd-0000-0000-1918-00000000000c', 'e2',
   '99999999-9999-9999-9999-99991918a001', '2026-10-20T01:30:00Z', 'weekly',
   array['MO','TU'], null, null, 'America/New_York'),
  ('eeeeeeee-0000-0000-1918-000000000003', 'dddddddd-0000-0000-1918-00000000000c', 'e3',
   '99999999-9999-9999-9999-99991918a001', '2027-02-01T02:00:00Z', 'monthly',
   null, null, null, 'America/New_York'),
  ('eeeeeeee-0000-0000-1918-000000000004', 'dddddddd-0000-0000-1918-00000000000c', 'e4',
   '99999999-9999-9999-9999-99991918a001', '2026-10-21T11:00:00Z', 'weekly',
   null, null, null, 'America/New_York'),
  ('eeeeeeee-0000-0000-1918-000000000006', 'dddddddd-0000-0000-1918-00000000000c', 'e6',
   '99999999-9999-9999-9999-99991918a001', '2026-09-03T01:30:00Z', 'weekly',
   array['WE'], null, null, 'America/New_York'),
  ('eeeeeeee-0000-0000-1918-000000000007', 'dddddddd-0000-0000-1918-00000000000c', 'e7',
   '99999999-9999-9999-9999-99991918a001', '2026-09-03T01:30:00Z', 'weekly',
   array['TH'], null, null, 'UTC');

-- Rows on UTC-clock instants, as every build before § 1918 wrote them.
insert into event_attendees (event_id, user_id, instance_start, status) values
  ('eeeeeeee-0000-0000-1918-000000000001', '99999999-9999-9999-9999-99991918a002', '2026-09-09T01:30:00Z', 'going'),
  ('eeeeeeee-0000-0000-1918-000000000001', '99999999-9999-9999-9999-99991918a002', '2026-09-16T01:30:00Z', 'going'),
  ('eeeeeeee-0000-0000-1918-000000000002', '99999999-9999-9999-9999-99991918a003', '2026-10-20T01:30:00Z', 'going'),
  ('eeeeeeee-0000-0000-1918-000000000002', '99999999-9999-9999-9999-99991918a003', '2026-10-26T01:30:00Z', 'going'),
  ('eeeeeeee-0000-0000-1918-000000000002', '99999999-9999-9999-9999-99991918a003', '2026-10-27T01:30:00Z', 'going'),
  ('eeeeeeee-0000-0000-1918-000000000002', '99999999-9999-9999-9999-99991918a003', '2026-11-02T01:30:00Z', 'going'),
  ('eeeeeeee-0000-0000-1918-000000000002', '99999999-9999-9999-9999-99991918a003', '2026-11-03T01:30:00Z', 'going'),
  ('eeeeeeee-0000-0000-1918-000000000003', '99999999-9999-9999-9999-99991918a002', '2027-03-01T02:00:00Z', 'going'),
  ('eeeeeeee-0000-0000-1918-000000000003', '99999999-9999-9999-9999-99991918a002', '2027-04-01T02:00:00Z', 'going'),
  ('eeeeeeee-0000-0000-1918-000000000004', '99999999-9999-9999-9999-99991918a002', '2026-10-28T11:00:00Z', 'going'),
  ('eeeeeeee-0000-0000-1918-000000000004', '99999999-9999-9999-9999-99991918a002', '2026-11-04T11:00:00Z', 'going'),
  ('eeeeeeee-0000-0000-1918-000000000006', '99999999-9999-9999-9999-99991918a004', '2026-09-09T01:30:00Z', 'going'),
  ('eeeeeeee-0000-0000-1918-000000000006', '99999999-9999-9999-9999-99991918a004', '2026-09-10T01:30:00Z', 'going'),
  ('eeeeeeee-0000-0000-1918-000000000006', '99999999-9999-9999-9999-99991918a002', '2026-09-09T01:30:00Z', 'going'),
  ('eeeeeeee-0000-0000-1918-000000000007', '99999999-9999-9999-9999-99991918a002', '2026-09-10T01:30:00Z', 'going');

insert into event_results (event_id, instance_start, user_id, duration_s, distance_m, finisher_status) values
  ('eeeeeeee-0000-0000-1918-000000000002', '2026-10-26T01:30:00Z', '99999999-9999-9999-9999-99991918a003', 1500, 5000, 'finished'),
  ('eeeeeeee-0000-0000-1918-000000000002', '2026-10-27T01:30:00Z', '99999999-9999-9999-9999-99991918a003', 1490, 5000, 'finished');

insert into event_exceptions (event_id, instance_start)
values ('eeeeeeee-0000-0000-1918-000000000001', '2026-09-23T01:30:00Z');

insert into notifications (user_id, kind, event_id, event_instance_start)
values ('99999999-9999-9999-9999-99991918a002', 'event_reminder',
        'eeeeeeee-0000-0000-1918-000000000001', '2026-09-16T01:30:00Z');

insert into club_posts (id, club_id, author_id, body, event_id, event_instance_start)
values ('ffffffff-0000-0000-1918-000000000001', 'dddddddd-0000-0000-1918-00000000000c',
        '99999999-9999-9999-9999-99991918a001', 'See you Tuesday',
        'eeeeeeee-0000-0000-1918-000000000001', '2026-09-09T01:30:00Z');

-- A paid order an old build opened before the strict trigger existed: written
-- with that trigger off, so the remap's move is what it has to accept.
alter table event_orders disable trigger event_orders_validate_occurrence;
insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                          amount_cents, platform_fee_cents, status)
values ('22222222-0000-0000-1918-000000000001', 'eeeeeeee-0000-0000-1918-000000000004',
        '2026-11-04T11:00:00Z', '99999999-9999-9999-9999-99991918a002',
        '99999999-9999-9999-9999-99991918a001', 2000, 100, 'paid');
alter table event_orders enable trigger event_orders_validate_occurrence;

insert into run_photos (id, owner_id, storage_path, event_id, event_instance_start)
values ('11111111-0000-0000-1918-000000000001', '99999999-9999-9999-9999-99991918a001',
        '99999999-9999-9999-9999-99991918a001/e1.jpg',
        'eeeeeeee-0000-0000-1918-000000000001', '2026-09-09T01:30:00Z');

create temp table ids (id uuid) on commit drop;
insert into ids values
  ('eeeeeeee-0000-0000-1918-000000000001'), ('eeeeeeee-0000-0000-1918-000000000002'),
  ('eeeeeeee-0000-0000-1918-000000000003'), ('eeeeeeee-0000-0000-1918-000000000004'),
  ('eeeeeeee-0000-0000-1918-000000000006'), ('eeeeeeee-0000-0000-1918-000000000007');

create function pg_temp.keys(p_event uuid, p_user uuid) returns text language sql as $$
  select coalesce(string_agg(to_char(instance_start at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI"Z"'), ' '
                             order by instance_start), '')
    from event_attendees where event_id = p_event and user_id = p_user;
$$;

-- ── the gate ────────────────────────────────────────────────────────────────

select ok(
  not has_function_privilege('anon', 'private.remap_recurrence_wallclock(int, boolean, timestamptz, uuid[])', 'execute')
  and not has_function_privilege('authenticated', 'private.remap_recurrence_wallclock(int, boolean, timestamptz, uuid[])', 'execute')
  and not has_function_privilege('service_role', 'private.remap_recurrence_wallclock(int, boolean, timestamptz, uuid[])', 'execute'),
  'no API role can run the remap; only an operator connected as the owner can');

select ok(
  not has_function_privilege('authenticated', 'private.close_recurrence_wallclock_transition(boolean)', 'execute')
  and not has_function_privilege('service_role', 'private.close_recurrence_wallclock_transition(boolean)', 'execute'),
  'no API role can close the transition window');

select ok(
  not exists (select 1 from pg_proc p
               where p.prosrc ~ 'remap_recurrence_wallclock\s*\('
                 and p.proname <> 'remap_recurrence_wallclock')
  and not exists (select 1 from cron.job where command ~ 'remap_recurrence_wallclock'),
  'nothing in the database calls the remap: no function body, trigger or cron job');

select is(
  (select enabled from private.feature_flags where name = 'recurrence_utc_clock_legacy'),
  true,
  'the migration seeds the legacy flag enabled');
select ok(private.recurrence_utc_clock_accepted(),
  'so the transition window starts open');

create temp table legacy_flag on commit drop as
  select * from private.feature_flags where name = 'recurrence_utc_clock_legacy';
delete from private.feature_flags where name = 'recurrence_utc_clock_legacy';
select ok(not private.recurrence_utc_clock_accepted()
          and not private.is_event_occurrence('eeeeeeee-0000-0000-1918-000000000001', '2026-09-09T01:30:00Z'),
  'an absent flag row is strict, as every private.feature_flags gate reads');
insert into private.feature_flags select * from legacy_flag;

-- ── inside the window, before any remap ─────────────────────────────────────

select ok(private.is_event_occurrence('eeeeeeee-0000-0000-1918-000000000001', '2026-09-09T01:30:00Z'),
  'the window accepts the UTC-clock instant an old build mints (Tuesday 21:30 local)');
select ok(private.is_event_occurrence('eeeeeeee-0000-0000-1918-000000000001', '2026-09-10T01:30:00Z'),
  'and the wall-clock instant a new build mints (Wednesday 21:30 local)');
select ok(not private.is_event_occurrence('eeeeeeee-0000-0000-1918-000000000001', '2026-09-09T02:30:00Z'),
  'and neither clock admits an hour off either');
select ok(not private.is_event_occurrence('eeeeeeee-0000-0000-1918-000000000001', '2026-09-09T01:30:00Z', false),
  'a strict caller (a money path) refuses the UTC-clock instant even with the window open');
select ok(private.is_event_occurrence('eeeeeeee-0000-0000-1918-000000000001', '2026-09-10T01:30:00Z', false),
  'and accepts the wall-clock one');

-- ── the default is a dry run ────────────────────────────────────────────────

select is(
  (select moved from private.remap_recurrence_wallclock(p_event_ids => array['eeeeeeee-0000-0000-1918-000000000001'::uuid])),
  6::bigint,
  'a dry run reports the rows the remap would move');
select is(pg_temp.keys('eeeeeeee-0000-0000-1918-000000000001', '99999999-9999-9999-9999-99991918a002'),
  '2026-09-09T01:30Z 2026-09-16T01:30Z',
  'and moves none of them');
select ok(not exists (select 1 from private.recurrence_wallclock_remaps l join ids on ids.id = l.event_id),
  'and records nothing, so the real run still sees every series as pending');

select throws_ok(
  $$ select * from private.remap_recurrence_wallclock(1, false, null, array(select id from ids)) $$,
  '22023',
  'a dry run records nothing, so it cannot be batched: 6 series are eligible and p_max_events is 1; pass p_max_events => 6 or narrow p_event_ids',
  'a dry run smaller than the series it would select is refused, so a batched dry-run loop cannot spin forever');
select is(
  (select count(*)::int from private.remap_recurrence_wallclock(6, false, null, array(select id from ids))),
  6,
  'a dry run that covers every eligible series runs in one shot');

-- ── the remap ───────────────────────────────────────────────────────────────

create temp table run1 on commit drop as
  select r.* from private.remap_recurrence_wallclock(100, true, null, array(select id from ids)) r;

select is((select shift from run1 where event_id = 'eeeeeeee-0000-0000-1918-000000000001'), 1,
  'e1 pairs O(i) with N(i + 1): the UTC clock dropped the first Wednesday');
select is(pg_temp.keys('eeeeeeee-0000-0000-1918-000000000001', '99999999-9999-9999-9999-99991918a002'),
  '2026-09-10T01:30Z 2026-09-17T01:30Z',
  'e1: each Tuesday RSVP moves to the Wednesday after it, not the one before');
select is(
  array[
    (select to_char(instance_start at time zone 'UTC', 'MM-DD"T"HH24:MI') from event_exceptions where event_id = 'eeeeeeee-0000-0000-1918-000000000001'),
    (select to_char(event_instance_start at time zone 'UTC', 'MM-DD"T"HH24:MI') from notifications where event_id = 'eeeeeeee-0000-0000-1918-000000000001' and kind = 'event_reminder'),
    (select to_char(event_instance_start at time zone 'UTC', 'MM-DD"T"HH24:MI') from club_posts where id = 'ffffffff-0000-0000-1918-000000000001'),
    (select to_char(event_instance_start at time zone 'UTC', 'MM-DD"T"HH24:MI') from run_photos where id = '11111111-0000-0000-1918-000000000001')
  ],
  array['09-24T01:30', '09-17T01:30', '09-10T01:30', '09-10T01:30'],
  'e1: the cancellation, the reminder, the event post and the host photo move with their occurrence');

select is(
  (select array[moved, conflicts, unmapped] from run1 where event_id = 'eeeeeeee-0000-0000-1918-000000000002'),
  array[7, 0, 0]::bigint[],
  'e2: adjacent weekdays move all seven rows with no collision');
select is(pg_temp.keys('eeeeeeee-0000-0000-1918-000000000002', '99999999-9999-9999-9999-99991918a003'),
  '2026-10-21T01:30Z 2026-10-27T01:30Z 2026-10-28T01:30Z 2026-11-03T02:30Z 2026-11-04T02:30Z',
  'e2: every RSVP keeps its weekday code (UTC Monday -> local Monday), onto local Mon + Tue at 21:30');
select is(
  (select string_agg(to_char(instance_start at time zone 'UTC', 'MM-DD"T"HH24:MI'), ' ' order by instance_start)
     from event_results where event_id = 'eeeeeeee-0000-0000-1918-000000000002'),
  '10-27T01:30 10-28T01:30',
  'e2: results move through the same chain without tripping their unique key');

select is(pg_temp.keys('eeeeeeee-0000-0000-1918-000000000003', '99999999-9999-9999-9999-99991918a002'),
  '2027-03-01T02:00Z 2027-04-01T01:00Z',
  'e3: the 28 February clamp already agreed; the April occurrence moves to 21:00 EDT');

select is(pg_temp.keys('eeeeeeee-0000-0000-1918-000000000004', '99999999-9999-9999-9999-99991918a002'),
  '2026-10-28T11:00Z 2026-11-04T12:00Z',
  'e4: after the fall-back the RSVP moves back to 07:00 local');

select is(
  (select array[moved, conflicts] from run1 where event_id = 'eeeeeeee-0000-0000-1918-000000000006'),
  array[1, 1]::bigint[],
  'e6: a row whose target the same member already holds is left in place and counted, and the others at that instant still move');
select is(pg_temp.keys('eeeeeeee-0000-0000-1918-000000000006', '99999999-9999-9999-9999-99991918a004'),
  '2026-09-09T01:30Z 2026-09-10T01:30Z',
  'e6: both of that member''s rows survive');

select is(
  (select to_char(instance_start at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI"Z"')
     from event_orders where id = '22222222-0000-0000-1918-000000000001'),
  '2026-11-04T12:00Z',
  'e4: the paid order moves onto the wall-clock instant, through the strict occurrence trigger');

select is(
  (select array[shift::bigint, moved] from run1 where event_id = 'eeeeeeee-0000-0000-1918-000000000007'),
  array[0, 0]::bigint[],
  'e7: a series in UTC has one clock and nothing to move');

-- ── idempotence ─────────────────────────────────────────────────────────────

select is(
  (select count(*)::int from private.remap_recurrence_wallclock(100, true, null, array(select id from ids))),
  0,
  'a second run finds every series already remapped');
select is(pg_temp.keys('eeeeeeee-0000-0000-1918-000000000002', '99999999-9999-9999-9999-99991918a003'),
  '2026-10-21T01:30Z 2026-10-27T01:30Z 2026-10-28T01:30Z 2026-11-03T02:30Z 2026-11-04T02:30Z',
  'and moves nothing, though several moved keys are themselves UTC-clock instants');

-- ── the sweep: an old build writes during the window ────────────────────────

insert into event_attendees (event_id, user_id, instance_start, status)
values ('eeeeeeee-0000-0000-1918-000000000001', '99999999-9999-9999-9999-99991918a003',
        '2026-09-30T01:30:00Z', 'going');

select lives_ok($$
  insert into run_photos (id, owner_id, storage_path, event_id, event_instance_start)
  values ('11111111-0000-0000-1918-000000000002', '99999999-9999-9999-9999-99991918a001',
          '99999999-9999-9999-9999-99991918a001/e1-late.jpg',
          'eeeeeeee-0000-0000-1918-000000000001', '2026-09-30T01:30:00Z')
$$, 'an old build''s host photo on a UTC-clock instant still passes the occurrence check inside the window');

-- A new build's Monday 26 Oct RSVP: 01:30Z on the 27th is a wall-clock
-- instant of e2 and, by coincidence, also one of its UTC-clock instants.
insert into event_attendees (event_id, user_id, instance_start, status)
values ('eeeeeeee-0000-0000-1918-000000000002', '99999999-9999-9999-9999-99991918a004',
        '2026-10-27T01:30:00Z', 'going');

create temp table sweep_at on commit drop as select clock_timestamp() as at;
select throws_ok(
  format('select * from private.remap_recurrence_wallclock(1, false, %L, array(select id from ids))',
         (select at from sweep_at)),
  '22023',
  'a dry run records nothing, so it cannot be batched: 6 series are eligible and p_max_events is 1; pass p_max_events => 6 or narrow p_event_ids',
  'a dry-run sweep is single-shot too');
create temp table run2 on commit drop as
  select r.* from private.remap_recurrence_wallclock(100, true, (select at from sweep_at), array(select id from ids)) r;

select is((select moved from run2 where event_id = 'eeeeeeee-0000-0000-1918-000000000001'), 2::bigint,
  'the sweep moves exactly the two rows written after the remap');
select is(pg_temp.keys('eeeeeeee-0000-0000-1918-000000000001', '99999999-9999-9999-9999-99991918a003'),
  '2026-10-01T01:30Z',
  'onto the same pairing the first pass used');
select is(pg_temp.keys('eeeeeeee-0000-0000-1918-000000000002', '99999999-9999-9999-9999-99991918a004'),
  '2026-10-27T01:30Z',
  'the sweep leaves a wall-clock RSVP alone even when its instant is also a UTC-clock one');
select is(
  (select count(*)::int from private.remap_recurrence_wallclock(100, true, (select at from sweep_at), array(select id from ids))),
  0,
  'a sweep with the same cutoff does not revisit a series it already swept');

-- ── closing the window ──────────────────────────────────────────────────────

select throws_ok(
  $$ select private.close_recurrence_wallclock_transition() $$,
  'P0001',
  '1 keyed rows still sit on UTC-clock-only instants; sweep them first or pass p_force => true',
  'the window will not close while a row still sits on a UTC-clock-only instant');

delete from event_attendees
 where event_id = 'eeeeeeee-0000-0000-1918-000000000006' and instance_start = '2026-09-09T01:30:00Z';

select is(private.close_recurrence_wallclock_transition(), 0::bigint,
  'once that row is resolved the window closes');
select is(
  (select enabled from private.feature_flags where name = 'recurrence_utc_clock_legacy'),
  false,
  'by disabling the legacy flag');
select ok(not private.is_event_occurrence('eeeeeeee-0000-0000-1918-000000000001', '2026-09-09T01:30:00Z'),
  'after the close a UTC-clock instant is no occurrence');
select ok(private.is_event_occurrence('eeeeeeee-0000-0000-1918-000000000001', '2026-09-10T01:30:00Z'),
  'and the wall-clock one still is');

select * from finish();
rollback;

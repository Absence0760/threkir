-- Pins migration 20270808000042 (decisions § 1921): Discover's p_byday reads
-- a weekly / biweekly series with an empty or null byday as meeting on the
-- weekday of its start on the EVENT's wall clock — the reading both clients'
-- expandInstances give it — never matches a monthly series, and keeps the
-- one-off and stored-byday behaviour.
--
-- 2099-01-05 01:00Z is Sunday 2099-01-04 20:00 in America/New_York and a
-- Monday in UTC, so every "own weekday" case straddles the UTC date line and
-- a derivation off the UTC clock fails it.

begin;
select plan(13);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('aaaa1921-0000-0000-0000-0000000000d1', 'authenticated', 'authenticated', 'byday-series@disc.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public)
values ('cccc1921-0000-0000-0000-0000000000d1', 'aaaa1921-0000-0000-0000-0000000000d1',
        'Byday Series Club', 'byday-series', true);

insert into events (id, club_id, author_id, title, category, starts_at, timezone,
                    recurrence_freq, recurrence_byday)
values
  -- weekly, stored days TU/TH
  ('eeee1921-0000-0000-0000-0000000000d1', 'cccc1921-0000-0000-0000-0000000000d1',
   'aaaa1921-0000-0000-0000-0000000000d1', 'Stored days', 'run',
   timestamptz '2099-01-06 12:00:00+00', 'UTC', 'weekly', array['TU', 'TH']),
  -- weekly, empty byday, Sunday evening in New York
  ('eeee1921-0000-0000-0000-0000000000d2', 'cccc1921-0000-0000-0000-0000000000d1',
   'aaaa1921-0000-0000-0000-0000000000d1', 'Empty byday', 'run',
   timestamptz '2099-01-05 01:00:00+00', 'America/New_York', 'weekly', '{}'),
  -- biweekly, null byday, same instant
  ('eeee1921-0000-0000-0000-0000000000d3', 'cccc1921-0000-0000-0000-0000000000d1',
   'aaaa1921-0000-0000-0000-0000000000d1', 'Null byday', 'run',
   timestamptz '2099-01-05 01:00:00+00', 'America/New_York', 'biweekly', null),
  -- monthly, no byday, same instant
  ('eeee1921-0000-0000-0000-0000000000d4', 'cccc1921-0000-0000-0000-0000000000d1',
   'aaaa1921-0000-0000-0000-0000000000d1', 'Monthly', 'run',
   timestamptz '2099-01-05 01:00:00+00', 'America/New_York', 'monthly', null),
  -- monthly carrying a stale byday
  ('eeee1921-0000-0000-0000-0000000000d5', 'cccc1921-0000-0000-0000-0000000000d1',
   'aaaa1921-0000-0000-0000-0000000000d1', 'Monthly stale byday', 'run',
   timestamptz '2099-01-05 01:00:00+00', 'America/New_York', 'monthly', array['SA']),
  -- one-off, same instant
  ('eeee1921-0000-0000-0000-0000000000d6', 'cccc1921-0000-0000-0000-0000000000d1',
   'aaaa1921-0000-0000-0000-0000000000d1', 'One-off', 'run',
   timestamptz '2099-01-05 01:00:00+00', 'America/New_York', null, null),
  -- legacy weekly with no timezone and no byday: read on UTC
  ('eeee1921-0000-0000-0000-0000000000d7', 'cccc1921-0000-0000-0000-0000000000d1',
   'aaaa1921-0000-0000-0000-0000000000d1', 'Legacy zone-less', 'run',
   timestamptz '2099-01-05 01:00:00+00', null, 'weekly', '{}');

create temp table hit (id uuid, day text);
grant all on hit to anon;

set local role anon;

insert into hit
select r.id, d.day
  from (values ('MO'), ('TU'), ('WE'), ('TH'), ('FR'), ('SA'), ('SU')) d(day),
       lateral search_public_events(p_byday := d.day) r
 where r.club_id = 'cccc1921-0000-0000-0000-0000000000d1';

select is((select string_agg(day, ',' order by day) from hit where id = 'eeee1921-0000-0000-0000-0000000000d1'),
  'TH,TU', 'a weekly series with stored days is listed under exactly those days');

select is((select count(*)::int from hit where id = 'eeee1921-0000-0000-0000-0000000000d2' and day = 'SU'),
  1, 'a weekly series with an empty byday is listed under its start''s local weekday');
select is((select count(*)::int from hit where id = 'eeee1921-0000-0000-0000-0000000000d2'),
  1, 'and under no other day — not the UTC Monday');

select is((select count(*)::int from hit where id = 'eeee1921-0000-0000-0000-0000000000d3' and day = 'SU'),
  1, 'a biweekly series with a null byday is listed under its start''s local weekday');
select is((select count(*)::int from hit where id = 'eeee1921-0000-0000-0000-0000000000d3'),
  1, 'the null-byday biweekly series is under no other day');

select is((select count(*)::int from hit where id = 'eeee1921-0000-0000-0000-0000000000d4'),
  0, 'a monthly series is under no weekday — its day of the month moves across them');
select is((select count(*)::int from hit where id = 'eeee1921-0000-0000-0000-0000000000d5'),
  0, 'nor is a monthly series that carries a stale byday');

select is((select count(*)::int from hit where id = 'eeee1921-0000-0000-0000-0000000000d6' and day = 'SU'),
  1, 'a one-off is listed under its local weekday');
select is((select count(*)::int from hit where id = 'eeee1921-0000-0000-0000-0000000000d6'),
  1, 'the one-off is under no other day');

select is((select count(*)::int from hit where id = 'eeee1921-0000-0000-0000-0000000000d7' and day = 'MO'),
  1, 'a zone-less legacy series with no byday reads its weekday on UTC');
select is((select count(*)::int from hit where id = 'eeee1921-0000-0000-0000-0000000000d7'),
  1, 'the zone-less legacy series is under no other day');

-- Positive control for every zero above: with no day filter, all seven rows
-- are returned to anon, so a zero is the filter and not a hidden row.
select is(
  (select count(*)::int from search_public_events() r
    where r.club_id = 'cccc1921-0000-0000-0000-0000000000d1'),
  7, 'every fixture series is discoverable without a day filter');

set local time zone 'Asia/Tokyo';

select is(
  (select count(*)::int from search_public_events(p_byday := 'SU') r
    where r.id = 'eeee1921-0000-0000-0000-0000000000d2'),
  1, 'the defaulted weekday follows the event, not the caller''s session timezone');

select * from finish();
rollback;

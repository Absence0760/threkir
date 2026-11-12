-- Pins migration 20270830000011 (issue #1182): the coach roster picks each
-- athlete's current plan by the athlete's local date, read from the
-- `time_zone` universal pref, falling back to the server's date when unset.
--
-- private.athlete_local_date is pinned at fixed instants on either side of
-- midnight, so the changeover cases are deterministic whatever hour this
-- runs at. The roster itself is pinned end to end with plans that change
-- over on each athlete's own local today; an athlete at UTC+14 and one at
-- UTC-11 cannot both share the UTC date at any instant, so at least one of
-- them is a real changeover every time it runs. The trigger refuses a zone
-- Postgres does not know.
begin;
select plan(17);

set local timezone = 'UTC';

-- ─────────── private.athlete_local_date at fixed instants ───────────

select is(private.athlete_local_date('Pacific/Kiritimati', '2031-03-01 12:00:00+00'), '2031-03-02'::date,
  'ahead of UTC: noon UTC is already the next day at UTC+14');
select is(private.athlete_local_date('Pacific/Kiritimati', '2031-03-01 09:00:00+00'), '2031-03-01'::date,
  'ahead of UTC: before 10:00 UTC it is still the same day at UTC+14');
select is(private.athlete_local_date('America/New_York', '2031-03-02 02:00:00+00'), '2031-03-01'::date,
  'behind UTC: 02:00 UTC is still the previous evening in New York');
select is(private.athlete_local_date('America/New_York', '2031-03-02 06:00:00+00'), '2031-03-02'::date,
  'behind UTC: once New York passes midnight the dates agree');
select is(private.athlete_local_date(null, '2031-03-01 23:30:00+00'), '2031-03-01'::date,
  'an unset zone falls back to the server date');
select is(private.athlete_local_date('Mars/Olympus_Mons', '2031-03-01 23:30:00+00'), '2031-03-01'::date,
  'a name Postgres does not know falls back to the server date rather than raising');

-- ─────────── the time_zone pref is validated ───────────

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('1182aaaa-0000-0000-0000-0000000000c1', 'authenticated', 'authenticated', 'coach@crtz.local', '', now(), now()),
  ('1182aaaa-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'ahead@crtz.local', '', now(), now()),
  ('1182aaaa-0000-0000-0000-0000000000b1', 'authenticated', 'authenticated', 'behind@crtz.local', '', now(), now()),
  ('1182aaaa-0000-0000-0000-0000000000d1', 'authenticated', 'authenticated', 'unset@crtz.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name) values
  ('1182aaaa-0000-0000-0000-0000000000a1', 'Ahead'),
  ('1182aaaa-0000-0000-0000-0000000000b1', 'Behind'),
  ('1182aaaa-0000-0000-0000-0000000000d1', 'Unset')
on conflict (id) do nothing;

select throws_ok(
  $$ insert into user_settings (user_id, prefs) values ('1182aaaa-0000-0000-0000-0000000000d1', '{"time_zone":"Mars/Olympus_Mons"}') $$,
  '22023', null,
  'an unknown zone is refused on insert'
);
select throws_ok(
  $$ insert into user_settings (user_id, prefs) values ('1182aaaa-0000-0000-0000-0000000000d1', '{"time_zone":600}') $$,
  '22023', null,
  'a zone that is not a string is refused'
);
select lives_ok(
  $$ insert into user_settings (user_id, prefs) values ('1182aaaa-0000-0000-0000-0000000000d1', '{"preferred_unit":"km","time_zone":null}') $$,
  'an unset zone (JSON null) is accepted'
);
select lives_ok(
  $$ insert into user_settings (user_id, prefs) values
       ('1182aaaa-0000-0000-0000-0000000000a1', '{"time_zone":"Pacific/Kiritimati"}'),
       ('1182aaaa-0000-0000-0000-0000000000b1', '{"time_zone":"Pacific/Pago_Pago"}') $$,
  'known IANA zones are accepted'
);
select throws_ok(
  $$ update user_settings set prefs = prefs || '{"time_zone":"UTC+5"}' where user_id = '1182aaaa-0000-0000-0000-0000000000b1' $$,
  '22023', null,
  'changing the zone to an unknown name is refused'
);
select lives_ok(
  $$ update user_settings set prefs = prefs || '{"preferred_unit":"mi"}' where user_id = '1182aaaa-0000-0000-0000-0000000000b1' $$,
  'another key changes freely beside a stored zone'
);

-- ─────────── the roster picks by each athlete's local date ───────────

insert into coach_athletes (coach_id, athlete_id, status, invite_token, accepted_at) values
  ('1182aaaa-0000-0000-0000-0000000000c1', '1182aaaa-0000-0000-0000-0000000000a1', 'active', 'crtz-tok-a', now()),
  ('1182aaaa-0000-0000-0000-0000000000c1', '1182aaaa-0000-0000-0000-0000000000b1', 'active', 'crtz-tok-b', now()),
  ('1182aaaa-0000-0000-0000-0000000000c1', '1182aaaa-0000-0000-0000-0000000000d1', 'active', 'crtz-tok-d', now());

-- Each athlete: a block that ended on their local yesterday and the next one,
-- starting on their local today. The roster must name the second.
with athletes(user_id, tag, today) as (
  values
    ('1182aaaa-0000-0000-0000-0000000000a1'::uuid, 'a', private.athlete_local_date('Pacific/Kiritimati', now())),
    ('1182aaaa-0000-0000-0000-0000000000b1'::uuid, 'b', private.athlete_local_date('Pacific/Pago_Pago', now())),
    ('1182aaaa-0000-0000-0000-0000000000d1'::uuid, 'd', current_date)
)
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status)
select ('1182bbbb-0000-0000-0000-0000000000' || tag || '1')::uuid, user_id, 'Ended ' || tag, 'distance_10k'::goal_event, 10000, today - 10, today - 1, 4, 'active'
from athletes
union all
select ('1182bbbb-0000-0000-0000-0000000000' || tag || '2')::uuid, user_id, 'Today ' || tag, 'distance_10k'::goal_event, 10000, today, today + 10, 4, 'active'
from athletes;

select ok(
  private.athlete_local_date('Pacific/Kiritimati', now()) <> current_date
    or private.athlete_local_date('Pacific/Pago_Pago', now()) <> current_date,
  'at this instant at least one athlete''s local date differs from the UTC date'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"1182aaaa-0000-0000-0000-0000000000c1","role":"authenticated"}';

select is(
  (select active_plan_id from coach_roster_summary() where athlete_id = '1182aaaa-0000-0000-0000-0000000000a1'),
  '1182bbbb-0000-0000-0000-0000000000a2'::uuid,
  'an athlete ahead of UTC (UTC+14) gets the plan starting on their local today'
);
select is(
  (select active_plan_id from coach_roster_summary() where athlete_id = '1182aaaa-0000-0000-0000-0000000000b1'),
  '1182bbbb-0000-0000-0000-0000000000b2'::uuid,
  'an athlete behind UTC (UTC-11) gets the plan starting on their local today'
);
select is(
  (select active_plan_id from coach_roster_summary() where athlete_id = '1182aaaa-0000-0000-0000-0000000000d1'),
  '1182bbbb-0000-0000-0000-0000000000d2'::uuid,
  'an athlete with no zone set is picked by the server date'
);
reset role;

select is(
  (select prefs ->> 'time_zone' from user_settings where user_id = '1182aaaa-0000-0000-0000-0000000000b1'),
  'Pacific/Pago_Pago',
  'the refused zone change left the stored zone as it was'
);

select * from finish();
rollback;

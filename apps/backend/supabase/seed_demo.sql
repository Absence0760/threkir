-- Opt-in demo dataset for clicking through the app by hand.
--
-- Layered on top of seed.sql, never instead of it: seed.sql is the fixture
-- every Playwright spec and pgtap suite counts against, so growing it would
-- move those counts. This file is NOT named in config.toml's [db.seed], and
-- CI never runs it. Apply it with `bin/seed-demo.sh` after `supabase db reset`
-- (decisions § 2521).
--
-- Contract:
--   * Idempotent. Every row this file owns has a deterministic id
--     (pg_temp.did) or a natural key, and every insert is
--     `on conflict do nothing`, so a second run inserts nothing and fires no
--     AFTER trigger. Dates are relative to the day it first runs; to move
--     them forward, `supabase db reset` and run it again.
--   * It only adds rows. Rows seed.sql owns are never updated or deleted
--     (the one exception: demo-generated notifications get a realistic
--     created_at / read_at, see section 14).
--   * It runs as postgres, so RLS is bypassed, but every CHECK, trigger and
--     consent gate still fires: heart rate is kept only where
--     health_data_consent_at is stamped (decisions § 2514), and the food log
--     is written only for the runner, who has consent.
--   * The park geometry is FICTIONAL (circles and out-and-backs around a
--     real park's centre). It is local demo data, never catalogue data: real
--     courses ship through scripts/parks/ (park_courses.md § Loading courses).
--   * GPS tracks live in Storage, not in a column, so demo runs carry no
--     track_url (as most seed.sql runs don't); run detail shows its no-track
--     state for them.

begin;

-- ───────────────────────── Guards + helpers ─────────────────────────

do $$
begin
  -- tests.confirm_consent() is created by seed.sql alone, which never runs
  -- against production, so its absence means this is not a seeded local
  -- stack. Fail closed rather than write demo rows anywhere else.
  if to_regprocedure('tests.confirm_consent()') is null then
    raise exception 'seed_demo.sql: tests.confirm_consent() is missing, so this database was not seeded by seed.sql; refusing to write demo data';
  end if;
  if not exists (select 1 from auth.users where id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890') then
    raise exception 'seed_demo.sql layers on seed.sql: runner@test.com is missing; run supabase db reset first';
  end if;
end $$;

-- Deterministic uuid for a demo key, so a re-run conflicts instead of
-- duplicating.
create function pg_temp.did(k text) returns uuid
  language sql immutable as $$ select md5('threkir-demo:' || k)::uuid $$;

-- Deterministic pseudo-random number in [0, 1) for a key.
create function pg_temp.rnd(k text) returns double precision
  language sql immutable as $$
    select ('x' || lpad(substr(md5(k), 1, 8), 16, '0'))::bit(64)::bigint / 4294967296.0
  $$;

-- A wall-clock time on a local date in Virginia, as timestamptz.
create function pg_temp.va(d date, t interval) returns timestamptz
  language sql immutable as $$ select (d::timestamp + t) at time zone 'America/New_York' $$;

-- The next date (after today) that falls on ISO weekday `dow` (1 = Monday).
create function pg_temp.next_dow(dow int) returns date
  language sql stable as $$
    select current_date + 1 + ((dow - extract(isodow from current_date + 1)::int + 7) % 7)
  $$;

-- A closed loop of `n` points around (lat, lng), roughly `len_m` long, with a
-- little wobble so it doesn't read as a perfect circle, and an elevation
-- profile between base and base + amp.
create function pg_temp.loop_points(k text, lat double precision, lng double precision,
                                    len_m double precision, base_ele double precision,
                                    amp double precision, n int default 24)
  returns jsonb language sql immutable as $$
    select jsonb_agg(jsonb_build_object(
             'lat', round((lat + (r * (1 + 0.12 * sin(3 * th + ph)) / 111320.0) * sin(th))::numeric, 6),
             'lng', round((lng + (r * (1 + 0.12 * sin(3 * th + ph)) / (111320.0 * cos(radians(lat)))) * cos(th))::numeric, 6),
             'ele', round((base_ele + amp * (0.5 + 0.5 * sin(th + ph)))::numeric, 0))
           order by i)
      from (select i, 2 * pi() * (i % n) / n as th,
                   len_m / (2 * pi()) as r,
                   pg_temp.rnd(k) * 6.28 as ph
              from generate_series(0, n) i) s
  $$;

-- An out-and-back: `len_m / 2` out along a bearing, then back the same way.
create function pg_temp.oab_points(k text, lat double precision, lng double precision,
                                   len_m double precision, base_ele double precision,
                                   amp double precision, n int default 12)
  returns jsonb language sql immutable as $$
    select jsonb_agg(jsonb_build_object(
             'lat', round((lat + (dist * cos(b) + 25 * sin(dist / 180.0)) / 111320.0)::numeric, 6),
             'lng', round((lng + (dist * sin(b)) / (111320.0 * cos(radians(lat))))::numeric, 6),
             'ele', round((base_ele + amp * dist / (len_m / 2))::numeric, 0))
           order by i)
      from (select i,
                   (len_m / 2) * (case when i <= n then i else 2 * n - i end)::double precision / n as dist,
                   radians(pg_temp.rnd(k) * 360) as b
              from generate_series(0, 2 * n) i) s
  $$;

-- Polyline length in metres of a [{lat,lng}] array.
create function pg_temp.line_len(w jsonb) returns numeric
  language sql immutable as $$
    select round(extensions.st_length(extensions.st_makeline(array_agg(
             extensions.st_setsrid(extensions.st_makepoint((p->>'lng')::float8, (p->>'lat')::float8), 4326)
             order by o))::extensions.geography)::numeric, 0)
      from jsonb_array_elements(w) with ordinality as t(p, o)
  $$;

-- ───────────────────────── 1. People ─────────────────────────
-- Eight more runners so the feed, boards and clubs have a crowd. Every one
-- signs in with the seed password `testtest`. Tom has not given health-data
-- consent, so the database strips his runs' heart rate (§ 2514), as it would
-- for a real runner.

create temp table demo_users on commit drop as
select k, pg_temp.did('user:' || k) as id, email, name, handle, consent, home, style, idx
  from (values
    ('sam',    'sam.patel@test.com',    'Sam Patel',     'sampatel_rva',  true,  'rva',    'road',      1),
    ('priya',  'priya.raman@test.com',  'Priya Raman',   'priya_trails',  true,  'cville', 'trail',     2),
    ('marcus', 'marcus.j@test.com',     'Marcus Johnson','marcus_rides',  true,  'rva',    'cyclist',   3),
    ('elena',  'elena.rossi@test.com',  'Elena Rossi',   'elena_walks',   true,  'vb',     'walker',    4),
    ('tom',    'tom.becker@test.com',   'Tom Becker',    'tombecker26',   false, 'nova',   'marathon',  5),
    ('aisha',  'aisha.okafor@test.com', 'Aisha Okafor',  'aisha_c25k',    true,  'rva',    'beginner',  6),
    ('diego',  'diego.alvarez@test.com','Diego Alvarez', 'diego_ridge',   true,  'shen',   'trail',     7),
    ('hannah', 'hannah.kim@test.com',   'Hannah Kim',    'hannah_strolls',true,  'vb',     'stroller',  8)
  ) v(k, email, name, handle, consent, home, style, idx);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change_token_current,
  email_change, phone, phone_change, phone_change_token, reauthentication_token,
  is_sso_user, is_anonymous, raw_app_meta_data, raw_user_meta_data
)
select '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.email,
       extensions.crypt('testtest', extensions.gen_salt('bf')),
       now(), now() - interval '300 days', now(),
       '', '', '', '', '', null, '', '', '',
       false, false,
       '{"provider":"email","providers":["email"]}', '{"email_verified":true}'
  from demo_users u
on conflict (id) do nothing;

insert into auth.identities (id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
select u.id, u.id, u.id,
       jsonb_build_object('sub', u.id, 'email', u.email, 'email_verified', true),
       'email', now(), now(), now()
  from demo_users u
on conflict do nothing;

insert into user_profiles (id, display_name, handle, preferred_unit, subscription_tier,
                           age_confirmed_at, terms_accepted_at, onboarded_at,
                           health_data_consent_at, gender)
select u.id, u.name, u.handle, case when u.k in ('tom', 'hannah') then 'mi' else 'km' end, 'free',
       now(), now(), now(),
       case when u.consent then now() end,
       case when u.consent then (case when u.k in ('priya', 'elena', 'aisha', 'hannah') then 'female' else 'male' end) end
  from demo_users u
on conflict (id) do nothing;

-- The welcome-email trigger queued a lifecycle job per new profile; a demo
-- account asked for no mail.
delete from jobs j
 using demo_users u
 where j.kind = 'lifecycle_email'
   and j.payload->>'template' = 'welcome'
   and j.payload->>'user_id' = u.id::text;

-- Follows. The runner follows everyone; most follow back; a few follow each
-- other and the two seed friends.
insert into user_follows (follower_id, followee_id, followed_at)
select 'a1b2c3d4-e5f6-7890-abcd-ef1234567890', u.id, now() - (u.idx * 9 + 20) * interval '1 day'
  from demo_users u
union all
select u.id, 'a1b2c3d4-e5f6-7890-abcd-ef1234567890', now() - (u.idx * 7 + 3) * interval '1 day'
  from demo_users u where u.k not in ('tom', 'diego')
union all
select a.id, b.id, now() - interval '40 days'
  from demo_users a join demo_users b on a.id <> b.id and (a.idx + b.idx) % 3 = 0
union all
select u.id, s.id, now() - interval '60 days'
  from demo_users u
  cross join (values ('b2c3d4e5-f6a7-8901-bcde-f23456789012'::uuid),
                     ('c3d4e5f6-a7b8-9012-cdef-345678901234'::uuid)) s(id)
 where u.idx % 2 = 1
on conflict do nothing;

-- ───────────────────────── 2. Parks and park courses ─────────────────────────
-- 34 real Virginia parks (real names, plausible centres) with 3-7 courses
-- each. The geometry is generated, not surveyed.

create temp table demo_parks on commit drop as
select pg_temp.did('park:' || slug) as id, slug, name, agency, nps, lat, lng, feature, region, ele, idx
  from (values
    ('james-river-park-system',   'James River Park System',        'other',  null,   37.5300, -77.4560, 'Belle Isle',       'rva',    40, 1),
    ('maymont',                   'Maymont',                        'other',  null,   37.5368, -77.4775, 'Italian Garden',   'rva',    45, 2),
    ('byrd-park',                 'Byrd Park',                      'other',  null,   37.5398, -77.4877, 'Swan Lake',        'rva',    55, 3),
    ('bryan-park',                'Bryan Park',                     'other',  null,   37.5960, -77.4718, 'Young''s Pond',    'rva',    60, 4),
    ('forest-hill-park',          'Forest Hill Park',               'other',  null,   37.5200, -77.4730, 'Reedy Creek',      'rva',    50, 5),
    ('dorey-park',                'Dorey Park',                     'county', null,   37.4920, -77.3560, 'Dorey Lake',       'rva',    45, 6),
    ('robious-landing-park',      'Robious Landing Park',           'county', null,   37.5480, -77.6750, 'River Landing',    'rva',    50, 7),
    ('dutch-gap-conservation-area','Dutch Gap Conservation Area',   'county', null,   37.3600, -77.3700, 'Henricus',         'rva',    10, 8),
    ('ivy-creek-natural-area',    'Ivy Creek Natural Area',         'county', null,   38.0870, -78.5010, 'Ivy Creek',        'cville', 150, 9),
    ('mcintire-park',             'McIntire Park',                  'other',  null,   38.0430, -78.4800, 'Meadow Creek',     'cville', 140, 10),
    ('riverview-park',            'Riverview Park',                 'other',  null,   38.0270, -78.4600, 'Rivanna',          'cville', 110, 11),
    ('ragged-mountain-natural-area','Ragged Mountain Natural Area', 'other',  null,   38.0230, -78.5520, 'Reservoir',        'cville', 180, 12),
    ('shenandoah-national-park',  'Shenandoah National Park',       'nps',    'shen', 38.5300, -78.4400, 'Big Meadows',      'shen',   1000, 13),
    ('sky-meadows-state-park',    'Sky Meadows State Park',         'state',  null,   38.9890, -77.9650, 'Piedmont Overlook','shen',   250, 14),
    ('douthat-state-park',        'Douthat State Park',             'state',  null,   37.8980, -79.8040, 'Douthat Lake',     'shen',   450, 15),
    ('seven-bends-state-park',    'Seven Bends State Park',         'state',  null,   38.8730, -78.4700, 'North Fork',       'shen',   230, 16),
    ('first-landing-state-park',  'First Landing State Park',       'state',  null,   36.9170, -76.0480, 'Cape Henry',       'vb',     4, 17),
    ('false-cape-state-park',     'False Cape State Park',          'state',  null,   36.6340, -75.9150, 'Barbour Hill',     'vb',     3, 18),
    ('mount-trashmore-park',      'Mount Trashmore Park',           'other',  null,   36.8250, -76.1420, 'Lake Windsor',     'vb',     8, 19),
    ('northwest-river-park',      'Northwest River Park',           'county', null,   36.5890, -76.1700, 'Indian Creek',     'vb',     4, 20),
    ('prince-william-forest-park','Prince William Forest Park',     'nps',    'prwi', 38.5850, -77.3800, 'Quantico Creek',   'nova',   70, 21),
    ('great-falls-park',          'Great Falls Park',               'nps',    'grfa', 38.9980, -77.2550, 'Mather Gorge',     'nova',   60, 22),
    ('burke-lake-park',           'Burke Lake Park',                'county', null,   38.7600, -77.3010, 'Burke Lake',       'nova',   90, 23),
    ('leesylvania-state-park',    'Leesylvania State Park',         'state',  null,   38.5880, -77.2600, 'Freestone Point',  'nova',   10, 24),
    ('holliday-lake-state-park',  'Holliday Lake State Park',       'state',  null,   37.3990, -78.6400, 'Holliday Lake',    'central',190, 25),
    ('smith-mountain-lake-state-park','Smith Mountain Lake State Park','state',null,  37.0870, -79.6020, 'Turtle Island',    'roanoke',240, 26),
    ('claytor-lake-state-park',   'Claytor Lake State Park',        'state',  null,   37.0570, -80.6250, 'Claytor Lake',     'roanoke',560, 27),
    ('mill-mountain-park',        'Mill Mountain Park',             'other',  null,   37.2510, -79.9330, 'Roanoke Star',     'roanoke',480, 28),
    ('carvins-cove-natural-reserve','Carvins Cove Natural Reserve', 'other',  null,   37.3740, -79.9590, 'Carvins Cove',     'roanoke',360, 29),
    ('grayson-highlands-state-park','Grayson Highlands State Park', 'state',  null,   36.6290, -81.5090, 'Wilburn Ridge',    'roanoke',1450, 30),
    ('york-river-state-park',     'York River State Park',          'state',  null,   37.4130, -76.7140, 'Taskinas Creek',   'central',15, 31),
    ('belle-isle-state-park',     'Belle Isle State Park',          'state',  null,   37.7810, -76.5960, 'Mulberry Creek',   'central',5, 32),
    ('lake-anna-state-park',      'Lake Anna State Park',           'state',  null,   38.1210, -77.8170, 'Lake Anna',        'central',80, 33),
    ('james-river-state-park',    'James River State Park',         'state',  null,   37.6260, -78.8030, 'Tye River',        'central',200, 34)
  ) v(slug, name, agency, nps, lat, lng, feature, region, ele, idx);

insert into parks (id, slug, name, description, agency, nps_park_code, region_code, country_code,
                   timezone, centroid_lat, centroid_lng,
                   bbox_min_lat, bbox_min_lng, bbox_max_lat, bbox_max_lng)
select p.id, p.slug, p.name,
       'Demo data: the courses here are generated around the park''s centre, not surveyed.',
       p.agency, p.nps, 'US-VA', 'US', 'America/New_York', p.lat, p.lng,
       p.lat - 0.045, p.lng - 0.055, p.lat + 0.045, p.lng + 0.055
  from demo_parks p
on conflict (id) do nothing;

-- Course templates: j is the template index; a park gets the first 3 + idx % 5.
create temp table demo_course_templates on commit drop as
select * from (values
  (0, '%f Loop',               'loop',          3200,  'easy',     'trail', 0.4),
  (1, '%p Perimeter 5K',       'loop',          5000,  'moderate', 'mixed', 0.3),
  (2, '%f Out-and-Back',       'out_and_back',  4400,  'easy',     'trail', 0.5),
  (3, 'Ridge Trail',           'loop',          5600,  'hard',     'trail', 1.0),
  (4, '%p Mile',               'loop',          1609,  'easy',     'road',  0.1),
  (5, 'Woodland Figure Eight', 'loop',          6400,  'moderate', 'trail', 0.6),
  (6, 'Long Loop 10K',         'loop',          10000, 'moderate', 'mixed', 0.5)
) t(j, pattern, shape, len, difficulty, surface, climb);

create temp table demo_courses on commit drop as
select pg_temp.did('course:' || p.slug || ':' || t.j) as id,
       pg_temp.did('segment:' || p.slug || ':' || t.j) as segment_id,
       p.id as park_id, p.slug as park_slug, p.name as park_name, p.region, t.j, t.shape,
       t.difficulty, t.surface,
       replace(replace(t.pattern, '%f', p.feature),
               '%p', regexp_replace(p.name, ' (State Park|National Park|Park|Natural Area|Conservation Area|Natural Reserve|Park System)$', '')) as name,
       case when t.shape = 'loop'
         then pg_temp.loop_points(p.slug || t.j,
                p.lat + (300 + t.j * 160) * sin(radians(t.j * 51 + p.idx * 17)) / 111320.0,
                p.lng + (300 + t.j * 160) * cos(radians(t.j * 51 + p.idx * 17)) / (111320.0 * cos(radians(p.lat))),
                t.len * (0.92 + 0.16 * pg_temp.rnd('len:' || p.slug || t.j)), p.ele,
                greatest(4, t.climb * (case when p.region in ('shen', 'roanoke') then 120 else 30 end)))
         else pg_temp.oab_points(p.slug || t.j, p.lat, p.lng,
                t.len * (0.92 + 0.16 * pg_temp.rnd('len:' || p.slug || t.j)), p.ele,
                greatest(4, t.climb * (case when p.region in ('shen', 'roanoke') then 120 else 30 end)))
       end as waypoints,
       greatest(4, t.climb * (case when p.region in ('shen', 'roanoke') then 120 else 30 end)) as climb_m
  from demo_parks p
  join demo_course_templates t on t.j < 3 + p.idx % 5;

alter table demo_courses add column distance_m numeric;
update demo_courses set distance_m = pg_temp.line_len(waypoints);

insert into global_segments (id, name, description, waypoints, distance_m, elevation_m, surface,
                             region, country_code)
select c.segment_id, c.name,
       'Demo course in ' || c.park_name || '. Generated geometry for local testing.',
       c.waypoints, c.distance_m, round(c.climb_m::numeric * (case when c.shape = 'loop' then 1 else 2 end)),
       c.surface, c.park_name || ', Virginia', 'US'
  from demo_courses c
on conflict (id) do nothing;

insert into park_courses (id, park_id, global_segment_id, slug, course_shape, status, status_note,
                          status_checked_at, geometry_source, source_ref, difficulty, laps)
select c.id, c.park_id, c.segment_id,
       trim(both '-' from regexp_replace(lower(c.name), '[^a-z0-9]+', '-', 'g')),
       c.shape,
       case when c.park_slug = 'false-cape-state-park' and c.j = 2 then 'seasonal'
            when c.park_slug = 'forest-hill-park' and c.j = 2 then 'closed'
            else 'open' end,
       case when c.park_slug = 'false-cape-state-park' and c.j = 2
              then 'The beach section closes 1 April to 31 October for nesting shorebirds.'
            when c.park_slug = 'forest-hill-park' and c.j = 2
              then 'Closed while the footbridge over Reedy Creek is rebuilt.' end,
       case when c.j in (2, 3) then now() - interval '6 days' end,
       'traced', 'demo seed (generated geometry)', c.difficulty,
       case when c.shape = 'loop' then 1 end
  from demo_courses c
on conflict (id) do nothing;

-- ───────────────────────── 3. Races ─────────────────────────
-- Real Virginia-area races, dated relative to today so the calendar always
-- has a past and a future.

create temp table demo_races on commit drop as
select pg_temp.did('race:' || k) as id, k, name, (current_date + off) as race_date, dist, label, lat, lng, verified
  from (values
    ('richmond-marathon',       'Richmond Marathon',                    24,  42195, 'Richmond, VA',          37.5407, -77.4360, true),
    ('richmond-half',           'Richmond Half Marathon',               24,  21098, 'Richmond, VA',          37.5407, -77.4360, true),
    ('richmond-8k',             'Richmond 8K',                          24,   8000, 'Richmond, VA',          37.5407, -77.4360, true),
    ('monument-ave-10k',        'Monument Avenue 10K',                 150,  10000, 'Richmond, VA',          37.5560, -77.4720, true),
    ('shamrock-marathon',       'Shamrock Marathon',                   122,  42195, 'Virginia Beach, VA',    36.8529, -75.9780, true),
    ('shamrock-half',           'Shamrock Half Marathon',              122,  21098, 'Virginia Beach, VA',    36.8529, -75.9780, true),
    ('shamrock-8k',             'Shamrock 8K',                         121,   8000, 'Virginia Beach, VA',    36.8529, -75.9780, true),
    ('cville-ten-miler',        'Charlottesville Ten Miler',           109,  16093, 'Charlottesville, VA',   38.0293, -78.4767, true),
    ('cville-marathon',         'Charlottesville Marathon',            157,  42195, 'Charlottesville, VA',   38.0293, -78.4767, false),
    ('blue-ridge-marathon',     'Blue Ridge Marathon',                 157,  42195, 'Roanoke, VA',           37.2710, -79.9414, true),
    ('star-city-half',          'Star City Half Marathon',             136,  21098, 'Roanoke, VA',           37.2710, -79.9414, false),
    ('va-ten-miler',            'Virginia Ten Miler',                  304,  16093, 'Lynchburg, VA',         37.4138, -79.1422, true),
    ('rnr-vb-half',             'Rock ''n'' Roll Virginia Beach Half', 290,  21098, 'Virginia Beach, VA',    36.8529, -75.9780, true),
    ('harbor-half',             'Norfolk Harbor Half',                 179,  21098, 'Norfolk, VA',           36.8508, -76.2859, false),
    ('cbbt-10k',                'Chesapeake Bay Bridge-Tunnel 10K',    143,  10000, 'Cape Charles, VA',      37.0280, -76.0860, false),
    ('colonial-half',           'Colonial Williamsburg Half',           81,  21098, 'Williamsburg, VA',      37.2707, -76.7075, false),
    ('fredericksburg-half',     'Marine Corps Historic Half',           185,  21098, 'Fredericksburg, VA',    38.3032, -77.4605, true),
    ('harrisonburg-half',       'Harrisonburg Half Marathon',          129,  21098, 'Harrisonburg, VA',      38.4496, -78.8689, false),
    ('jingle-bell-5k',          'Jingle Bell Run 5K',                   29,   5000, 'Richmond, VA',          37.5407, -77.4360, false),
    ('turkey-trot-5k',          'Ashland Turkey Trot 5K',               13,   5000, 'Ashland, VA',           37.7590, -77.4800, false),
    ('new-years-day-10k',       'New Year''s Day 10K',                  49,  10000, 'Virginia Beach, VA',    36.8529, -75.9780, false),
    ('terrapin-50k',            'Terrapin Mountain 50K',               136,  50000, 'Sedalia, VA',           37.4260, -79.4120, true),
    ('holiday-lake-50k',        'Holiday Lake 50K++',                   94,  53000, 'Appomattox, VA',        37.3990, -78.6400, true),
    ('promise-land-50k',        'Promise Land 50K++',                  164,  55000, 'Bedford, VA',           37.5300, -79.4600, true),
    ('bull-run-run-50m',        'Bull Run Run 50 Miler',               150,  80467, 'Clifton, VA',           38.8040, -77.4500, true),
    ('mmt-100',                 'Massanutten Mountain Trails 100',     185, 160934, 'Fort Valley, VA',       38.8600, -78.4000, true),
    ('hellgate-100k',           'Hellgate 100K++',                      27, 106000, 'Natural Bridge Station, VA', 37.6290, -79.5430, true),
    ('ragged-mountain-10k',     'Ragged Mountain Trail 10K',            44,  10000, 'Charlottesville, VA',   38.0230, -78.5520, false),
    ('pocahontas-trail-half',   'Pocahontas Trail Half',                66,  21098, 'Chesterfield, VA',      37.3850, -77.5800, false),
    ('richmond-marathon-past',  'Richmond Marathon (last year)',      -341,  42195, 'Richmond, VA',          37.5407, -77.4360, true),
    ('monument-ave-10k-past',   'Monument Avenue 10K (spring)',       -215,  10000, 'Richmond, VA',          37.5560, -77.4720, true),
    ('cville-ten-miler-past',   'Charlottesville Ten Miler (spring)', -256,  16093, 'Charlottesville, VA',   38.0293, -78.4767, true),
    ('rnr-vb-half-past',        'Rock ''n'' Roll Virginia Beach Half (summer)', -75, 21098, 'Virginia Beach, VA', 36.8529, -75.9780, true),
    ('grindstone-100-past',     'Grindstone 100',                      -48, 160934, 'Swoope, VA',            38.1620, -79.2210, true),
    ('mountain-masochist-past', 'Mountain Masochist Trail Run 50M',    -12,  80467, 'Lynchburg, VA',         37.4138, -79.1422, true),
    ('trashmore-5k-past',       'Mount Trashmore 5K',                  -33,   5000, 'Virginia Beach, VA',    36.8250, -76.1420, false)
  ) v(k, name, off, dist, label, lat, lng, verified);

insert into race_listings (id, provider, provider_race_id, name, race_date, distance_m, location_label,
                           location_point, is_verified)
select r.id, 'manual', null, r.name, r.race_date, r.dist, r.label,
       extensions.st_setsrid(extensions.st_makepoint(r.lng, r.lat), 4326)::extensions.geography,
       r.verified
  from demo_races r
on conflict (id) do nothing;

-- ───────────────────────── 4. Routes ─────────────────────────
-- 42 routes for the runner across road / trail / mixed, some starred, some
-- private; two public routes for each demo friend.

create temp table demo_routes on commit drop as
select pg_temp.did('route:' || owner_k || ':' || n) as id, owner_k, n, name, lat, lng, km, surface, shape,
       is_public, starred, region, ele
  from (values
    ('runner', 1,  'Belle Isle Figure Eight',              37.5300, -77.4530,  5.2, 'mixed', 'loop', true,  true,  'rva', 40),
    ('runner', 2,  'Canal Walk to Rocketts Landing',       37.5310, -77.4250,  8.0, 'road',  'oab',  true,  true,  'rva', 30),
    ('runner', 3,  'Monument Avenue Out-and-Back',         37.5560, -77.4720, 10.0, 'road',  'oab',  true,  false, 'rva', 55),
    ('runner', 4,  'Fan District Easy 6',                  37.5520, -77.4630,  6.0, 'road',  'loop', true,  false, 'rva', 55),
    ('runner', 5,  'Byrd Park Lakes Loop',                 37.5398, -77.4877,  4.6, 'road',  'loop', true,  true,  'rva', 55),
    ('runner', 6,  'Forest Hill Singletrack',              37.5200, -77.4730,  7.4, 'trail', 'loop', true,  false, 'rva', 50),
    ('runner', 7,  'Buttermilk and North Bank Trails',     37.5330, -77.4700, 11.2, 'trail', 'loop', true,  true,  'rva', 45),
    ('runner', 8,  'Bryan Park 5K Loop',                   37.5960, -77.4718,  5.0, 'road',  'loop', true,  false, 'rva', 60),
    ('runner', 9,  'Libby Hill Hill Repeats',              37.5280, -77.4180,  6.5, 'road',  'loop', false, false, 'rva', 40),
    ('runner', 10, 'Virginia Capital Trail to Four Mile Creek', 37.5110, -77.4000, 21.1, 'road', 'oab', true, true, 'rva', 15),
    ('runner', 11, 'Dorey Park Easy Loop',                 37.4920, -77.3560,  4.0, 'mixed', 'loop', true,  false, 'rva', 45),
    ('runner', 12, 'Pony Pasture Rapids Out-and-Back',     37.5470, -77.5470,  9.0, 'trail', 'oab',  true,  false, 'rva', 50),
    ('runner', 13, 'Maymont Garden Loop',                  37.5368, -77.4775,  3.4, 'mixed', 'loop', true,  false, 'rva', 45),
    ('runner', 14, 'Church Hill Sunrise 8K',               37.5320, -77.4170,  8.0, 'road',  'loop', true,  false, 'rva', 45),
    ('runner', 15, 'Richmond Half Course Preview',         37.5407, -77.4360, 21.1, 'road',  'loop', true,  true,  'rva', 50),
    ('runner', 16, 'Lunch Run: VCU to the River',          37.5480, -77.4530,  5.5, 'road',  'oab',  false, false, 'rva', 50),
    ('runner', 17, 'Deep Run Park Recovery Jog',           37.6390, -77.5980,  4.2, 'mixed', 'loop', false, false, 'rva', 70),
    ('runner', 18, 'Robious Landing River Loop',           37.5480, -77.6750,  6.6, 'trail', 'loop', true,  false, 'rva', 50),
    ('runner', 19, 'Pocahontas Lakeside Long Run',         37.3850, -77.5800, 16.0, 'trail', 'loop', true,  false, 'rva', 70),
    ('runner', 20, 'Ashland Trolley Line Trail',           37.7590, -77.4800, 12.0, 'mixed', 'oab',  true,  false, 'rva', 65),
    ('runner', 21, 'Rivanna Trail Full Loop',              38.0330, -78.4700, 32.0, 'trail', 'loop', true,  true,  'cville', 140),
    ('runner', 22, 'Saunders-Monticello Trail Climb',      38.0110, -78.4810,  9.6, 'mixed', 'oab',  true,  false, 'cville', 160),
    ('runner', 23, 'Downtown Mall to UVA Grounds',         38.0310, -78.4880,  6.2, 'road',  'oab',  true,  false, 'cville', 140),
    ('runner', 24, 'Ragged Mountain Reservoir Loop',       38.0230, -78.5520, 10.5, 'trail', 'loop', true,  false, 'cville', 180),
    ('runner', 25, 'Old Rag Summit Hike',                  38.5520, -78.3150, 14.5, 'trail', 'loop', true,  true,  'shen', 400),
    ('runner', 26, 'Whiteoak Canyon Falls',                38.5700, -78.3700, 11.0, 'trail', 'oab',  true,  false, 'shen', 600),
    ('runner', 27, 'Big Meadows to Dark Hollow Falls',     38.5300, -78.4400,  7.2, 'trail', 'loop', true,  false, 'shen', 1000),
    ('runner', 28, 'Massanutten Ridge Traverse',           38.7400, -78.6400, 24.0, 'trail', 'oab',  false, false, 'shen', 600),
    ('runner', 29, 'Skyline Drive Gravel Ride',            38.6500, -78.3300, 60.0, 'mixed', 'oab',  true,  false, 'shen', 900),
    ('runner', 30, 'Virginia Beach Boardwalk 10K',         36.8529, -75.9780, 10.0, 'road',  'oab',  true,  true,  'vb', 3),
    ('runner', 31, 'First Landing Cape Henry Trail',       36.9170, -76.0480,  9.2, 'trail', 'oab',  true,  false, 'vb', 4),
    ('runner', 32, 'Mount Trashmore Summit Repeats',       36.8250, -76.1420,  5.0, 'mixed', 'loop', true,  false, 'vb', 8),
    ('runner', 33, 'Shamrock Course Recon',                36.8529, -75.9780, 21.1, 'road',  'loop', false, false, 'vb', 3),
    ('runner', 34, 'Mount Vernon Trail South',             38.7900, -77.0500, 15.0, 'mixed', 'oab',  true,  false, 'nova', 10),
    ('runner', 35, 'W&OD Trail Tempo',                     38.8800, -77.1700, 12.0, 'road',  'oab',  true,  false, 'nova', 60),
    ('runner', 36, 'Great Falls River Trail',              38.9980, -77.2550,  8.4, 'trail', 'loop', true,  false, 'nova', 60),
    ('runner', 37, 'Roanoke River Greenway',               37.2580, -79.9400, 14.0, 'road',  'oab',  true,  false, 'roanoke', 280),
    ('runner', 38, 'Carvins Cove Gauntlet',                37.3740, -79.9590, 18.5, 'trail', 'loop', true,  false, 'roanoke', 360),
    ('runner', 39, 'Mill Mountain Star 10K',               37.2510, -79.9330, 10.0, 'mixed', 'loop', true,  false, 'roanoke', 480),
    ('runner', 40, 'Neighbourhood Walk with the Dog',      37.5600, -77.4900,  3.2, 'road',  'loop', false, false, 'rva', 55),
    ('runner', 41, 'Sunday Spin: Route 5 to Charles City', 37.4300, -77.2000, 52.0, 'road',  'oab',  true,  false, 'rva', 15),
    ('runner', 42, 'Track Night at the University',        37.5750, -77.5400,  8.0, 'road',  'loop', false, false, 'rva', 60),
    ('sam',    1,  'Sam''s Riverfront 10K',                37.5320, -77.4400, 10.0, 'road',  'loop', true,  false, 'rva', 40),
    ('sam',    2,  'Grace Street Hills',                   37.5500, -77.4700,  7.0, 'road',  'loop', true,  false, 'rva', 55),
    ('priya',  1,  'Ivy Creek Wildflower Loop',            38.0870, -78.5010,  6.0, 'trail', 'loop', true,  false, 'cville', 150),
    ('priya',  2,  'Humpback Rocks Climb',                 37.9670, -78.8960,  9.0, 'trail', 'oab',  true,  false, 'shen', 700),
    ('marcus', 1,  'Capital Trail Century Prep',           37.4500, -77.2500, 80.0, 'road',  'oab',  true,  false, 'rva', 15),
    ('marcus', 2,  'Bryan Park Crit Loop',                 37.5960, -77.4718,  3.0, 'road',  'loop', true,  false, 'rva', 60),
    ('elena',  1,  'Seashore Trail Ramble',                36.9100, -76.0400,  8.5, 'trail', 'oab',  true,  false, 'vb', 4),
    ('elena',  2,  'Lake Smith Morning Walk',              36.8900, -76.1200,  5.0, 'road',  'loop', true,  false, 'vb', 5),
    ('tom',    1,  'Rock Creek to Georgetown',             38.9000, -77.0500, 18.0, 'road',  'oab',  true,  false, 'nova', 20),
    ('tom',    2,  'Burke Lake 7.2',                       38.7600, -77.3010,  7.2, 'mixed', 'loop', true,  false, 'nova', 90),
    ('aisha',  1,  'My First 5K Route',                    37.5800, -77.4900,  5.0, 'road',  'loop', true,  false, 'rva', 60),
    ('aisha',  2,  'Run-Walk Around Byrd Park',            37.5398, -77.4877,  3.5, 'road',  'loop', true,  false, 'rva', 55),
    ('diego',  1,  'Signal Knob Loop',                     38.9450, -78.3130, 16.6, 'trail', 'loop', true,  false, 'shen', 500),
    ('diego',  2,  'Strickler Knob Scramble',              38.6950, -78.6000, 15.0, 'trail', 'oab',  true,  false, 'shen', 600),
    ('hannah', 1,  'Stroller-Friendly Oceanfront',         36.8600, -75.9780,  6.0, 'road',  'oab',  true,  false, 'vb', 3),
    ('hannah', 2,  'Red Wing Park Loop',                   36.7900, -76.0100,  4.0, 'road',  'loop', true,  false, 'vb', 4)
  ) v(owner_k, n, name, lat, lng, km, surface, shape, is_public, starred, region, ele);

insert into routes (id, user_id, name, waypoints, distance_m, elevation_m, surface, is_public, is_starred,
                    description, created_at)
select r.id,
       coalesce(u.id, 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'),
       r.name, w.pts, pg_temp.line_len(w.pts),
       round(greatest(5, r.km * (case r.surface when 'trail' then 22 when 'mixed' then 9 else 5 end))),
       r.surface, r.is_public, r.starred,
       case when r.n % 3 = 0 then 'Demo route. ' || case r.surface when 'trail' then 'Rooty in places; good shoes help.'
                                                   when 'mixed' then 'Mostly paved with a gravel stretch.'
                                                   else 'Flat and fast, best early before traffic.' end end,
       now() - (r.n * 4 + 10) * interval '1 day'
  from demo_routes r
  left join demo_users u on u.k = r.owner_k
  cross join lateral (select case when r.shape = 'loop'
           then pg_temp.loop_points('route' || r.id, r.lat, r.lng, r.km * 1000, r.ele,
                  case r.surface when 'trail' then 40 when 'mixed' then 15 else 6 end, 32)
           else pg_temp.oab_points('route' || r.id, r.lat, r.lng, r.km * 1000, r.ele,
                  case r.surface when 'trail' then 40 when 'mixed' then 15 else 6 end, 16) end as pts) w
on conflict (id) do nothing;

-- The runner keeps a few friends' public routes in the library.
insert into saved_routes (user_id, route_id, saved_at)
select 'a1b2c3d4-e5f6-7890-abcd-ef1234567890', r.id, now() - r.n * interval '5 days'
  from demo_routes r
 where r.owner_k in ('sam', 'priya', 'diego', 'hannah')
on conflict do nothing;

-- ───────────────────────── 5. The runner's six months ─────────────────────────
-- About five sessions a week for 182 days: easy runs (some on a saved
-- route), a weekly long run (every third one a trail run in the mountains),
-- tempo or a bike ride midweek, and a walk or hike. Heart rate is kept: the
-- runner has health-data consent.

create temp table demo_runner_days on commit drop as
select d,
       case when d % 7 = 0 then (case when d % 21 = 0 then 'trail_long' else 'long' end)
            when d % 7 = 3 then (case when d % 14 = 3 then 'cycle' else 'tempo' end)
            when d % 7 = 5 then (case when d % 21 = 5 then 'hike' else 'walk' end)
            else 'easy' end as kind,
       pg_temp.rnd('runner-day:' || d) as x
  from generate_series(1, 182) d
 where d % 7 <> 2 and d % 11 <> 0;

create temp table demo_runner_runs on commit drop as
select pg_temp.did('run:runner:' || d.d) as id, d.d, d.kind, d.x,
       case d.kind when 'cycle' then 'cycle' when 'walk' then 'walk' when 'hike' then 'hike' else 'run' end as activity,
       rt.id as route_id,
       round(case
         when rt.id is not null then rt_len.len * (1.0 + d.x * 0.03)
         when d.kind = 'long'       then 15000 + d.x * 9000
         when d.kind = 'trail_long' then 14000 + d.x * 8000
         when d.kind = 'tempo'      then 8000 + d.x * 3000
         when d.kind = 'cycle'      then 35000 + d.x * 30000
         when d.kind = 'walk'       then 3500 + d.x * 3000
         when d.kind = 'hike'       then 9000 + d.x * 6000
         else 6000 + d.x * 4000 end) as distance_m,
       case d.kind
         when 'long' then 345 when 'trail_long' then 430 when 'tempo' then 286
         when 'cycle' then 138 when 'walk' then 640 when 'hike' then 790
         else 330 end * (0.97 + 0.06 * pg_temp.rnd('pace:' || d.d)) as pace_s_per_km
  from demo_runner_days d
  left join lateral (
    select r.id from demo_routes r
     where d.kind = 'easy' and d.d % 3 = 0 and r.owner_k = 'runner' and r.region = 'rva'
       and r.km between 3 and 12
     order by pg_temp.rnd('pick:' || d.d || r.id) limit 1) rt on true
  left join lateral (select distance_m as len from routes where id = rt.id) rt_len on true;

insert into runs (id, user_id, started_at, duration_s, distance_m, source, is_public, route_id,
                  activity_type, elevation_gain_m, fastest_5k_s, fastest_10k_s, metadata)
select r.id, 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
       pg_temp.va(current_date - r.d,
                  case when r.d % 3 = 1 then interval '17 hours 40 minutes' else interval '6 hours 10 minutes' end
                  + (r.x * 50)::int * interval '1 minute'),
       round(r.distance_m / 1000.0 * r.pace_s_per_km)::int,
       r.distance_m,
       (array['app', 'watch', 'strava', 'healthconnect'])[1 + r.d % 4],
       r.d % 6 <> 0,
       r.route_id,
       r.activity,
       round(case r.kind when 'trail_long' then 600 + r.x * 500 when 'hike' then 500 + r.x * 400
                         when 'cycle' then 250 + r.x * 300 when 'long' then 120 + r.x * 90
                         else 30 + r.x * 60 end),
       case when r.activity = 'run' and r.kind <> 'trail_long' and r.distance_m >= 5000
            then round(5 * r.pace_s_per_km * (0.96 - case r.kind when 'tempo' then 0.03 else 0 end))::int end,
       case when r.activity = 'run' and r.kind <> 'trail_long' and r.distance_m >= 10000
            then round(10 * r.pace_s_per_km * 0.975)::int end,
       jsonb_strip_nulls(jsonb_build_object(
         'title', case r.kind
                    when 'long' then (array['Sunday long run', 'Long run along the river', 'Long and steady', 'Easy long miles'])[1 + r.d % 4]
                    when 'trail_long' then (array['Trail long run in Shenandoah', 'Mountain miles on the AT', 'Massanutten ridge run'])[1 + r.d % 3]
                    when 'tempo' then (array['Tempo on the Capital Trail', 'Threshold 3 x 2 km', 'Progression run', 'Cruise intervals'])[1 + r.d % 4]
                    when 'cycle' then (array['Recovery spin', 'Gravel ride to Charles City', 'Group ride'])[1 + r.d % 3]
                    when 'walk' then (array['Walk with the dog', 'Lunchtime walk', 'Evening stroll'])[1 + r.d % 3]
                    when 'hike' then (array['Old Rag hike', 'Hike to Dark Hollow Falls', 'Humpback Rocks hike'])[1 + r.d % 3]
                    else (array['Easy run', 'Morning shakeout', 'Recovery jog', 'Easy miles in the Fan', 'Before-work run'])[1 + r.d % 5] end,
         'avg_bpm', round(case r.kind when 'tempo' then 166 when 'long' then 151 when 'trail_long' then 148
                                      when 'cycle' then 128 when 'walk' then 104 when 'hike' then 121 else 146 end
                          + r.x * 8),
         'max_bpm', round(case r.kind when 'tempo' then 181 when 'walk' then 122 when 'cycle' then 158 else 170 end + r.x * 8),
         'steps', case when r.activity in ('run', 'walk', 'hike')
                       then round(r.distance_m / (case when r.activity = 'run' then 1.15 else 0.78 end)) end,
         'perceived_effort', case r.kind when 'tempo' then 7 when 'long' then 6 when 'trail_long' then 7
                                         when 'walk' then 2 when 'hike' then 5 when 'cycle' then 4 else 3 end,
         'sub_sport', case when r.kind = 'trail_long' then 'trail' end,
         'notes', case when r.d % 9 = 0 then 'Legs felt good. Fuelled with one gel at 45 min.' end
       ))
  from demo_runner_runs r
on conflict (id) do nothing;

-- Three past races in the race calendar, run by the runner.
insert into runs (id, user_id, started_at, duration_s, distance_m, source, is_public, race_listing_id,
                  activity_type, fastest_5k_s, fastest_10k_s, fastest_half_marathon_s, metadata)
select pg_temp.did('run:runner:race:' || r.k), 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
       pg_temp.va(r.race_date, interval '7 hours 30 minutes'), v.t, r.dist, 'race', true, r.id, 'run',
       case when r.dist >= 5000 then round(v.t * 5000.0 / r.dist * 0.99)::int end,
       case when r.dist >= 10000 then round(v.t * 10000.0 / r.dist * 0.995)::int end,
       case when r.dist >= 21097 then v.t end,
       jsonb_build_object('title', r.name, 'race_name', r.name, 'avg_bpm', v.bpm,
                          'chip_time', to_char(make_interval(secs => v.t), 'FMHH24:MI:SS'),
                          'overall_place', v.place)
  from demo_races r
  join (values ('monument-ave-10k-past', 2585, 171, 812),
               ('cville-ten-miler-past', 4410, 168, 233),
               ('rnr-vb-half-past',      5930, 169, 461)) v(k, t, bpm, place) on v.k = r.k
on conflict (id) do nothing;

-- ───────────────────────── 6. Friends' runs (the feed) ─────────────────────────
-- Seven weeks for each demo friend, several inside the 14-day feed window,
-- and one in the last few hours each so "run completed" notices fire.

create temp table demo_friend_runs on commit drop as
select pg_temp.did('run:' || u.k || ':' || d) as id, u.id as user_id, u.k, u.style, u.home, u.idx, d,
       pg_temp.rnd(u.k || ':' || d) as x
  from demo_users u
  cross join generate_series(0, 48) d
 where d = 0 or (d + u.idx) % 2 = 0 or (u.style in ('road', 'marathon') and d % 3 = 0);

alter table demo_friend_runs add column activity text, add column distance_m numeric,
  add column pace numeric, add column vert numeric, add column title text;

update demo_friend_runs f set
  activity = case
    when f.style = 'cyclist' and f.d % 3 <> 0 then 'cycle'
    when f.style = 'walker' then (case when f.d % 4 = 0 then 'hike' else 'walk' end)
    when f.style = 'stroller' then (case when f.d % 3 = 0 then 'stroller' else 'run' end)
    when f.style = 'beginner' and f.d % 4 = 1 then 'walk'
    else 'run' end;

update demo_friend_runs f set
  distance_m = round(case
    when f.activity = 'cycle' then 25000 + f.x * 45000
    when f.activity = 'hike' then 8000 + f.x * 7000
    when f.activity = 'walk' then 3500 + f.x * 4500
    when f.activity = 'stroller' then 4500 + f.x * 3500
    when f.style = 'trail' then 8000 + f.x * (case when f.d % 7 = 0 then 24000 else 9000 end)
    when f.style = 'marathon' then 10000 + f.x * (case when f.d % 7 = 0 then 22000 else 8000 end)
    when f.style = 'beginner' then 3000 + f.x * 2500
    else 5000 + f.x * 11000 end),
  pace = case
    when f.activity = 'cycle' then 130 + f.x * 20
    when f.activity = 'hike' then 760 + f.x * 80
    when f.activity = 'walk' then 620 + f.x * 60
    when f.activity = 'stroller' then 380 + f.x * 30
    when f.style = 'trail' then 400 + f.x * 80
    when f.style = 'marathon' then 290 + f.x * 25
    when f.style = 'beginner' then 410 + f.x * 40
    when f.style = 'cyclist' then 330 + f.x * 20
    else 295 + f.x * 30 end,
  vert = case when f.style = 'trail' or f.activity = 'hike' then 300 + f.x * 900 else 20 + f.x * 80 end;

update demo_friend_runs f set title = case
    when f.activity = 'cycle' then (array['Capital Trail spin', 'Hill reps on the bike', 'Coffee ride', 'Long ride out to Varina'])[1 + f.d % 4]
    when f.activity = 'hike' then (array['Seashore Trail hike', 'Sunday hike', 'Back Bay ramble'])[1 + f.d % 3]
    when f.activity = 'walk' then (array['Morning walk', 'Beach walk', 'Walk and talk'])[1 + f.d % 3]
    when f.activity = 'stroller' then (array['Stroller miles', 'Run with the little one', 'Stroller loop at Red Wing'])[1 + f.d % 3]
    when f.style = 'trail' then (array['Ridge run', 'Trail miles', 'Vert day', 'Technical singletrack', 'Long trail day'])[1 + f.d % 5]
    when f.style = 'marathon' then (array['Marathon pace miles', 'Easy recovery', 'Long run, last 5K fast', 'Track 6 x 1 km'])[1 + f.d % 4]
    when f.style = 'beginner' then (array['Couch to 5K: week 6', 'Run-walk intervals', 'First non-stop 3K!', 'Parkrun practice'])[1 + f.d % 4]
    else (array['Easy run', 'Tempo Tuesday', 'River loop', 'Hill repeats', 'Shakeout'])[1 + f.d % 5] end;

insert into runs (id, user_id, started_at, duration_s, distance_m, source, is_public, activity_type,
                  elevation_gain_m, fastest_5k_s, metadata)
select f.id, f.user_id,
       case when f.d = 0 then now() - round(f.distance_m / 1000.0 * f.pace) * interval '1 second'
                              - (1 + f.idx) * interval '35 minutes'
            else pg_temp.va(current_date - f.d,
                            case when f.idx % 2 = 0 then interval '6 hours' else interval '17 hours 30 minutes' end
                            + (f.x * 70)::int * interval '1 minute') end,
       round(f.distance_m / 1000.0 * f.pace)::int, f.distance_m,
       (array['app', 'strava', 'watch', 'healthconnect', 'garmin'])[1 + (f.d + f.idx) % 5],
       f.d % 9 <> 4,
       f.activity, round(f.vert),
       case when f.activity = 'run' and f.distance_m >= 5000 then round(5 * f.pace * 0.97)::int end,
       jsonb_build_object('title', f.title,
                          'avg_bpm', round(140 + f.x * 25),
                          'perceived_effort', 3 + (f.d % 5))
  from demo_friend_runs f
on conflict (id) do nothing;

-- ───────────────────────── 7. Park course efforts ─────────────────────────
-- Each foot activity is timed on a course in its owner's area: usually their
-- home area, sometimes a neighbouring one (the runner's mountain long runs and
-- hikes count in Shenandoah). A few "local favourite" courses per area take
-- about half of all efforts, so their monthly and season boards have a crowd
-- of runners; the rest spread over the long tail. Alex's and Morgan's recent
-- seed.sql runs are timed too, as extra Richmond regulars.

create temp table demo_hot_courses on commit drop as
select c.segment_id
  from demo_courses c
  join (values ('byrd-park', 1), ('james-river-park-system', 0), ('bryan-park', 1),
               ('riverview-park', 0), ('ivy-creek-natural-area', 1),
               ('shenandoah-national-park', 0), ('sky-meadows-state-park', 1),
               ('first-landing-state-park', 0), ('mount-trashmore-park', 1),
               ('burke-lake-park', 1), ('great-falls-park', 0)) h(slug, j)
    on h.slug = c.park_slug and h.j = c.j;

create temp table demo_effort_runs on commit drop as
select r.id as run_id, r.user_id, r.started_at, r.distance_m,
       r.duration_s / r.distance_m as pace_s_per_m,
       case
         when r.user_id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
              and (r.metadata->>'sub_sport' = 'trail' or r.activity_type = 'hike') then 'shen'
         when r.user_id in ('a1b2c3d4-e5f6-7890-abcd-ef1234567890',
                            'b2c3d4e5-f6a7-8901-bcde-f23456789012',
                            'c3d4e5f6-a7b8-9012-cdef-345678901234') then 'rva'
         when pg_temp.rnd('travel:' || r.id) < 0.25 then
           case u.k when 'sam' then 'cville' when 'priya' then 'rva' when 'diego' then 'cville'
                    when 'tom' then 'rva' else u.home end
         else u.home end as region,
       pg_temp.rnd('hot:' || r.id) < 0.55 as to_hot
  from runs r
  left join demo_users u on u.id = r.user_id
 where (r.id in (select id from demo_runner_runs union all select id from demo_friend_runs)
        or (r.user_id in ('b2c3d4e5-f6a7-8901-bcde-f23456789012', 'c3d4e5f6-a7b8-9012-cdef-345678901234')
            and r.is_public and r.started_at > now() - interval '45 days'))
   and r.activity_type <> 'cycle'
   and r.distance_m > 0 and r.duration_s > 0
   and r.started_at > now() - interval '182 days';

insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at, matched_by)
select p.segment_id, p.run_id, p.user_id,
       round(p.course_m * p.pace_s_per_m * (0.95 + 0.08 * pg_temp.rnd('effort:' || p.run_id || p.segment_id)))::numeric,
       p.started_at + (pg_temp.rnd('offset:' || p.run_id || p.segment_id) * 600)::int * interval '1 second',
       'gate'
  from (
    select e.*, c.segment_id, c.distance_m as course_m,
           row_number() over (
             partition by e.run_id
             order by (e.to_hot and c.segment_id in (select segment_id from demo_hot_courses)) desc,
                      pg_temp.rnd(e.run_id::text || c.segment_id::text)) as rn
      from demo_effort_runs e
      join demo_courses c on c.region = e.region and c.distance_m <= e.distance_m * 0.95
  ) p
 where p.rn = 1 or (p.rn = 2 and p.distance_m > 12000)
on conflict (global_segment_id, run_id) do nothing;

-- ───────────────────────── 8. Kudos, comments, reactions, reviews ─────────────────────────

insert into run_kudos (user_id, run_id, given_at)
select u.id, r.id, least(now() - interval '5 minutes', r.started_at + r.duration_s * interval '1 second'
                         + (1 + u.idx * 3) * interval '17 minutes')
  from runs r
  join demo_users u on pg_temp.rnd('kudos:' || u.k || r.id) < 0.45
 where r.user_id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
   and r.is_public and r.started_at > now() - interval '45 days'
   and r.id in (select id from demo_runner_runs)
union all
select 'a1b2c3d4-e5f6-7890-abcd-ef1234567890', r.id,
       least(now() - interval '2 minutes', r.started_at + r.duration_s * interval '1 second' + interval '3 hours')
  from runs r
 where r.id in (select id from demo_friend_runs) and r.is_public
   and r.started_at > now() - interval '14 days'
   and pg_temp.rnd('kudos:runner' || r.id) < 0.6
union all
select f.id, r.id, least(now() - interval '1 minute', r.started_at + r.duration_s * interval '1 second' + interval '90 minutes')
  from runs r
  join demo_users f on f.id <> r.user_id and pg_temp.rnd('kudos:' || f.k || r.id) < 0.3
 where r.id in (select id from demo_friend_runs) and r.is_public
   and r.started_at > now() - interval '14 days'
on conflict do nothing;

create temp table demo_comment_lines on commit drop as
select * from (values
  (0, 'Great pace on that one!'),
  (1, 'Those hills are no joke. Nice work.'),
  (2, 'Looking strong for the half!'),
  (3, 'Was that you on the Capital Trail this morning? Waved!'),
  (4, 'Recovery done right.'),
  (5, 'See you Saturday for the long run?'),
  (6, 'That last split though!'),
  (7, 'Shoes holding up OK on the trail?'),
  (8, 'Love this route. Saving it.'),
  (9, 'Steady and consistent. Love to see it.')
) v(n, body);

insert into run_comments (id, run_id, author_id, body, created_at, updated_at)
select pg_temp.did('comment:' || r.id || ':' || u.k), r.id, u.id, l.body, t.at, t.at
  from runs r
  join demo_users u on pg_temp.rnd('comment:' || u.k || r.id) < 0.18
  join demo_comment_lines l on l.n = (abs(hashtext(u.k || r.id::text)) % 10)
  cross join lateral (select least(now() - interval '3 minutes',
                        r.started_at + r.duration_s * interval '1 second' + (2 + u.idx) * interval '23 minutes') as at) t
 where r.user_id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890' and r.is_public
   and r.started_at > now() - interval '30 days'
   and r.id in (select id from demo_runner_runs)
union all
select pg_temp.did('comment:' || r.id || ':runner'), r.id, 'a1b2c3d4-e5f6-7890-abcd-ef1234567890', l.body, t.at, t.at
  from runs r
  join demo_comment_lines l on l.n = (abs(hashtext('runner' || r.id::text)) % 10)
  cross join lateral (select least(now() - interval '1 minute',
                        r.started_at + r.duration_s * interval '1 second' + interval '4 hours') as at) t
 where r.id in (select id from demo_friend_runs) and r.is_public
   and r.started_at > now() - interval '10 days'
   and pg_temp.rnd('comment:runner' || r.id) < 0.25
on conflict (id) do nothing;

-- A reply from the runner on the newest commented run of theirs.
insert into run_comments (id, run_id, author_id, parent_comment_id, body, created_at, updated_at)
select pg_temp.did('reply:' || c.id), c.run_id, 'a1b2c3d4-e5f6-7890-abcd-ef1234567890', c.id,
       'Thanks! Felt easier than it looked.', least(now(), c.created_at + interval '40 minutes'),
       least(now(), c.created_at + interval '40 minutes')
  from run_comments c
  join runs r on r.id = c.run_id and r.user_id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
 where c.author_id in (select id from demo_users) and c.parent_comment_id is null
 order by c.created_at desc
 limit 3
on conflict (id) do nothing;

insert into run_reactions (user_id, run_id, reaction, reacted_at)
select u.id, r.id, (array['fire', 'strong', 'trophy', 'thumbs_up', 'wave'])[1 + abs(hashtext(u.k || r.id::text)) % 5],
       least(now() - interval '4 minutes', r.started_at + r.duration_s * interval '1 second' + interval '1 hour')
  from runs r
  join demo_users u on pg_temp.rnd('react:' || u.k || r.id) < 0.15
 where r.user_id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890' and r.is_public
   and r.started_at > now() - interval '30 days'
   and r.id in (select id from demo_runner_runs)
on conflict do nothing;

insert into route_reviews (id, route_id, user_id, rating, comment, created_at, updated_at)
select pg_temp.did('review:' || r.id || ':' || u.k), r.id, u.id,
       3 + abs(hashtext(u.k || r.id::text)) % 3,
       (array['Great views, well worth the climb.', 'Nice and flat, perfect for tempo work.',
              'Busy on weekends, go early.', 'Some mud after rain, otherwise lovely.', null])[1 + abs(hashtext(r.id::text || u.k)) % 5],
       now() - u.idx * interval '3 days', now() - u.idx * interval '3 days'
  from demo_routes r
  join demo_users u on pg_temp.rnd('review:' || u.k || r.id) < 0.3
 where r.owner_k = 'runner' and r.is_public
on conflict do nothing;

-- ───────────────────────── 9. Clubs, events, posts ─────────────────────────

create temp table demo_clubs on commit drop as
select pg_temp.did('club:' || slug) as id, slug, name, owner_k, description, label, lat, lng, policy
  from (values
    ('cville-trail-runners', 'Charlottesville Trail Runners', 'priya',
     'Weekend trail long runs on the Rivanna Trail and in Shenandoah. All paces, nobody left behind.',
     'Charlottesville, VA', 38.0293, -78.4767, 'open'),
    ('tidewater-sunrise-runners', 'Tidewater Sunrise Runners', 'elena',
     'Sunrise miles on the Virginia Beach boardwalk, coffee after.', 'Virginia Beach, VA', 36.8529, -75.9780, 'open'),
    ('rva-yoga-mobility', 'RVA Yoga & Mobility for Runners', 'aisha',
     'Weekly yoga and mobility classes built for runners, plus the occasional social.', 'Richmond, VA', 37.5480, -77.4530, 'request')
  ) v(slug, name, owner_k, description, label, lat, lng, policy);

insert into clubs (id, owner_id, name, slug, description, location_label, location_point, is_public, join_policy)
select c.id, u.id, c.name, c.slug, c.description, c.label,
       extensions.st_setsrid(extensions.st_makepoint(c.lng, c.lat), 4326)::extensions.geography,
       true, c.policy
  from demo_clubs c join demo_users u on u.k = c.owner_k
on conflict (id) do nothing;

insert into club_members (club_id, user_id, role, status, joined_at)
select c.id, 'a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'member', 'active', now() - interval '50 days'
  from demo_clubs c
union all
select c.id, u.id, case when u.k = 'sam' and c.slug = 'rva-yoga-mobility' then 'admin' else 'member' end,
       case when u.k = 'tom' and c.slug = 'rva-yoga-mobility' then 'pending' else 'active' end,
       now() - u.idx * interval '6 days'
  from demo_clubs c
  join demo_users u on u.k <> c.owner_k
   and ((c.slug = 'cville-trail-runners' and u.k in ('diego', 'sam', 'tom'))
     or (c.slug = 'tidewater-sunrise-runners' and u.k in ('hannah', 'marcus'))
     or (c.slug = 'rva-yoga-mobility' and u.k in ('sam', 'marcus', 'hannah', 'tom')))
on conflict do nothing;

create temp table demo_events on commit drop as
select pg_temp.did('event:' || k) as id, k, club_slug, title, description, category, discipline,
       starts_at, duration_min, meet_label, lat, lng, distance_m, pace, capacity, freq, byday
  from (values
    ('ctr-saturday-long', 'cville-trail-runners', 'Saturday Trail Long Run',
     'Two groups: 15 km and 25 km on the Rivanna Trail. Bring water, there are no fountains.',
     'run', null, pg_temp.va(pg_temp.next_dow(6), interval '7 hours 30 minutes'), 150,
     'Riverview Park lot', 38.0270, -78.4600, 20000, 400, null, 'weekly', array['SA']),
    ('ctr-ragged-night', 'cville-trail-runners', 'Ragged Mountain Night Run',
     'Headlamps on. A slow social loop of the reservoir, then tacos.',
     'run', null, pg_temp.va(current_date + 9, interval '18 hours'), 90,
     'Ragged Mountain trailhead', 38.0230, -78.5520, 10500, 420, 25, null, null),
    ('tsr-boardwalk', 'tidewater-sunrise-runners', 'Sunrise Boardwalk 5 Miler',
     'Out to the fishing pier and back as the sun comes up.',
     'run', null, pg_temp.va(pg_temp.next_dow(2), interval '6 hours 15 minutes'), 60,
     'King Neptune statue, 31st Street', 36.8560, -75.9770, 8000, 330, null, 'weekly', array['TU']),
    ('tsr-shamrock-recon', 'tidewater-sunrise-runners', 'Shamrock Course Recon',
     'Easy run over the back half of the Shamrock course.',
     'run', null, pg_temp.va(current_date + 16, interval '7 hours'), 120,
     '19th Street and Atlantic Ave', 36.8480, -75.9760, 16000, 360, null, null, null),
    ('yoga-vinyasa', 'rva-yoga-mobility', 'Vinyasa for Runners',
     'An hour of flow focused on hips, hamstrings and calves. Mats provided.',
     'class', 'Yoga', pg_temp.va(pg_temp.next_dow(3), interval '18 hours 30 minutes'), 60,
     'Carytown studio', 37.5530, -77.4900, null, null, 20, 'weekly', array['WE']),
    ('yoga-mobility', 'rva-yoga-mobility', 'Foam Rolling & Mobility Clinic',
     'Learn a 15-minute post-run routine you can do at home.',
     'class', 'Mobility', pg_temp.va(current_date + 6, interval '10 hours'), 75,
     'Carytown studio', 37.5530, -77.4900, null, null, 15, null, null),
    ('yoga-social', 'rva-yoga-mobility', 'Post-Race Social at Hardywood',
     'Celebrate the Richmond Marathon weekend. Medals encouraged.',
     'social', null, pg_temp.va(current_date + 25, interval '16 hours'), 180,
     'Hardywood Park Craft Brewery', 37.5650, -77.4520, null, null, null, null, null)
  ) v(k, club_slug, title, description, category, discipline, starts_at, duration_min, meet_label,
      lat, lng, distance_m, pace, capacity, freq, byday);

insert into events (id, club_id, title, description, starts_at, duration_min, meet_lat, meet_lng, meet_label,
                    distance_m, pace_target_sec, capacity, author_id, category, discipline,
                    recurrence_freq, recurrence_byday, timezone, is_public)
select e.id, c.id, e.title, e.description, e.starts_at, e.duration_min, e.lat, e.lng, e.meet_label,
       e.distance_m, e.pace, e.capacity, u.id, e.category, e.discipline,
       e.freq, e.byday, 'America/New_York', true
  from demo_events e
  join demo_clubs c on c.slug = e.club_slug
  join demo_users u on u.k = c.owner_k
on conflict (id) do nothing;

insert into event_attendees (event_id, user_id, status, joined_at, instance_start)
select e.id, 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
       case when e.k in ('ctr-ragged-night', 'tsr-shamrock-recon') then 'maybe' else 'going' end,
       now() - interval '2 days', e.starts_at
  from demo_events e where e.k <> 'tsr-boardwalk'
union all
select e.id, u.id, case when u.idx % 3 = 0 then 'maybe' else 'going' end, now() - u.idx * interval '5 hours', e.starts_at
  from demo_events e
  join demo_clubs c on c.slug = e.club_slug
  join club_members m on m.club_id = c.id and m.status = 'active'
  join demo_users u on u.id = m.user_id
on conflict do nothing;

insert into club_posts (id, club_id, author_id, body, created_at)
select pg_temp.did('post:' || c.slug || ':' || p.n), c.id, coalesce(u.id, ow.id), p.body, now() - p.ago
  from demo_clubs c
  join demo_users ow on ow.k = c.owner_k
  join (values
    ('cville-trail-runners', 1, null, 'Trail report: the Rivanna crossing at Riverview is muddy after the rain. Bring a spare pair of socks.', interval '2 days'),
    ('cville-trail-runners', 2, 'diego', 'Anyone up for a Massanutten recon next month? Thinking 30 km with a car shuttle.', interval '5 days'),
    ('tidewater-sunrise-runners', 1, null, 'Sunrise is now 6:45, so we are pushing the start to 6:15 until spring.', interval '3 days'),
    ('tidewater-sunrise-runners', 2, 'hannah', 'Stroller crew is meeting at 30th Street, all welcome.', interval '9 days'),
    ('rva-yoga-mobility', 1, null, 'New Wednesday class is live. Bring a strap if you have one; we will have spares.', interval '1 day'),
    ('rva-yoga-mobility', 2, 'sam', 'The mobility clinic has 15 spots and is filling up. RSVP so we can plan.', interval '4 days')
  ) p(slug, n, author_k, body, ago) on p.slug = c.slug
  left join demo_users u on u.k = p.author_k
on conflict (id) do nothing;

-- ───────────────────────── 10. Challenges ─────────────────────────

create temp table demo_challenges on commit drop as
select pg_temp.did('challenge:' || k) as id, k, creator_k, club_slug, title, description, metric, scope,
       goal, activity, starts_at, ends_at, region
  from (values
    ('nov-100k', 'sam', null, 'This Month''s 100K', 'Run 100 km between the first and last day of the month.',
     'distance', 'individual', 100000, 'run',
     date_trunc('month', now()), date_trunc('month', now()) + interval '1 month', null),
    ('streak-14', 'hannah', null, 'Two-Week Streak', 'Move every day for 14 days. A 1 km walk counts.',
     'streak_days', 'individual', 14, null,
     date_trunc('day', now()) - interval '3 days', date_trunc('day', now()) + interval '11 days', null),
    ('va-parks-12', 'diego', null, 'Virginia Park Courses: 12 This Year', 'Complete 12 different park courses in Virginia this year.',
     'park_courses', 'individual', 12, null,
     date_trunc('year', now()), date_trunc('year', now()) + interval '1 year', 'US-VA'),
    ('vert-3000', 'priya', null, 'Vert Club: 3,000 m in 30 Days', 'Climb 3,000 m on foot in 30 days.',
     'vert', 'individual', 3000, null,
     date_trunc('day', now()) - interval '10 days', date_trunc('day', now()) + interval '20 days', null),
    ('ctr-1000k', 'priya', 'cville-trail-runners', 'Club Goal: 1,000 km This Month', 'Every kilometre the club runs this month counts.',
     'distance', 'group_goal', 1000000, null,
     date_trunc('month', now()), date_trunc('month', now()) + interval '1 month', null),
    ('dec-daily', 'elena', null, 'December Daily Activity', 'Log an activity on 25 days in December.',
     'activity_count', 'individual', 25, null,
     date_trunc('month', now()) + interval '1 month', date_trunc('month', now()) + interval '2 months', null)
  ) v(k, creator_k, club_slug, title, description, metric, scope, goal, activity, starts_at, ends_at, region);

insert into challenges (id, creator_id, club_id, title, description, metric, scope, goal_value, activity_type,
                        starts_at, ends_at, is_public, park_region_code, created_at)
select ch.id, u.id, c.id, ch.title, ch.description, ch.metric, ch.scope, ch.goal, ch.activity,
       ch.starts_at, ch.ends_at, true, ch.region, least(now(), ch.starts_at) - interval '5 days'
  from demo_challenges ch
  join demo_users u on u.k = ch.creator_k
  left join demo_clubs c on c.slug = ch.club_slug
on conflict (id) do nothing;

insert into challenge_participants (challenge_id, user_id, joined_at)
select ch.id, 'a1b2c3d4-e5f6-7890-abcd-ef1234567890', least(now(), ch.starts_at + interval '1 day')
  from demo_challenges ch where ch.k in ('nov-100k', 'va-parks-12', 'vert-3000', 'ctr-1000k')
union all
select ch.id, u.id, least(now(), ch.starts_at + u.idx * interval '6 hours')
  from demo_challenges ch
  join demo_users u on (ch.k = 'nov-100k' and u.k in ('sam', 'tom', 'aisha', 'hannah'))
                    or (ch.k = 'streak-14' and u.k in ('hannah', 'marcus', 'elena'))
                    or (ch.k = 'va-parks-12' and u.k in ('diego', 'priya', 'sam'))
                    or (ch.k = 'vert-3000' and u.k in ('priya', 'diego'))
                    or (ch.k = 'ctr-1000k' and u.k in ('priya', 'diego', 'sam', 'tom'))
                    or (ch.k = 'dec-daily' and u.k in ('elena'))
on conflict do nothing;

-- ───────────────────────── 11. Messages ─────────────────────────
-- Two direct threads. The conversation row is created by the send trigger.

insert into direct_messages (id, sender_id, recipient_id, body, created_at, read_at)
select pg_temp.did('dm:' || m.n), s.id, r.id, m.body, now() - m.ago,
       case when m.read then now() - m.ago + interval '10 minutes' end
  from (values
    (1, 'sam',    'runner', 'Are you doing the Richmond Half this year?', interval '3 days 4 hours', true),
    (2, 'runner', 'sam',    'Yes! Going for sub 1:40. You?', interval '3 days 3 hours', true),
    (3, 'sam',    'runner', 'Same goal. Want to do the long run on Saturday together?', interval '3 days 2 hours', true),
    (4, 'runner', 'sam',    'Deal. Belle Isle at 7?', interval '3 days 1 hour', true),
    (5, 'sam',    'runner', 'Perfect, see you there.', interval '2 days 20 hours', true),
    (6, 'sam',    'runner', 'Nice run today. That last 5K was quick!', interval '5 hours', false),
    (7, 'priya',  'runner', 'Saved you a spot on the Saturday trail run. 25 km group?', interval '1 day 6 hours', true),
    (8, 'runner', 'priya',  'Maybe the 15 this week, I have a tempo on Sunday.', interval '1 day 5 hours', true),
    (9, 'priya',  'runner', 'Fair. The 15 group leaves at 7:30 from Riverview.', interval '50 minutes', false)
  ) m(n, sender_k, recipient_k, body, ago, read)
  join (select k, id from demo_users union all select 'runner', 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'::uuid) s on s.k = m.sender_k
  join (select k, id from demo_users union all select 'runner', 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'::uuid) r on r.k = m.recipient_k
 order by m.n
on conflict (id) do nothing;

-- ───────────────────────── 12. Training ─────────────────────────
-- seed.sql already gives the runner the active Richmond Half plan; the demo
-- runs above land on its past days and the matcher links them. This adds the
-- 10K block finished before it, so plan history has a completed plan.

insert into training_plans (id, user_id, name, goal_event, goal_distance_m, goal_time_seconds,
                            start_date, end_date, days_per_week, vdot, current_5k_seconds, status, source, notes)
values (pg_temp.did('plan:fall-10k'), 'a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Fall 10K Build',
        'distance_10k', 10000, 2640, current_date - 79, current_date - 24, 4, 47.5, 1290, 'completed',
        'generated', 'Eight weeks of speed before the half block.')
on conflict (id) do nothing;

insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m)
select pg_temp.did('plan:fall-10k:week:' || w), pg_temp.did('plan:fall-10k'), w,
       (case when w < 3 then 'base' when w < 6 then 'build' when w < 7 then 'peak' else 'taper' end)::plan_phase,
       28000 + w * 3000 - case when w = 7 then 12000 else 0 end
  from generate_series(0, 7) w
on conflict (id) do nothing;

insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m, target_pace_sec_per_km, notes,
                           race_name, race_priority)
select pg_temp.did('plan:fall-10k:workout:' || w || ':' || s.slot), pg_temp.did('plan:fall-10k:week:' || w),
       current_date - 79 + w * 7 + s.dayoff,
       (case when w = 7 and s.slot = 3 then 'race' else s.kind end)::workout_kind,
       case when w = 7 and s.slot = 3 then 10000 else s.dist + w * 500 end,
       case when w = 7 and s.slot = 3 then 264 else s.pace end,
       case when s.kind = 'interval' then '6 x 800 m at 5K pace, 2 min jog between.' end,
       case when w = 7 and s.slot = 3 then 'Monument Avenue 10K' end,
       case when w = 7 and s.slot = 3 then 'A' end
  from generate_series(0, 7) w
  cross join (values (0, 1, 'easy', 6000, 335), (1, 2, 'interval', 7000, 262),
                     (2, 4, 'tempo', 8000, 285), (3, 6, 'long', 12000, 345)) s(slot, dayoff, kind, dist, pace)
on conflict (id) do nothing;

-- ───────────────────────── 13. Gym, food, body, fitness ─────────────────────────

insert into gym_routines (id, author_id, title, notes, periodisation, exercise_count)
values
  (pg_temp.did('routine:a'), 'a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Runner''s Strength A',
   'Lower body and posterior chain. Twice a week in base, once in build.', 'linear', 4),
  (pg_temp.did('routine:b'), 'a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Runner''s Strength B',
   'Single-leg work and core.', 'none', 4)
on conflict (id) do nothing;

insert into gym_routine_exercises (id, routine_id, exercise_name, position, modality, progression)
select pg_temp.did('routine:' || r || ':ex:' || p), pg_temp.did('routine:' || r), name, p, modality, prog
  from (values
    ('a', 0, 'Back Squat', 'weight_reps', 'linear'),
    ('a', 1, 'Romanian Deadlift', 'weight_reps', 'linear'),
    ('a', 2, 'Walking Lunge', 'weight_reps', 'double_progression'),
    ('a', 3, 'Calf Raise', 'weight_reps', 'none'),
    ('b', 0, 'Bulgarian Split Squat', 'weight_reps', 'double_progression'),
    ('b', 1, 'Single-Leg Glute Bridge', 'bodyweight_reps', 'none'),
    ('b', 2, 'Plank', 'time', 'none'),
    ('b', 3, 'Side Plank', 'time', 'none')
  ) v(r, p, name, modality, prog)
on conflict (id) do nothing;

insert into gym_routine_sets (id, routine_exercise_id, set_index, set_type, target_reps_min, target_reps_max,
                              target_weight_kg, rest_s, target_duration_s)
select pg_temp.did('routine:' || v.r || ':ex:' || v.p || ':set:' || s), pg_temp.did('routine:' || v.r || ':ex:' || v.p),
       s, case when s = 0 and v.kg is not null then 'warmup' else 'working' end,
       v.reps_min, v.reps_max,
       case when v.kg is not null then case when s = 0 then round(v.kg * 0.6) else v.kg end end,
       v.rest, v.secs
  from (values
    ('a', 0, 5, 8, 70.0, 120, null), ('a', 1, 6, 10, 60.0, 120, null), ('a', 2, 10, 12, 16.0, 90, null),
    ('a', 3, 12, 15, 40.0, 60, null), ('b', 0, 8, 10, 14.0, 90, null), ('b', 1, 12, 15, null, 60, null),
    ('b', 2, null, null, null, 45, 60), ('b', 3, null, null, null, 45, 40)
  ) v(r, p, reps_min, reps_max, kg, rest, secs)
  cross join generate_series(0, 2) s
on conflict (id) do nothing;

insert into gym_workouts (id, user_id, title, started_at, duration_s, notes, is_public)
select pg_temp.did('gym:' || w), 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
       case when w % 2 = 0 then 'Runner''s Strength A' else 'Runner''s Strength B' end,
       pg_temp.va(current_date - (8 + w * 4), interval '18 hours'), 2700 + (w % 3) * 300,
       case when w = 0 then 'Squat felt smooth, add 2.5 kg next time.' end, w % 3 = 0
  from generate_series(0, 11) w
on conflict (id) do nothing;

insert into gym_sets (id, workout_id, set_index, exercise_name, reps, weight_kg, rpe, duration_s, set_type)
select pg_temp.did('gym:' || w || ':set:' || (e.p * 3 + s)), pg_temp.did('gym:' || w),
       e.p * 3 + s, e.name,
       case when e.secs is null then e.reps end,
       case when e.kg is not null then e.kg + (11 - w) * e.step end,
       case when s = 2 then 8 else 7 end,
       e.secs, 'working'
  from generate_series(0, 11) w
  join (values
    (0, 0, 'Back Squat', 6, 62.5, 1.25, null), (0, 1, 'Romanian Deadlift', 8, 55.0, 1.0, null),
    (0, 2, 'Walking Lunge', 10, 14.0, 0.5, null), (0, 3, 'Calf Raise', 12, 40.0, 0.0, null),
    (1, 0, 'Bulgarian Split Squat', 8, 12.0, 0.5, null), (1, 1, 'Single-Leg Glute Bridge', 12, null, 0.0, null),
    (1, 2, 'Plank', null, null, 0.0, 60), (1, 3, 'Side Plank', null, null, 0.0, 40)
  ) e(parity, p, name, reps, kg, step, secs) on e.parity = w % 2
  cross join generate_series(0, 2) s
on conflict (id) do nothing;

-- Food: three weeks before seed.sql's own last seven days. The runner has
-- health-data consent, which the food_log gate requires.
insert into food_log (id, user_id, started_at, item_name, meal_slot, calories, protein_g, carbs_g, fat_g, fiber_g)
select pg_temp.did('food:' || d || ':' || m.n), 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
       pg_temp.va(current_date - d, m.at),
       case when m.n = 2 then (array['Chicken burrito bowl', 'Turkey sandwich and an apple', 'Lentil soup and sourdough'])[1 + d % 3]
            when m.n = 4 then (array['Salmon, rice and roasted broccoli', 'Pasta with turkey meatballs', 'Black bean tacos'])[1 + d % 3]
            else m.item end,
       m.slot,
       round(m.kcal * (0.9 + 0.2 * pg_temp.rnd('food:' || d || m.n))), m.p, m.c, m.f, m.fib
  from generate_series(7, 27) d
  cross join (values
    (1, interval '7 hours 15 minutes', 'Oatmeal with banana and peanut butter', 'breakfast', 480, 16, 72, 15, 9),
    (2, interval '12 hours 30 minutes', 'Lunch', 'lunch', 690, 42, 78, 20, 12),
    (3, interval '15 hours 30 minutes', 'Greek yogurt with granola', 'snack', 260, 18, 32, 6, 2),
    (4, interval '19 hours', 'Dinner', 'dinner', 720, 45, 70, 26, 7)
  ) m(n, at, item, slot, kcal, p, c, f, fib)
 where not (m.n = 3 and d % 3 = 0)
on conflict (id) do nothing;

insert into body_metrics (id, user_id, recorded_at, weight_kg)
select pg_temp.did('weight:' || w), 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
       pg_temp.va(current_date - (28 + w * 7), interval '6 hours 45 minutes'),
       round((74.6 + w * 0.09 + (pg_temp.rnd('weight:' || w) - 0.5) * 0.8)::numeric, 1)
  from generate_series(0, 22) w
on conflict (id) do nothing;

insert into fitness_snapshots (id, user_id, computed_at, vdot, vo2_max, acute_load, chronic_load,
                               training_stress_bal, qualifying_run_count, source, notes)
select pg_temp.did('fitness:' || w), 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
       now() - (w * 7 + 3) * interval '1 day',
       round((50.2 - w * 0.12)::numeric, 1), round((52.0 - w * 0.12)::numeric, 1),
       round((58 + 10 * sin(w))::numeric, 1), round((54 - w * 0.6)::numeric, 1),
       round((54 - w * 0.6 - (58 + 10 * sin(w)))::numeric, 1),
       12 + (25 - w), 'server', null
  from generate_series(1, 25) w
on conflict (id) do nothing;

-- ───────────────────────── 14. Notifications ─────────────────────────
-- The triggers above raised the runner's kudos, comment, follow, message,
-- RSVP and run-completed notices at insert time. Give each its source's time
-- and mark everything older than two days read, so the inbox has a realistic
-- mix of read and unread. Only notifications a demo user caused are touched.

update notifications n set created_at = k.given_at
  from run_kudos k
 where n.kind = 'kudos' and n.run_id = k.run_id and n.actor_id = k.user_id
   and n.actor_id in (select id from demo_users) and n.created_at > k.given_at;

update notifications n set created_at = c.created_at
  from run_comments c
 where n.kind in ('comment', 'comment_reply') and n.comment_id = c.id
   and n.actor_id in (select id from demo_users) and n.created_at > c.created_at;

update notifications n set created_at = r.reacted_at
  from run_reactions r
 where n.kind = 'reaction' and n.run_id = r.run_id and n.actor_id = r.user_id
   and n.actor_id in (select id from demo_users) and n.created_at > r.reacted_at;

update notifications n set created_at = f.followed_at
  from user_follows f
 where n.kind = 'follow' and n.actor_id = f.follower_id and n.user_id = f.followee_id
   and n.actor_id in (select id from demo_users) and n.created_at > f.followed_at;

update notifications n set created_at = r.started_at + r.duration_s * interval '1 second'
  from runs r
 where n.kind = 'run_completed' and n.run_id = r.id
   and n.actor_id in (select id from demo_users)
   and n.created_at > r.started_at + r.duration_s * interval '1 second';

update notifications n set read_at = n.created_at + interval '3 hours'
 where n.user_id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
   and n.actor_id in (select id from demo_users)
   and n.read_at is null and n.created_at < now() - interval '2 days';

-- Each of those notifications also queued its email (and, with a device,
-- push) delivery job. A real notice that old went out long ago, and a local
-- job worker draining hundreds of them into Mailpit is noise, so drop the
-- delivery jobs of every notification a demo user caused or received.
delete from jobs j
 using notifications n
 where j.kind in ('notification_email', 'native_push', 'web_push')
   and j.status = 'queued'
   and j.payload->>'notification_id' = n.id::text
   and (n.actor_id in (select id from demo_users) or n.user_id in (select id from demo_users));

commit;

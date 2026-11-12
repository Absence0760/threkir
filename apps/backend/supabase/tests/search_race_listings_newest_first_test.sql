-- search_race_listings' `p_newest_first` (migration 20270904000001,
-- decisions § 2083). The calendar's "Recent" view asks for a past window
-- newest first; the cap must then keep the most recent races, not the oldest,
-- and the default order must be unchanged for every existing caller.

begin;

select plan(5);

set local role service_role;
insert into race_listings (id, provider, name, race_date, distance_m, is_verified)
values
  ('11111111-1111-1111-1111-1111000ee001', 'manual', 'Zqn Recent One', current_date - 20, 10000, true),
  ('11111111-1111-1111-1111-1111000ee002', 'manual', 'Zqn Recent Two', current_date - 10, 10000, true),
  ('11111111-1111-1111-1111-1111000ee003', 'manual', 'Zqn Recent Three', current_date - 2, 10000, true),
  ('11111111-1111-1111-1111-1111000ee004', 'manual', 'Zqn Upcoming', current_date + 5, 10000, true);

set local role anon;

select is(
  (select array_agg(name) from search_race_listings(
     p_query => 'Zqn', p_from => current_date - 30, p_to => current_date - 1,
     p_newest_first => true)),
  array['Zqn Recent Three', 'Zqn Recent Two', 'Zqn Recent One'],
  'newest first sorts a past window by date descending'
);

select is(
  (select array_agg(name) from search_race_listings(
     p_query => 'Zqn', p_from => current_date - 30, p_to => current_date - 1,
     p_newest_first => true, p_limit => 1)),
  array['Zqn Recent Three'],
  'the cap keeps the most recent race, not the oldest'
);

select is(
  (select array_agg(name) from search_race_listings(
     p_query => 'Zqn', p_from => current_date - 30, p_to => current_date - 1)),
  array['Zqn Recent One', 'Zqn Recent Two', 'Zqn Recent Three'],
  'the default order is unchanged: soonest (oldest) first'
);

select is(
  (select array_agg(name) from search_race_listings(p_query => 'Zqn')),
  array['Zqn Upcoming'],
  'with no window the calendar still lists only races from today on'
);

select is(
  (select count(*)::int from pg_proc where proname = 'search_race_listings'),
  1,
  'one signature only, so PostgREST can resolve the call'
);

select * from finish();

rollback;

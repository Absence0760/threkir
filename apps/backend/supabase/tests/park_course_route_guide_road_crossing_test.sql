-- park_courses.route_guide's road crossing (migration 20280105001344, issue
-- #1344): `{ kind: 'crossing', at_m, crossing: 'road', name?, signal? }`, a
-- motor road the course crosses at grade. The shape CHECK
-- (private.park_course_route_guide_ok) accepts it named or not, with or
-- without a signal, keeps bridges and fords to their old fields, and refuses
-- a signal that is not `true`.

begin;

select plan(6);

select ok(
  private.park_course_route_guide_ok('{"version": 1, "lang": "en", "steps": [
    {"kind": "start", "at_m": 0, "name": "Washington and Old Dominion Trail"},
    {"kind": "crossing", "at_m": 820, "crossing": "road", "name": "Hunter Mill Road", "signal": true},
    {"kind": "crossing", "at_m": 2400, "crossing": "road", "name": "Sunset Hills Road"},
    {"kind": "crossing", "at_m": 3100, "crossing": "road"},
    {"kind": "finish", "at_m": 5000}]}'::jsonb),
  'a road crossing, named or not, with or without a signal, passes'
);

select ok(
  private.park_course_route_guide_ok('{"version": 1, "lang": "en", "steps": [
    {"kind": "start", "at_m": 0, "way": "path"},
    {"kind": "crossing", "at_m": 10, "crossing": "bridge"},
    {"kind": "finish", "at_m": 100}]}'::jsonb),
  'a bridge crossing as before still passes'
);

select ok(
  not private.park_course_route_guide_ok('{"version": 1, "lang": "en", "steps": [
    {"kind": "start", "at_m": 0, "way": "path"},
    {"kind": "crossing", "at_m": 10, "crossing": "bridge", "name": "Mill Bridge"},
    {"kind": "finish", "at_m": 100}]}'::jsonb),
  'a bridge crossing with a name fails'
);

select ok(
  not private.park_course_route_guide_ok('{"version": 1, "lang": "en", "steps": [
    {"kind": "start", "at_m": 0, "way": "path"},
    {"kind": "crossing", "at_m": 10, "crossing": "ford", "signal": true},
    {"kind": "finish", "at_m": 100}]}'::jsonb),
  'a ford crossing with a signal fails'
);

select ok(
  not private.park_course_route_guide_ok('{"version": 1, "lang": "en", "steps": [
    {"kind": "start", "at_m": 0, "way": "path"},
    {"kind": "crossing", "at_m": 10, "crossing": "road", "signal": false},
    {"kind": "finish", "at_m": 100}]}'::jsonb),
  'a road crossing whose signal is false fails'
);

select ok(
  not private.park_course_route_guide_ok('{"version": 1, "lang": "en", "steps": [
    {"kind": "start", "at_m": 0, "way": "path"},
    {"kind": "crossing", "at_m": 10, "crossing": "road", "name": " "},
    {"kind": "finish", "at_m": 100}]}'::jsonb),
  'a road crossing with a blank name fails'
);

select * from finish();
rollback;

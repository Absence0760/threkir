-- park_courses.route_guide's road step (migration 20280102001430, issue
-- #1430): `{ kind: 'road', at_m, length_m, name? }`, the stretch of road a
-- course follows between two pieces of trail. The shape CHECK
-- (private.park_course_route_guide_ok) accepts it with a whole length and an
-- optional name, and refuses any other field or a length it could not hold.

begin;

select plan(5);

select ok(
  private.park_course_route_guide_ok('{"version": 1, "lang": "en", "steps": [
    {"kind": "start", "at_m": 0, "name": "Main Trail"},
    {"kind": "junction", "at_m": 556, "turn": "straight", "name": "Anderson Wright Drive"},
    {"kind": "road", "at_m": 556, "length_m": 56, "name": "Anderson Wright Drive"},
    {"kind": "road", "at_m": 1475, "length_m": 219},
    {"kind": "finish", "at_m": 5000}]}'::jsonb),
  'a road step with a whole length, named or not, passes'
);

select ok(
  not private.park_course_route_guide_ok('{"version": 1, "lang": "en", "steps": [
    {"kind": "start", "at_m": 0, "way": "path"},
    {"kind": "road", "at_m": 10, "length_m": 0},
    {"kind": "finish", "at_m": 100}]}'::jsonb),
  'a road step of 0 m fails'
);

select ok(
  not private.park_course_route_guide_ok('{"version": 1, "lang": "en", "steps": [
    {"kind": "start", "at_m": 0, "way": "path"},
    {"kind": "road", "at_m": 10, "length_m": 12.5},
    {"kind": "finish", "at_m": 100}]}'::jsonb),
  'a road step with a fractional length fails'
);

select ok(
  not private.park_course_route_guide_ok('{"version": 1, "lang": "en", "steps": [
    {"kind": "start", "at_m": 0, "way": "path"},
    {"kind": "road", "at_m": 10},
    {"kind": "finish", "at_m": 100}]}'::jsonb),
  'a road step with no length fails'
);

select ok(
  not private.park_course_route_guide_ok('{"version": 1, "lang": "en", "steps": [
    {"kind": "start", "at_m": 0, "way": "path"},
    {"kind": "road", "at_m": 10, "length_m": 40, "way": "road"},
    {"kind": "finish", "at_m": 100}]}'::jsonb),
  'a road step with a field outside its kind fails'
);

select * from finish();
rollback;

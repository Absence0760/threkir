-- The job_worker's smoothed-position sidecar, `{user_id}/{run_id}.smoothed.json.gz`
-- in the `runs` bucket (docs/features/gps_distance.md § Waypoint fields),
-- needs no policy of its own: the bucket's per-folder owner policies
-- (20260410_001, wrapped in 20270416_001) already cover it, and the worker
-- writes as the service role. This pins that coverage by behaviour rather
-- than by policy text: the owner reads it, another signed-in user and anon do
-- not. A non-owner sees the smoothed positions only through clip-public-track,
-- which merges them before the privacy-zone clip.

begin;
select plan(4);

insert into storage.objects (bucket_id, name) values
  ('runs', 'ae000000-0000-0000-0000-0000000000c1/ae000003-0000-0000-0000-000000000001.smoothed.json.gz');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"ae000000-0000-0000-0000-0000000000c1","role":"authenticated"}';
select is(
  (select count(*)::int from storage.objects
    where bucket_id = 'runs' and name like '%.smoothed.json.gz'),
  1, 'the owner can read their own run''s smoothed sidecar');

set local "request.jwt.claims" = '{"sub":"ae000000-0000-0000-0000-0000000000c2","role":"authenticated"}';
select is(
  (select count(*)::int from storage.objects
    where bucket_id = 'runs' and name like '%.smoothed.json.gz'),
  0, 'another signed-in user cannot read it');

reset role;
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
select is(
  (select count(*)::int from storage.objects
    where bucket_id = 'runs' and name like '%.smoothed.json.gz'),
  0, 'anon cannot read it');

reset role;
select is(
  (select public from storage.buckets where id = 'runs'),
  false, 'the runs bucket stays private, so no CDN path bypasses the folder policy');

select * from finish();
rollback;

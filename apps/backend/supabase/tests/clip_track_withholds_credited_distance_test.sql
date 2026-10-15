-- pgtap suite for clip_track_for_user withholding each point's credited
-- distance (`distM`) from its non-owner output
-- (20270829000021_clip_track_withholds_credited_distance).
--
-- `distM` is the run's distance credited up to and including a fix
-- (docs/features/gps_distance.md § Waypoint fields). Served on the first
-- point after a trimmed start zone, it states how far the runner went inside
-- that zone; served on the last point before a trimmed end zone, it states the
-- same for the end, via the run's public `distance_m`. Every caller of the
-- clip serves a non-owner, so the key is removed on every path.

begin;

select plan(7);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000d501', 'authenticated', 'authenticated',
   'zoned@distm.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000d502', 'authenticated', 'authenticated',
   'nozones@distm.local', '', now(), now());

-- ~150 m zone around (47.37, 8.54); 8.5550 and further east are outside it.
insert into user_settings (user_id, prefs)
values (
  '00000000-0000-0000-0000-00000000d501',
  jsonb_build_object(
    'privacy_zones', jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.54, 'radius_m', 150)
    )
  )
);

-- 1. A start zone: the in-zone head is trimmed and the first served point
--    carries no distM (it used to carry 420, the distance run in the zone).
select is(
  clip_track_for_user(
    '00000000-0000-0000-0000-00000000d501',
    jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.5400, 'distM', 0),
      jsonb_build_object('lat', 47.37, 'lng', 8.5405, 'distM', 40),
      jsonb_build_object('lat', 47.37, 'lng', 8.5550, 'distM', 420, 'bpm', 140),
      jsonb_build_object('lat', 47.37, 'lng', 8.5600, 'distM', 800, 'bpm', 150)
    )
  ),
  jsonb_build_array(
    jsonb_build_object('lat', 47.37, 'lng', 8.5550, 'bpm', 140),
    jsonb_build_object('lat', 47.37, 'lng', 8.5600, 'bpm', 150)
  ),
  'a start-zone clip serves no distM, and keeps every other field'
);

-- 2. An end zone: the last served point carries no distM either, so the gap
--    to distance_m does not state the distance run inside the end zone.
select is(
  clip_track_for_user(
    '00000000-0000-0000-0000-00000000d501',
    jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.5600, 'distM', 0),
      jsonb_build_object('lat', 47.37, 'lng', 8.5550, 'distM', 380),
      jsonb_build_object('lat', 47.37, 'lng', 8.5405, 'distM', 1490),
      jsonb_build_object('lat', 47.37, 'lng', 8.5400, 'distM', 1530)
    )
  ),
  jsonb_build_array(
    jsonb_build_object('lat', 47.37, 'lng', 8.5600),
    jsonb_build_object('lat', 47.37, 'lng', 8.5550)
  ),
  'an end-zone clip serves no distM on the last visible point'
);

-- 3. A zone passed through mid-run: the interior is served (the clip trims
--    only the ends), and no point on either side of it carries distM.
select is(
  clip_track_for_user(
    '00000000-0000-0000-0000-00000000d501',
    jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.5600, 'distM', 0),
      jsonb_build_object('lat', 47.37, 'lng', 8.5400, 'distM', 1510),
      jsonb_build_object('lat', 47.37, 'lng', 8.5200, 'distM', 3020)
    )
  ),
  jsonb_build_array(
    jsonb_build_object('lat', 47.37, 'lng', 8.5600),
    jsonb_build_object('lat', 47.37, 'lng', 8.5400),
    jsonb_build_object('lat', 47.37, 'lng', 8.5200)
  ),
  'a mid-run zone pass serves no distM on any point'
);

-- 4. No zones configured: the track is served whole but without distM, so
--    the key's presence never tells a viewer whether the owner has a zone.
select is(
  clip_track_for_user(
    '00000000-0000-0000-0000-00000000d502',
    jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.5400, 'distM', 0, 'baroEle', 410.5),
      jsonb_build_object('lat', 47.37, 'lng', 8.5600, 'distM', 1510, 'baroEle', 412.0)
    )
  ),
  jsonb_build_array(
    jsonb_build_object('lat', 47.37, 'lng', 8.5400, 'baroEle', 410.5),
    jsonb_build_object('lat', 47.37, 'lng', 8.5600, 'baroEle', 412.0)
  ),
  'the no-zones path serves no distM either'
);

-- 5. A non-object interior element passes through as it always did.
select is(
  clip_track_for_user(
    '00000000-0000-0000-0000-00000000d502',
    jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.5600, 'distM', 0),
      'null'::jsonb,
      jsonb_build_object('lat', 47.37, 'lng', 8.5650, 'distM', 380)
    )
  ),
  jsonb_build_array(
    jsonb_build_object('lat', 47.37, 'lng', 8.5600),
    'null'::jsonb,
    jsonb_build_object('lat', 47.37, 'lng', 8.5650)
  ),
  'a non-object element is served unchanged'
);

-- 6. A track wholly inside the zone is still empty.
select is(
  clip_track_for_user(
    '00000000-0000-0000-0000-00000000d501',
    jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.5400, 'distM', 0),
      jsonb_build_object('lat', 47.37, 'lng', 8.5405, 'distM', 40)
    )
  ),
  '[]'::jsonb,
  'a track wholly inside a zone is still served empty'
);

-- 7. No served point of any shape carries the key.
select is(
  (clip_track_for_user(
    '00000000-0000-0000-0000-00000000d501',
    jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.5400, 'distM', 0),
      jsonb_build_object('smoothedLat', 47.37, 'smoothedLng', 8.5550, 'distM', 410),
      jsonb_build_object('lat', 47.37, 'lng', 8.5600, 'ts', '2026-10-15T07:00:00Z', 'distM', 800)
    )
  )::text ~ 'distM'),
  false,
  'clip_track_for_user output never carries distM'
);

select * from finish();
rollback;

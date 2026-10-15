-- pgtap suite for clip_track_for_user serving a non-owner no off-track fix
-- (20270829000032_clip_track_drops_off_track_fixes).
--
-- An off-track fix (`offTrack: true`) is one the recorder's distance
-- estimator took that failed its track gate (docs/features/gps_distance.md
-- § Waypoint fields). It is distance input, never line: the clip drops it
-- before the zone walk, so one inside a zone is not served, one outside a
-- zone is not served either, and one sitting outside a zone cannot end the
-- walk early and leave in-zone fixes on the served line.

begin;

select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000d601', 'authenticated', 'authenticated',
   'zoned@offtrack.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000d602', 'authenticated', 'authenticated',
   'nozones@offtrack.local', '', now(), now());

-- ~150 m zone around (47.37, 8.54); 8.5550 and further east are outside it.
insert into user_settings (user_id, prefs)
values (
  '00000000-0000-0000-0000-00000000d601',
  jsonb_build_object(
    'privacy_zones', jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.54, 'radius_m', 150)
    )
  )
);

-- 1. An off-track fix outside the zone between two in-zone fixes does not end
--    the start walk: the in-zone on-track fix after it is still trimmed, and
--    neither off-track fix is served.
select is(
  clip_track_for_user(
    '00000000-0000-0000-0000-00000000d601',
    jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.5400),
      jsonb_build_object('lat', 47.37, 'lng', 8.5550, 'offTrack', true),
      jsonb_build_object('lat', 47.37, 'lng', 8.5405),
      jsonb_build_object('lat', 47.37, 'lng', 8.5600),
      jsonb_build_object('lat', 47.37, 'lng', 8.5650, 'offTrack', true),
      jsonb_build_object('lat', 47.37, 'lng', 8.5700)
    )
  ),
  jsonb_build_array(
    jsonb_build_object('lat', 47.37, 'lng', 8.5600),
    jsonb_build_object('lat', 47.37, 'lng', 8.5700)
  ),
  'an off-track fix outside a zone neither ends the walk nor is served'
);

-- 2. An off-track fix inside a zone passed mid-run is dropped, while the
--    on-track interior the clip has always served stays.
select is(
  clip_track_for_user(
    '00000000-0000-0000-0000-00000000d601',
    jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.5600),
      jsonb_build_object('lat', 47.37, 'lng', 8.5402, 'offTrack', true),
      jsonb_build_object('lat', 47.37, 'lng', 8.5400),
      jsonb_build_object('lat', 47.37, 'lng', 8.5200)
    )
  ),
  jsonb_build_array(
    jsonb_build_object('lat', 47.37, 'lng', 8.5600),
    jsonb_build_object('lat', 47.37, 'lng', 8.5400),
    jsonb_build_object('lat', 47.37, 'lng', 8.5200)
  ),
  'an off-track fix inside a zone is never served'
);

-- 3. No zones configured: off-track fixes are dropped all the same, and
--    `offTrack: false` is an on-track fix, served as stored (minus distM).
select is(
  clip_track_for_user(
    '00000000-0000-0000-0000-00000000d602',
    jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.5400, 'distM', 0),
      jsonb_build_object('lat', 47.37, 'lng', 8.5450, 'distM', 380, 'offTrack', true),
      jsonb_build_object('lat', 47.37, 'lng', 8.5500, 'distM', 760, 'offTrack', false)
    )
  ),
  jsonb_build_array(
    jsonb_build_object('lat', 47.37, 'lng', 8.5400),
    jsonb_build_object('lat', 47.37, 'lng', 8.5500, 'offTrack', false)
  ),
  'the no-zones path drops off-track fixes and keeps offTrack false'
);

-- 4. A track of nothing but off-track fixes serves nothing.
select is(
  clip_track_for_user(
    '00000000-0000-0000-0000-00000000d602',
    jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.5600, 'offTrack', true),
      jsonb_build_object('lat', 47.37, 'lng', 8.5650, 'offTrack', true)
    )
  ),
  '[]'::jsonb,
  'an all-off-track track is served empty'
);

-- 5. Non-object elements still pass through unchanged.
select is(
  clip_track_for_user(
    '00000000-0000-0000-0000-00000000d602',
    jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.5600),
      'null'::jsonb,
      jsonb_build_object('lat', 47.37, 'lng', 8.5625, 'offTrack', true),
      jsonb_build_object('lat', 47.37, 'lng', 8.5650)
    )
  ),
  jsonb_build_array(
    jsonb_build_object('lat', 47.37, 'lng', 8.5600),
    'null'::jsonb,
    jsonb_build_object('lat', 47.37, 'lng', 8.5650)
  ),
  'a non-object element is served unchanged beside a dropped off-track fix'
);

-- 6. No served point carries offTrack true, whatever the zone walk does.
select is(
  (clip_track_for_user(
    '00000000-0000-0000-0000-00000000d601',
    jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.5600, 'offTrack', true),
      jsonb_build_object('smoothedLat', 47.37, 'smoothedLng', 8.5650),
      jsonb_build_object('lat', 47.37, 'lng', 8.5700, 'offTrack', true),
      jsonb_build_object('lat', 47.37, 'lng', 8.5750)
    )
  )::text ~ 'offTrack'),
  false,
  'clip_track_for_user output never carries an off-track fix'
);

select * from finish();
rollback;

-- NYC Marathon bridges as catalogue segments (issue #1274).
--
-- The NYC Marathon recap asks runners to "see what the bridges cost you".
-- Their grade-adjusted splits already come from their own trace; this adds
-- the five bridges and the Fifth Avenue climb to the global_segments
-- catalogue (20270411_001), so a run of the course matches each one and
-- earns a time on its leaderboard.
--
-- Data, not schema. Curated catalogue rows ship in a migration for the same
-- reason the exercise catalogue does (20270222_001): every environment gets
-- the same rows, reviewed in a PR, instead of hand-entered in Studio. The
-- fixed ids make the insert a no-op where a row already exists, so a re-run
-- changes nothing. Pulling a bad entry later is
-- `update global_segments set is_active = false where id = ...`, which keeps
-- the efforts athletes earned on it.
--
-- Geometry source: OpenStreetMap, (c) OpenStreetMap contributors, licensed
-- under the ODbL 1.0 (https://www.openstreetmap.org/copyright), read through
-- the Overpass API on 2026-11-03. Each line is the chain of OSM ways the road
-- named after the bridge is mapped as, in the direction the race runs, joined
-- end to end (every join is a shared OSM node). The attribution is repeated
-- in each row's description, which is what the segment page shows.
--
--   Verrazzano-Narrows Bridge  way 46858873 (upper level, eastbound). The
--       lower level runs directly beneath, about 15 m away horizontally,
--       inside the matcher's 35 m end tolerance, so one line serves both
--       decks the race uses.
--   Pulaski Bridge             ways 68523762, 968706245, 46717584, 799503342,
--       25355824, 1320224833, 221608280 (northbound, Brooklyn to Queens).
--   Queensboro Bridge          ways 46372178, 32947290, 198924625, 198595507
--       (westbound lower level, Queens to First Avenue, Manhattan).
--   Willis Avenue Bridge       ways 933665956, 32965216, 949990384, 5670524,
--       799505597, 788253907, 587061861, 5698215, 788253913, 421844232,
--       46626580 (northbound, Manhattan to the Bronx).
--   Madison Avenue Bridge      ways 33117596, 46625537, 799505599, 799505600,
--       68668518, 421844230, 421844231, 33117594 (westbound, the Bronx to
--       Manhattan).
--   Fifth Avenue climb         ways 840996403, 195743338, 993517671,
--       195743332, 1378258842, 1378258841, 587061863, 195743334, 440122865
--       (southbound), from node 42432352 at East 110th Street to node
--       42444809 at East 90th Street, where the course enters Central Park.
--
-- distance_m is the haversine length of each line on the 6371 km sphere the
-- matcher uses (computeGlobalSegmentEffort accepts a covered distance within
-- 25% of it). elevation_m is null on the five bridges on purpose: public
-- elevation models are bare earth, so they read the water under a deck, not
-- the deck, and would report a climb that is wrong. The Fifth Avenue climb is
-- on the ground, so its points carry elevations from the USGS 3DEP 1 m model
-- (Elevation Point Query Service, public domain), and elevation_m is their
-- summed rise, 29 m.
--
-- Not yet checked: the match rate on real 2026 traces, especially on the
-- Queensboro lower level and the Verrazzano lower deck, where GPS is poor.
-- Issue #1274 keeps that as a step before the release that ships this.
--
-- Locks: a plain INSERT into a small catalogue table. No DDL.

insert into public.global_segments
  (id, name, description, waypoints, distance_m, elevation_m, surface, region, country_code)
values
  ('00000000-0000-4000-8000-0000000c0127',
   'Verrazzano-Narrows Bridge (NYC Marathon)',
   'Staten Island to Brooklyn across the Verrazzano-Narrows Bridge, the first two miles of the TCS New York City Marathon. Runners use both decks, which sit one above the other, so one line serves both. Geometry from OpenStreetMap (c) OpenStreetMap contributors, ODbL 1.0.',
   '[{"lat":40.602741,"lng":-74.056403},{"lat":40.604319,"lng":-74.051531},{"lat":40.609859,"lng":-74.034367}]',
   2022, null, 'road', 'New York, NY', 'US'),
  ('00000000-0000-4000-8000-0000000c0128',
   'Pulaski Bridge (NYC Marathon)',
   'Greenpoint, Brooklyn to Long Island City, Queens over Newtown Creek, near the halfway mark of the TCS New York City Marathon. Geometry from OpenStreetMap (c) OpenStreetMap contributors, ODbL 1.0.',
   '[{"lat":40.734707,"lng":-73.952339},{"lat":40.734771,"lng":-73.952365},{"lat":40.734983,"lng":-73.952447},{"lat":40.73522,"lng":-73.952506},{"lat":40.735328,"lng":-73.952531},{"lat":40.735442,"lng":-73.952553},{"lat":40.736734,"lng":-73.952765},{"lat":40.737648,"lng":-73.952915},{"lat":40.737749,"lng":-73.952926},{"lat":40.737851,"lng":-73.952929},{"lat":40.737957,"lng":-73.952926},{"lat":40.738055,"lng":-73.952913},{"lat":40.738176,"lng":-73.952885},{"lat":40.738293,"lng":-73.952854},{"lat":40.738358,"lng":-73.952832},{"lat":40.738492,"lng":-73.952787},{"lat":40.73902,"lng":-73.952611},{"lat":40.739423,"lng":-73.952474},{"lat":40.739944,"lng":-73.952305},{"lat":40.740087,"lng":-73.952258},{"lat":40.740643,"lng":-73.952074},{"lat":40.742185,"lng":-73.951545},{"lat":40.742326,"lng":-73.951497},{"lat":40.742707,"lng":-73.951392},{"lat":40.743127,"lng":-73.951291},{"lat":40.743265,"lng":-73.951258}]',
   972, null, 'road', 'New York, NY', 'US'),
  ('00000000-0000-4000-8000-0000000c0129',
   'Queensboro Bridge (NYC Marathon)',
   'Queens to Manhattan on the lower level of the Queensboro Bridge, around miles 15 to 16 of the TCS New York City Marathon, ending at First Avenue. Geometry from OpenStreetMap (c) OpenStreetMap contributors, ODbL 1.0.',
   '[{"lat":40.750894,"lng":-73.940643},{"lat":40.751425,"lng":-73.941878},{"lat":40.751815,"lng":-73.942665},{"lat":40.752254,"lng":-73.943685},{"lat":40.753089,"lng":-73.945605},{"lat":40.754505,"lng":-73.948878},{"lat":40.759001,"lng":-73.959233},{"lat":40.759574,"lng":-73.960551},{"lat":40.760103,"lng":-73.961836}]',
   2058, null, 'road', 'New York, NY', 'US'),
  ('00000000-0000-4000-8000-0000000c012a',
   'Willis Avenue Bridge (NYC Marathon)',
   'Manhattan to the Bronx over the Harlem River on the Willis Avenue Bridge, around mile 20 of the TCS New York City Marathon. Geometry from OpenStreetMap (c) OpenStreetMap contributors, ODbL 1.0.',
   '[{"lat":40.801765,"lng":-73.931213},{"lat":40.801881,"lng":-73.931121},{"lat":40.80231,"lng":-73.930783},{"lat":40.802403,"lng":-73.930705},{"lat":40.802498,"lng":-73.930623},{"lat":40.802606,"lng":-73.930516},{"lat":40.802676,"lng":-73.930437},{"lat":40.802772,"lng":-73.930314},{"lat":40.802835,"lng":-73.93022},{"lat":40.8029,"lng":-73.930125},{"lat":40.802962,"lng":-73.930019},{"lat":40.803042,"lng":-73.929869},{"lat":40.803176,"lng":-73.929593},{"lat":40.80332,"lng":-73.92923},{"lat":40.803713,"lng":-73.928461},{"lat":40.803995,"lng":-73.927899},{"lat":40.80455,"lng":-73.926788},{"lat":40.804777,"lng":-73.926395},{"lat":40.804825,"lng":-73.926299},{"lat":40.804971,"lng":-73.926044},{"lat":40.805042,"lng":-73.925943},{"lat":40.805127,"lng":-73.925831},{"lat":40.805235,"lng":-73.925707},{"lat":40.805314,"lng":-73.92562},{"lat":40.805399,"lng":-73.925538},{"lat":40.805474,"lng":-73.925471},{"lat":40.805553,"lng":-73.925403},{"lat":40.805645,"lng":-73.925332},{"lat":40.805985,"lng":-73.925083},{"lat":40.806693,"lng":-73.924566},{"lat":40.806976,"lng":-73.924356},{"lat":40.807063,"lng":-73.924292},{"lat":40.80707,"lng":-73.924288},{"lat":40.807101,"lng":-73.924272},{"lat":40.807176,"lng":-73.924244}]',
   861, null, 'road', 'New York, NY', 'US'),
  ('00000000-0000-4000-8000-0000000c012b',
   'Madison Avenue Bridge (NYC Marathon)',
   'The Bronx back to Manhattan over the Harlem River on the Madison Avenue Bridge, around mile 21 of the TCS New York City Marathon. Geometry from OpenStreetMap (c) OpenStreetMap contributors, ODbL 1.0.',
   '[{"lat":40.813789,"lng":-73.931376},{"lat":40.813831,"lng":-73.931471},{"lat":40.81399,"lng":-73.931828},{"lat":40.814096,"lng":-73.932052},{"lat":40.814113,"lng":-73.932092},{"lat":40.814128,"lng":-73.932132},{"lat":40.81414,"lng":-73.932183},{"lat":40.814147,"lng":-73.932233},{"lat":40.814151,"lng":-73.932283},{"lat":40.81416,"lng":-73.932588},{"lat":40.814193,"lng":-73.933707},{"lat":40.814211,"lng":-73.934196},{"lat":40.814183,"lng":-73.934326},{"lat":40.814172,"lng":-73.934374},{"lat":40.814154,"lng":-73.93443},{"lat":40.814135,"lng":-73.934479},{"lat":40.814113,"lng":-73.934531},{"lat":40.814085,"lng":-73.934581},{"lat":40.814056,"lng":-73.934622},{"lat":40.814021,"lng":-73.934661},{"lat":40.813987,"lng":-73.934693},{"lat":40.813954,"lng":-73.934721},{"lat":40.813884,"lng":-73.934774},{"lat":40.813588,"lng":-73.934995},{"lat":40.813398,"lng":-73.935138},{"lat":40.812188,"lng":-73.936041},{"lat":40.812096,"lng":-73.93608}]',
   539, null, 'road', 'New York, NY', 'US'),
  ('00000000-0000-4000-8000-0000000c012c',
   'Fifth Avenue climb (NYC Marathon)',
   'Fifth Avenue south from East 110th Street to the Central Park entrance at East 90th Street, the long drag around miles 23 to 24 of the TCS New York City Marathon. Geometry from OpenStreetMap (c) OpenStreetMap contributors, ODbL 1.0. Elevations from the USGS 3DEP 1 m model.',
   '[{"lat":40.797101,"lng":-73.949078,"ele":5.3},{"lat":40.79699,"lng":-73.949157,"ele":5.3},{"lat":40.796705,"lng":-73.949359,"ele":5.3},{"lat":40.796636,"lng":-73.949408,"ele":5.2},{"lat":40.796273,"lng":-73.949654,"ele":4.9},{"lat":40.796222,"lng":-73.949693,"ele":5.1},{"lat":40.796161,"lng":-73.949739,"ele":5.1},{"lat":40.795648,"lng":-73.950113,"ele":4.9},{"lat":40.795585,"lng":-73.950158,"ele":4.9},{"lat":40.795531,"lng":-73.950198,"ele":4.8},{"lat":40.795018,"lng":-73.950569,"ele":5.5},{"lat":40.794963,"lng":-73.950608,"ele":5.5},{"lat":40.794912,"lng":-73.950646,"ele":5.6},{"lat":40.794382,"lng":-73.951039,"ele":6.2},{"lat":40.794285,"lng":-73.951111,"ele":6.4},{"lat":40.794192,"lng":-73.951178,"ele":6.7},{"lat":40.79409,"lng":-73.951252,"ele":6.9},{"lat":40.793962,"lng":-73.951345,"ele":7.3},{"lat":40.793663,"lng":-73.951562,"ele":8.2},{"lat":40.793608,"lng":-73.951602,"ele":8.4},{"lat":40.793561,"lng":-73.951636,"ele":8.5},{"lat":40.793042,"lng":-73.952015,"ele":10.0},{"lat":40.792982,"lng":-73.952059,"ele":10.2},{"lat":40.79293,"lng":-73.952096,"ele":10.3},{"lat":40.792612,"lng":-73.952328,"ele":11.4},{"lat":40.792406,"lng":-73.952479,"ele":12.1},{"lat":40.792347,"lng":-73.952522,"ele":12.3},{"lat":40.792302,"lng":-73.952555,"ele":12.6},{"lat":40.791781,"lng":-73.952935,"ele":14.3},{"lat":40.79172,"lng":-73.952979,"ele":14.5},{"lat":40.791662,"lng":-73.953021,"ele":14.6},{"lat":40.791632,"lng":-73.953043,"ele":14.7},{"lat":40.791148,"lng":-73.953396,"ele":15.8},{"lat":40.791086,"lng":-73.953441,"ele":15.9},{"lat":40.79104,"lng":-73.953475,"ele":16.1},{"lat":40.790471,"lng":-73.95389,"ele":17.5},{"lat":40.789877,"lng":-73.954323,"ele":18.9},{"lat":40.789851,"lng":-73.954342,"ele":18.9},{"lat":40.789782,"lng":-73.954392,"ele":19.1},{"lat":40.7896,"lng":-73.954525,"ele":19.5},{"lat":40.789263,"lng":-73.954771,"ele":20.4},{"lat":40.789204,"lng":-73.954814,"ele":20.5},{"lat":40.789158,"lng":-73.954847,"ele":20.7},{"lat":40.788989,"lng":-73.954971,"ele":21.1},{"lat":40.788641,"lng":-73.955224,"ele":22.2},{"lat":40.788585,"lng":-73.955265,"ele":22.4},{"lat":40.788526,"lng":-73.95531,"ele":22.5},{"lat":40.787982,"lng":-73.955705,"ele":24.0},{"lat":40.787901,"lng":-73.955767,"ele":24.1},{"lat":40.78782,"lng":-73.955826,"ele":24.2},{"lat":40.787273,"lng":-73.956226,"ele":24.7},{"lat":40.787227,"lng":-73.95626,"ele":24.8},{"lat":40.787172,"lng":-73.9563,"ele":25.0},{"lat":40.786655,"lng":-73.956678,"ele":26.8},{"lat":40.786601,"lng":-73.956717,"ele":27.1},{"lat":40.786543,"lng":-73.956759,"ele":27.2},{"lat":40.786035,"lng":-73.957131,"ele":29.6},{"lat":40.785979,"lng":-73.957172,"ele":29.9},{"lat":40.785914,"lng":-73.95722,"ele":29.9},{"lat":40.785401,"lng":-73.957595,"ele":31.1},{"lat":40.785345,"lng":-73.957635,"ele":31.2},{"lat":40.785294,"lng":-73.957673,"ele":31.4},{"lat":40.784779,"lng":-73.958049,"ele":33.2},{"lat":40.784731,"lng":-73.958084,"ele":33.4},{"lat":40.784667,"lng":-73.958132,"ele":33.5},{"lat":40.784168,"lng":-73.958498,"ele":33.9},{"lat":40.784087,"lng":-73.958557,"ele":33.9}]',
   1653, 29, 'road', 'New York, NY', 'US')
on conflict (id) do nothing;

# Park course geometry

Phase 3 of the park courses plan ([#1313](https://github.com/Absence0760/threkir/issues/1313)): the committed, reviewable pipeline that turns trails in a park into course lines for the `parks` / `park_courses` / `global_segments` tables.

## Layout

```
scripts/parks/
  lib/course_geometry.mjs        pure geometry: trace, measure, simplify, checkpoints
  fetch_snapshot.mjs             network step: OSM ways + USGS elevations -> snapshot.json
  build.mjs                      offline step: spec + snapshot -> <course>.geojson + manifest.json
  catalogue/<region>/<park>/
    park.json                    the spec, written by hand
    snapshot.json                source data, written by fetch_snapshot.mjs
    <course>.geojson             one per course, written by build.mjs
    manifest.json                what the operator load reads, written by build.mjs
```

## Adding a course

1. Find the trail's OSM way ids (the OSM website's "Query features" tool, or an Overpass query on the park boundary) and the node where the course starts. Use OSM or NPS data only. Never trace from AllTrails, Strava, Garmin or another app's routes (their terms forbid it), and use Virginia DCR data only once DCR has confirmed the terms in writing.
2. Add the course to the park's `park.json`: `osm_ways` lists the ways of ONE loop (dead-end spurs such as piers are pruned automatically), `start_node` is where timing starts, and `published` is the park's own distance with its source URL.
3. `node scripts/parks/fetch_snapshot.mjs scripts/parks/catalogue/<region>/<park>`
4. `node scripts/parks/build.mjs scripts/parks/catalogue/<region>/<park>`. The build refuses a course whose traced distance is more than 5 % off the published figure.
5. Review the `.geojson` on a map (geojson.io, or drop it into QGIS) against the park's trail map before committing.

`node scripts/parks/build.mjs --check <dir>` fails when a committed output no longer matches its spec and snapshot.

Only loop courses are built so far. Out-and-back and point-to-point courses (the rail trails) are added when the first one is specced.

## Race courses

A park course is the trail as it is, whatever its length. A race course must measure exactly a race distance (`5k`, `10k`, `half`, `marathon`, `50k`), so it is built differently, under `race_courses` in `park.json`:

- `lead_in_via` runs from the start area to the loop, and `loop_via` goes once around the loop and back to where the lead-in meets it. Each is a list of OSM node ids walked in order along `osm_ways`. A race reuses parts of long, branching ways, so the via list is what pins the route: a junction and the node after it for every junction, plus a node about every 400 m. Without the extra pins, a hop several kilometres long along fire roads can be cut short by another part of the listed ways (the half-marathon loop traced 515 m short that way).
- `laps` repeats the loop. Marathon and ultra distances are laps of a shorter loop.
- The build cuts the same length off both ends of lead-in + laps + lead-in, so the course measures exactly the race distance. That puts the shared start/finish line on the lead-in. It refuses a course that comes up short, or one where the start line would land past the lead-in onto the loop. Lengthen or shorten the lead-in, or pick another loop.

Finding a loop that fits is a search over the park's trail graph. For L the loop length, N the laps, D the race distance and S the lead-in length, a loop fits when (D - 2S) / N <= L <= D / N.

## Licence

Everything under `catalogue/` that comes from OpenStreetMap (`snapshot.json`, the `.geojson` files and the geometry in `manifest.json`) is © OpenStreetMap contributors and available under the [Open Database License 1.0](https://opendatacommons.org/licenses/odbl/1-0/). Elevations are from the USGS 3D Elevation Program (public domain). Course pages and GPX exports must credit "© OpenStreetMap contributors".

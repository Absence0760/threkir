# Drive this course

Runners often drive a race course before race day to see the hills, turns and
aid stations. **Drive this course** supports that without a car app of our own
(issue #1310, [decisions § 2380](../architecture/decisions.md)):

1. **Open the course in Maps.** The course becomes a set of legs that Google
   Maps, Apple Maps or Waze will route. That app does the driving, and it shows
   on CarPlay / Android Auto by itself.
2. **Spoken course notes (mobile only).** While the person drives, the phone
   speaks the course's markers as each one comes up: "In 400 metres: Aid
   station, Mile 8. Water, food." Audio only, screen locked, through the car's
   Bluetooth.

The spoken notes are the part only we can offer. The same note-trigger logic
(`DriveCueAnnouncer`) can later drive race-day and run-the-course cues.

**Status:** web (hand-off + notes list) and mobile (hand-off + spoken notes)
are built, behind a default-off flag on both platforms:
`PUBLIC_COURSE_DRIVE_ENABLED` (web) / `COURSE_DRIVE_ENABLED` (mobile). The flag
stays off in production until counsel signs off on the safety notice (see
[Safety notice](#safety-notice-and-the-flag)).

## Out of scope (decided)

- **No native CarPlay / Android Auto app.** CarPlay allows no video, Android
  Auto allows it only when parked, and a running app fits none of their app
  types except navigation, which needs Apple's navigation approval and a full
  turn-by-turn product. Revisit only if usage shows demand.
- **No flyover on the car screen.** The 3D preview (#1270) stays for
  passengers and for planning ahead.
- **No turns in the notes.** The Maps app already gives turn-by-turn
  directions, so `turn_cues` is not read.

## What is reused

| Need | Piece | Notes |
|---|---|---|
| Course line | `clip_route_for_viewer` (route page: `fetchRouteById` / `_displayWaypoints`; race page: `fetchPublicRoute` / `clipRouteForViewer`) | A non-owner gets the clipped line, never the raw one |
| What to say | `route_markers_for_viewer` (`fetchRouteMarkers`), `parseAidServices`, `parseCutoff` | Climb length and grade are read off the served line's own heights |
| Where on the course | `course_drive` (`snapWithinAlong`, `placeOnLine`) | Its own windowed snap; see gotchas 1 and 3 |
| Voice + ducking | `audio_cues.dart` (Android navigation-guidance focus, iOS `playback` + `duckOthers` + `mixWithOthers`) | New `announceDriveNote` / `announceDriveStatus` |
| Can Maps follow it? | The OSRM proxy's `car` profile (web, signed in) / `routing.dart` `fetchRouteThrough(profile: car)` (mobile) | Compared by `undrivableStretches` |
| Units / language | The km/mi preference, the shipped locales | Every phrase is in all web locales and all mobile ARBs |

## Pure core — the `course_drive` parity pair

Web `apps/web/src/lib/routes/course_drive.ts` ↔ mobile
`apps/mobile_android/lib/course_drive.dart`, 24 mirrored tests each. All
distances are along the line the client was **served**.

- **`buildDriveNotes(markers, line)`** places each marker on the line with
  `placeOnLine` (nearest pass to its server `position_m`, within 150 m of the
  line), keeps aid services for aid stations, the cut-off for cut-offs and a
  `climbFrom` length and grade for climbs, and orders the notes by distance. A
  marker further than 150 m from the served line is left out.
- **`driveLeadM(speed)`** = 15 s ahead, held to 150–1000 m. **`driveAtM`** =
  3 s, at least 30 m.
- **`DriveCueAnnouncer`** speaks each note at most twice (ahead, at) and
  reports a skipped one once (passed). See gotcha 2.
- **`planDriveLegs(line, maxWaypoints)`** cuts the line into Maps legs. See
  gotcha 5.
- **`undrivableStretches(line, routed)`** finds where a router's line leaves
  the course. See gotcha 4.
- **`googleMapsLegUrl` / `appleMapsUrl` / `wazeUrl` / `mapsLegUrl` /
  `mapsStartUrl`** build the links (coordinates to 5 decimals, about 1 m).

The live tracker (`apps/mobile_android/lib/course_drive_tracker.dart`) is
mobile-only, because web never follows a moving position, so it is not a pair.

## Gotchas, and how each is settled

### 1. The run recorder rejects car speeds

`GpsDistanceEstimator` caps speed at 10 m/s, so the drive cannot use
`RunRecorder`. `CourseDriveTracker` is its own small tracker on top of the
pair's windowed snap. It holds no track, writes nothing, and has no recorder
dependency, so a drive cannot become a run: no `runs` row, no PR, no auto-pause,
no live-tracking session, no challenge or plan credit.

**How it is enforced:** `course_drive_tracker.dart`, `course_drive_location.dart`
and `screens/course_drive_screen.dart` import none of `run_recorder`,
`local_run_store`, the sync service, live tracking or the challenge / plan
services. `test/course_drive_isolation_test.dart` reads those files and fails on
any such import. The location stream is opened through
`course_drive_location.dart`, a third named location intent beside browse
(`quiet_location.dart`) and record (`RunRecorder`), and the only other file
`quiet_location_test.dart` lets call `getPositionStream`.

### 2. Cue timing tuned for running

`TurnCueAnnouncer` fires on fixed 300 / 100 / 0 m bands with a ±25 m window,
which a car at 14 m/s (50 km/h) can step over between fixes. **Decision: a
sibling, not a generalisation.** `TurnCueAnnouncer` stays as it is (its bands
and tests are tuned for running, and the run screen relies on them);
`DriveCueAnnouncer` is new and lives in the `course_drive` pair:

- The "ahead" band is time-based: about 15 s at the current speed (150 m at a
  standstill, 210 m at 50 km/h, 375 m at 90 km/h, never more than 1 km).
- The "at" band is 3 s, at least 30 m.
- A fix that lands inside both bands speaks only "at".
- A note passed between two fixes with nothing said is reported once as
  "Just passed: …" when it is less than 400 m behind. Further back (a long GPS
  gap) it is retired silently, because a note about something a kilometre
  behind is noise.
- Only the nearest unfinished note is considered, so two close notes queue
  rather than talk over each other. Once a note has had its "at" cue, the next
  one may speak.

Speed comes from the tracker (change in distance along the course over time,
smoothed), not from the GPS speed field, which some devices leave at zero.

### 3. Courses that cross or double back

The tracker never does a global nearest-point snap after its first fix. Each
fix is snapped with `snapWithinAlong` to the window from 50 m behind the last
position to `max(300 m, 60 m/s × seconds since the last fix)` ahead, so the
other pass of an out-and-back, a loop's start/finish or a figure-eight's
crossing is never a candidate. Progress only moves forward (a snap behind the
last position keeps the last position). Markers use the same idea:
`placeOnLine` picks the pass nearest the marker's server `position_m`.

### 4. Parts of the course you can't drive

**Decision: compare a car router's line with the course.** The hand-off routes
each leg's stops through OSRM's `car` profile and runs `undrivableStretches`:
any run of course samples (every 25 m) more than 75 m from the routed line, at
least 200 m long, is a stretch Maps will not follow. The hand-off lists them as
distance ranges ("14.2 – 15.1 mi") under "Maps can't follow these stretches".

- Web uses the existing OSRM proxy, which is signed-in only. A signed-out
  visitor, or a failed or rate-limited call, gets "We couldn't check which
  stretches Maps can follow." Nothing claims the whole course is drivable when
  the check did not run.
- Mobile uses `routing.dart`'s `fetchRouteThrough(profile: car)`, same rules.
- The check compares against OSRM, not against Google's or Apple's router. It
  finds closed paths, bridges and one-ways reliably; it can still differ from
  what the chosen Maps app does, so the hand-off always says "The Maps route is
  guidance only. The notes follow the real course."

### 5. Stop caps

Researched 2026-11-07 (issue #1310): Google Maps URLs take nine waypoints, and
three in a mobile browser; Apple Maps has no documented multi-stop parameter;
Waze takes one destination. `MAPS_WAYPOINT_CAP` / `kMapsWaypointCap*` hold the
numbers.

- **Legs.** `planDriveLegs` pins a leg every 1.5 km. A Google leg's stops are
  its start plus up to eight more (two in a mobile browser), and the
  destination is its end, so a marathon is three legs in the app and seven in a
  mobile browser. The links carry no `origin`: Maps routes from wherever the
  phone is to the leg's start, which also covers joining late.
- **Apple Maps and Waze** get "Drive to the start" plus one leg every 3 km to a
  single destination each.
- **Which cap.** The mobile app uses Google's nine (the link opens the Google
  Maps app; the app's behaviour is not documented, so the manual recipe checks
  it on a device). Web uses three when the browser reports a coarse pointer
  (`(pointer: coarse)`), else nine.
- **Leg done.** On mobile, when the tracker passes a leg's end the phone says
  "Leg 1 done. Leg 2 is ready." and the screen highlights the next leg. Opening
  it is a tap, so it is for a passenger or a stop.
- Links stay far under Google's 2,048-character limit (a nine-stop link is
  about 300 characters), and a test pins that.

### 6. Privacy

A non-owner's hand-off and notes come only from `clip_route_for_viewer` and
`route_markers_for_viewer`. `clip_route_for_viewer` trims in-zone points from
the start and end and serves the middle unbroken, so there is no interior gap
today; `planDriveLegs` still never joins two served points more than 2 km
apart, so if a clip ever served a gap, no leg would bridge it. Stops are
interpolated on served points only, so they can't fall in a zone. Markers that
the RPC redacts never arrive, and any marker more than 150 m from the served
line is dropped.

Drive mode is offered only where the course is public: on the route page when
`is_public` is true (owner included; a private route offers nothing) and the
line is available, and on the race page only through `course_route_id`, which
the view nulls for a private or shadow-hidden route. A deleted route has no
page. Same rule as the race page's course map.

### 7. Screen locked, app in the background

- **Android:** `course_drive_location.dart` opens the position stream with
  geolocator's `ForegroundNotificationConfig` ("Drive notes on"), the same
  foreground-service type the recorder uses, with no recorder involved. A
  1 s fix interval, high accuracy.
- **iOS:** `AppleSettings(allowBackgroundLocationUpdates: true,
  activityType: automotiveNavigation, pauseLocationUpdatesAutomatically:
  false)`; the app already declares the `location` and `audio` background
  modes.
- **Two apps talking.** Our TTS asks Android for navigation-guidance focus,
  which is transient and may-duck; Google Maps asks for the same kind. Each
  ducks the other for the length of an utterance rather than pausing it, so
  neither is cut off. iOS uses `mixWithOthers` + `duckOthers`. The manual
  recipe checks both with Maps speaking.
- **Layered resilience.** Each speech call is its own `try`/`catch` + `debugPrint`
  in the screen; a failed or slow call never stops the tracker, the announcer
  or the screen. A failed Maps launch shows a banner and changes nothing else.

### 8. Driver safety and liability

- The drive view has one control while moving: **Stop**. Starting is a single
  tap (**Start spoken notes**). The leg list stays on the hand-off view, above.
- A one-time notice on each device before the first drive: "Use this with a
  passenger or a mounted phone, and don't touch it while driving. Follow road
  rules and signs. Course roads may be closed on race day, and the Maps route
  may not match the course." The acknowledgement is per device
  (`course_drive_notice_ack`, [settings.md](../backend/settings.md)). Web shows
  the same text in the dialog every time.
- **The wording needs counsel review.** Per decisions § 150 that is a
  pre-deploy checklist item ([deployment.md](../ops/deployment.md)), not
  missing code: the whole feature ships behind the default-off flag.

### 9. Starting and stopping

- **Joining.** The first fix within 300 m of the course is snapped to the
  whole line (nearest point, earliest pass on a tie) and becomes the start;
  every note behind it is retired silently. Until then the screen says "Head to
  the course. Notes start when you reach it."
- **Finish.** Within 75 m of the end of the served line, the phone says "You've
  reached the finish. Drive notes stopped." and the drive stops.
- **Off course.** More than 150 m from the course window for 10 minutes in a
  row stops the drive and says so. Coming back inside the window before that
  resumes it.

### 10. Where it lives, paywall, settings

- **Entry points:** the route page and the race page, on web and mobile, next
  to "Preview in 3D" (web) / in the route page's app bar and the race page's
  course section (mobile).
- **Web** offers the hand-off and the readable, printable list of notes (the
  page's own print stylesheet). **Mobile** adds the spoken notes.
- **Not paywalled** ([paywall.md](paywall.md)): it reads only public course
  data and costs no server work beyond the OSRM check the route builder already
  makes free.
- **No new setting.** The voice follows the app language and the km/mi
  preference; there is nothing to configure. The only stored value is the
  per-device notice acknowledgement.

## Owner decisions taken as defaults

These were implemented as the recommended default and are reported for the
owner to confirm:

- Free for everyone (not paywalled).
- A sibling announcer rather than a generalised `TurnCueAnnouncer`.
- OSRM `car` as the stand-in for "the Maps app's router" in the undrivable
  check.
- 10 minutes off course ends a drive; 400 m is the "just passed" limit.
- The safety-notice wording (pending counsel).

## Testing

- Pure: `routes/course_drive.test.ts` ↔ `test/course_drive_test.dart` (24 each).
- Mobile: `test/course_drive_tracker_test.dart` (tracker),
  `test/course_drive_screen_test.dart` (hand-off, notice, spoken notes with a
  fake position stream and a fake speaker, finish, failed speech),
  `test/course_drive_isolation_test.dart` (no recorder imports).
- Web: `tests-e2e/routes/course-drive.spec.ts` (route page as a non-owner,
  private route offers nothing, undrivable stretch from a mocked OSRM response,
  links, notes list).
- Manual: [manual_testing.md § Drive this course](../testing/manual_testing.md)
  is a real drive with Maps speaking.

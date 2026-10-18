# Structured workout execution

Live execution loop for running a `plan_workouts` row inside the existing `RunRecorder`. Phase 2 of the training-plan feature — the schema + editor + generator are shipped; this is the "start the workout" experience.

> **Status:** v1 shipped on Android. `packages/run_recorder/lib/src/workout_runner.dart` is the state machine + step expander; `apps/mobile_android/lib/widgets/workout_execution_band.dart` is the overlay; entry points are the **Start workout** button on the today's-workout card (Run tab and plan detail; hidden once the workout is done or skipped, and absent on Home, whose card opens plan detail) and the **Start workout** button on `workout_detail_screen` (which pops back to the run tab with the workout loaded). On `recorder.stop()` the run picks up `plan_workout_id`, `workout_step_results`, and `workout_adherence`; both `apps/mobile_android/lib/screens/run_detail_screen.dart` and the web `/runs/[id]` render the planned-vs-actual review section from those keys. Below is the original spec; what shipped largely follows it. `rewindStep` is wired up — `WorkoutRunner.rewindStep()` undoes the most recent advance (whether completed or skipped) and re-enters the previous step with `stepDistanceMetres` reset to zero, mirroring the spec at § Rewind step. The band exposes it as the leftmost button, disabled while on step 0. The **ghost pacer** (deferred from v1) is wired as well: `apps/mobile_android/lib/widgets/ghost_pacer.dart#ghostPacerPosition` walks the planned route's waypoints by `elapsed × target speed` and returns the interpolated lat/lng; `run_screen.dart` passes it through to `LiveRunMap` via the new `ghostPosition` field, which renders a faint outline-only dot under the live blue dot (no second pulse so it doesn't compete for attention). Returns null when the ghost runs off the end of the path so a finished ghost doesn't bunch onto the last waypoint for the rest of the step.

**Contents:** [Product contract](#product-contract) · [Data flow](#data-flow) · [Step expansion](#step-expansion) · [`WorkoutRunner` state machine](#workoutrunner-state-machine) · [Integration with `RunRecorder`](#integration-with-runrecorder) · [UI](#ui) · [Audio cues](#audio-cues) · [Control semantics](#control-semantics) · [Persistence](#persistence) · [Failure modes](#failure-modes) · [Testing](#testing) · [File list](#file-list) · [Open questions](#open-questions) · [Rough sizing](#rough-sizing)

## Product contract

The user opens a planned workout (from `todays_workout_card` or `workout_detail_screen`) and taps **Start workout**. They get the familiar run screen plus:

- A **top band** on the map showing the current step: `Rep 3/6 · 400 m @ 4:00/km` with a thin progress bar for the step and a green / amber / red pace-adherence pip.
- **Automatic step advance** when the step's target distance is hit. The band slides to the next step and the recorder keeps running — same GPS, same clock, same distance total.
- **Audio cues** at step transitions ("Rep 4 of 6, four hundred metres at four per kilometre"), at half-distance, in the last 50 m of each step, and when behind/ahead by more than the tolerance.
- **Manual controls** in the band: skip to next step, rewind to previous step, abandon (convert to free run).
- **Post-run summary** that shows planned vs actual per step, not just the overall pace.

Non-goals for v1: ~~time-based steps~~ (**shipped** — walk-run / C25K plans use `duration_s` reps; the runner reads distance OR duration per step), live interval-aware heart-rate zones (nice-to-have), adapting upcoming steps based on current effort.

## Data flow

```
plan_workouts.structure (jsonb, already stored)
    │
    │  _expandStructureToSteps(structure, paces)
    ▼
List<WorkoutStep>           ← computed once at workout start
    │
    │  WorkoutRunner consumes RunSnapshot stream
    ▼
Current step index + per-step start distance/elapsed
    │
    │  emit WorkoutExecEvent stream (transition, pace-drift, complete)
    ▼
Audio cues + execution-band UI rebuild
    │
    │  on recorder.stop():
    ▼
run.metadata.plan_workout_id      ← links the saved run back to the plan
run.metadata.workout_step_results ← per-step planned-vs-actual
run.metadata.workout_adherence    ← 'completed' | 'partial' | 'abandoned'
```

## Step expansion

`WorkoutStructure` (already in `training.dart`) has four optional sections. The expansion rule is fixed and simple:

1. `warmup` → one step
2. `repeats.count` × `{ rep, recovery }` pairs, but the **last rep has no trailing recovery** (cooldown takes its place)
3. `steady` → one step (mutually exclusive with `repeats` in current plans, but the expansion handles both existing)
4. `cooldown` → one step

Example: 6×400 with warmup + cooldown → **14 steps** (1 warmup + 6 reps + 5 recoveries + 1 cooldown).

A workout with no `structure` (e.g. "Easy 8 km") expands to a **single step** covering `target_distance_m` at the workout's `target_pace_sec_per_km`. The execution band still shows, just with a single row — the user gets a visible progress bar and pace-adherence pip without adding a code branch.

**Walk-run (C25K / Galloway) — persona #22, decisions §91.** A rep or recovery block may carry `duration_s` / `recovery_duration_s` instead of distances; the runner builds duration-based steps (end condition is elapsed time, not distance). When `recovery_pace == 'walk'`, `expandWorkoutSteps` relabels the work intervals **Run i/n** (kept `WorkoutStepKind.rep`) and the rest intervals **Walk i/n** (tagged `WorkoutStepKind.walk`), so the transition cue announces "Run 1 of 8. 1 minute." / "Walk 1 of 7. 1 minute 30 seconds." (duration spoken instead of distance + pace). Example: warmup-walk → 8× (run 60s / walk 90s) → cooldown-walk expands to **17 steps** (1 + 8 runs + 7 walks + 1).

**A walk-run session is not a pace test (decisions § 2074).** Every step of one, the walking warm-up and cool-down included, expands with `WorkoutStep.paced == false`: `paceAdherence` reads `onPace`, no `PaceDriftEvent` fires, and the band hides its pace pip. The voice says only the Run / Walk transitions and the end-of-step warning, and the warm-up and cool-down announce themselves as walks ("Warm-up walk. 5 minutes.") so a beginner doesn't start running on "Warmup". `targetPaceSecPerKm` still carries the plan's easy pace, which the distance estimate and the band header read. The custom watch receives the same contract as flag bit 0 (`WORKOUT_FLAG_UNPACED`) of the `WKT1` header, which is whole-frame because the expander makes a whole session unpaced or none of it.

Step resolution for symbolic paces (`'easy'`, `'jog'`): look up on the plan's `paces` bag (VDOT-derived, already stored on `training_plans`). `'easy'` → `paces.easy`, `'jog'` → `paces.recovery`. Numeric paces in `repeats.pace_sec_per_km` / `steady.pace_sec_per_km` pass through unchanged.

### `WorkoutStep` shape

```dart
class WorkoutStep {
  final WorkoutStepKind kind;          // warmup | rep | recovery | steady | cooldown
  final int? repIndex;                 // 1-based, only for rep + recovery
  final int? repTotal;                 // only for rep + recovery
  final double targetDistanceMetres;
  final int targetPaceSecPerKm;
  final int toleranceSecPerKm;         // inherits workout-level tolerance, default 10
  final String label;                  // "Warmup", "Rep 3/6", "Recovery 3/5", "Cooldown"
}
```

No duration-based field in v1 — see open questions.

## `WorkoutRunner` state machine

Lives in **`packages/run_recorder/lib/src/workout_runner.dart`** so iOS / watch can reuse it later. Sits *on top of* `RunRecorder`, not inside — the recorder stays focused on GPS/time/distance, the runner is a stateful consumer of `RunSnapshot`s.

```dart
class WorkoutRunner {
  WorkoutRunner(this.steps, {required this.plan PacesBag paces});

  final List<WorkoutStep> steps;
  int get currentStepIndex;
  WorkoutStep? get currentStep;           // null after the last step
  bool get isComplete;

  // Current-step derived metrics (cheap getters, recomputed from the last snapshot).
  double get stepDistanceMetres;
  Duration get stepElapsed;
  int? get stepAveragePaceSecPerKm;
  PaceAdherence get paceAdherence;        // onPace | ahead | behind | wayAhead | wayBehind
  double get stepRemainingMetres;

  // Drive.
  void onSnapshot(RunSnapshot s);

  // Controls — all idempotent if called after completion.
  void skipStep();                        // mark current complete, advance
  void rewindStep();                      // current restarts at now; prior step re-entered
  void abandon();                         // stop emitting transitions; recorder keeps running

  // Results (call when recorder.stop() is about to fire).
  List<WorkoutStepResult> snapshotResults();

  Stream<WorkoutExecEvent> get events;
  void dispose();
}
```

Auto-advance trigger: on each `onSnapshot`, compare `stepDistanceMetres` (= `snapshot.distanceMetres - _stepStartDistance`) to `currentStep.targetDistanceMetres`. If ≥, call `_advance(snapshot)`. Same logic whether the distance accumulated quickly or slowly; the recorder's pause gate already keeps stepDistance from creeping during a manual pause.

No internal "workout paused" flag — there is exactly one pause in the system, the recorder's. That's the whole point of sitting on top.

## Integration with `RunRecorder`

The recorder is unchanged. Hooking points in `run_screen.dart`:

1. **Construct**: if the route extras carry a `PlanWorkoutRow`, `_preload` builds a `WorkoutRunner(steps, paces: ...)` from the workout's structure + the plan's `paces` jsonb. Stored on `_State` alongside `_recorder`.
2. **Consume**: the existing `_onSnapshot` handler calls `_workoutRunner?.onSnapshot(snapshot)` before its own logic. The runner either no-ops or emits a `WorkoutExecEvent`.
3. **React**: subscribe to `_workoutRunner!.events` in `_preload` and:
   - `StepTransitionEvent` → fire audio cue, force one `setState` for the top band (cadence slow enough that a full rebuild is fine), schedule the "halfway" + "last 50 m" timers relative to the new step.
   - `PaceDriftEvent` → fire audio cue (throttled ~45 s so we don't nag).
   - `WorkoutCompleteEvent` → band collapses to "Workout complete · run on or stop", no audio change.
4. **Save**: `_finishRun` reads `_workoutRunner?.snapshotResults()` and writes to `run.metadata` before `saveRun`.
5. **Dispose**: in `_State.dispose`, call `_workoutRunner?.dispose()`.

The `_onSnapshot` handler in `run_screen.dart` remains free of `setState` — step transitions are routed through a new `_workoutNotifier` (same `ValueNotifier` pattern as `_statsNotifier`) to avoid the full-tree rebuild cost per CLAUDE.md hot-path rule.

## UI

One new widget: `apps/mobile_android/lib/widgets/workout_execution_band.dart`. Mounted at the top of the map stack in `run_screen.dart`, above the existing off-route banner.

**Where it actually sits (issue #666).** The band shipped as its own `Positioned` anchored on the status-bar inset, while every other top overlay composed into the single `top: 56` column from round 4 — so an armed workout painted the band straight over the live-share and route-remaining badges. It is now the first slot of `RunTopOverlay` (in `run_screen.dart`), which owns the one anchor for the band, the badge row and `RunTopBanners`, and takes the larger of 56 and the device's top inset so the band still clears a tall cutout. The band's shell dropped its own outer margin — the column supplies it. Adding a new top overlay means adding a slot there, not another `Positioned`; `run_screen_top_banners_test.dart` pins the non-overlapping rects, armed and unarmed.

```
┌────────────────────────────────────────────────┐
│ Rep 3/6 · 400 m @ 4:00/km         ● ahead −6s │
│ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░  320 m to go    │
│                                                │
│  [↶ back]    [skip step ↷]    [abandon]        │
└────────────────────────────────────────────────┘
```

- **Line 1**: step label · target distance · target pace. Pace pip colour tracks `paceAdherence` (green onPace, amber ahead/behind, red wayAhead/wayBehind) with a signed seconds delta.
- **Line 2**: progress bar + remaining-metres readout. Bar fills as `stepDistance / targetDistance` capped at 1.0.
- **Line 3**: expander. Collapsed by default; tap the card to expand. Keeps screen real estate for the map.

After the final step, the band switches to a **"Workout complete"** state — a green pip, no controls, and a "Cooldown done — tap stop to save" hint.

The existing collapsible stats panel underneath (distance / time / pace) is unchanged. The map still shows the pace-heatmap polyline. Nothing competes for the same space.

## Audio cues

Reuses `audio_cues.dart`. New cue kinds, all throttled and fire-and-forget (wrap each in try/catch + `debugPrint` per layered-resilience rules):

| Trigger | Utterance |
|---|---|
| Step transition | "Next: rep three of six. Four hundred metres at four minutes per kilometre." |
| Halfway (≥ 50 % of target on the step's own axis, once per step) — **paced `rep` steps only**: never on a warm-up, recovery, steady block, cool-down or walk-run interval, where "this rep" is wrong and the band already shows what is left | "Halfway through this rep." |
| Last 50 m of a distance step over 100 m (`StepProgressKind.lastFiftyMetres`, once per step) | "Fifty metres to go." — "Fifty yards to go." in miles mode (the window is 50 m, about 55 yd) |
| Last 10 s of a timed step over 20 s (`StepProgressKind.lastTenSeconds`, once per step) — a walk-run interval hears this before every Run / Walk switch | "Ten seconds to go." |
| Pace drift (every ≥ 45 s while `wayBehind` / `wayAhead`; never on an unpaced walk-run step) | "Pick it up — 25 seconds per kilometre behind pace." / "Ease up — 40 seconds per mile ahead of pace." — the miss is measured per km, converted to the runner's unit and rounded to 5 s (`workoutPaceDriftUtterance`) |
| Workout complete | "Workout complete. Nice work." |

**The general pace alert stands down during a workout (decisions § 2076).** The run screen's pace alert targets the saved target pace or the race-strategy phase, not the current step. While `WorkoutRunner.ownsPaceCues` is true (from arming until the workout completes or is abandoned) that alert does not fire, its haptic included, and the step's own drift cue is the only pace voice. Once the workout ends the run carries on as a free run and the general alert resumes.

Transition cues stall the halfway / last-50 m tracking on the previous step — any mid-step cue that would have fired after the advance is dropped.

## Control semantics

- **Skip step**: marks the current step as "incomplete" in results (actual distance < target), advances. Recorder keeps running. Useful when the user bails out of a rep but wants the plan intact for the next one.
- **Rewind step**: the current step's distance counter resets to zero and the previous step re-enters. Used when the user accidentally tapped skip, or took too short a recovery and wants to redo it. Only rewinds one step — no deep history.
- **Abandon workout**: stops emitting events, band collapses to "Workout abandoned", recorder continues as a free run. On save, `workout_adherence = 'abandoned'`. No way back from abandon in-session (the intent is "I just want to run").

All three are idempotent and safe during any `isComplete` state.

## Persistence

Three new `runs.metadata` keys — register in [metadata.md](../backend/metadata.md) in the same turn as shipping the code:

- `plan_workout_id` — uuid of the linked `plan_workouts` row. The database matcher (`private.match_runs_to_plan_workouts`, migration `20270901000001`) links that workout first, at any distance, when it belongs to the runner, is not a template row, is not already linked to another run by hand or by an earlier explicit link, and is not a workout the runner took this run off before; it takes the workout from an auto-matched run and clears a skip ([decisions § 2079](../architecture/decisions.md)).
- `workout_step_results` — `Array<{ step_index, kind, rep_index?, rep_total?, target_distance_m, actual_distance_m, target_pace_sec_per_km, actual_pace_sec_per_km, duration_s, status: 'completed' | 'skipped' }>`. One row per step, including skipped ones.
- `workout_adherence` — `'completed' | 'partial' | 'abandoned'`. `completed` = all steps hit target ±tolerance. `partial` = any step skipped or more than 20 % short. `abandoned` = user tapped abandon.

Run detail screen on mobile + web adds a "Workout" section when `plan_workout_id` is set — shows the planned-vs-actual table.

## On the wrist (Wear OS and Apple Watch)

Today's workout reaches both watches as a wrist-only port ([decisions § 24](../architecture/decisions.md#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive), the § 354 reasoning). Nothing is authored or edited on a watch.

- **Push.** The phone builds one payload (`apps/mobile_android/lib/watch_workout_push.dart`, `buildWatchWorkoutPayload`) from the same plan-overview read Home already does, expanded with `expandPlanWorkoutSteps` and the plan's pace bag (`plan_workout_steps.dart`, the one derivation the run screen also uses), and held to the custom watch's `WKT1` gate so a session no wrist could run is offered on none. Android writes it as a Data Layer item at `/todays_workout` (`WearWorkoutBridge.kt` → the watch's `WorkoutBridge.kt`); iOS queues the same JSON text with `transferUserInfo` under `todays_workout` (`WatchIngestBridge.swift`, `push_workout` → `WatchConnectivityManager`). A payload with no `plan_workout_id` is the explicit "nothing today" and clears the wrist, so a workout done, skipped or moved on the phone stops being offered the next time the phone reads the plan. The contract is `fixtures/watch_workout_payload.json`.
- **Offer.** Each watch offers the workout only when its `scheduled_date` is the watch's own calendar day, re-checked at Start so a pre-run screen left open past midnight cannot arm yesterday's session, and only once: after a run on it the same workout is not offered again until the phone pushes something else. The pre-run screen shows it with its step count and what it covers; it is followed by default, and one tap runs free instead.
- **Run.** `WorkoutRunner.kt` / `WatchWorkoutRunner.swift` are one-way ports of this runner (see [parity_pairs.md](../architecture/parity_pairs.md) § `workout_runner`), fed the run's distance and ACTIVE elapsed time on the recorder's own clock (Wear's 500 ms ticker, watchOS's 1 s timer), never while paused. The running screen shows the step and what is left of it on its own axis ("Rep 2/6 · 0.25 km", "Recovery · 01:15", "Workout done").
- **Controls.** There is no spare control mid-run on a wrist, so the **lap press also skips the step**, Garmin's grammar and the custom watch's (§ 354). Rewind, abandon and the halfway cue are not ported.
- **Haptics.** One cue per feed, most important first: completion, a new step, the end-of-step warning, then pace drift (`workoutCue` / `WatchWorkoutCue.cue`). Wear OS vibrates its own patterns (one 500 ms buzz for a new step, three short ticks for the last 50 m / 10 s, two long buzzes at the end); watchOS plays `.start`, `.click` and `.success`. Drift reuses each watch's pace alert (haptic plus the spoken cue), and the general target-pace alert stands down while the workout owns pace, as on the phone (§ 2076). The session's first step is silent because Start already cued.
- **Speech (§ 2145, § 2146).** Beside the haptics, both watches speak the phone's step sentence on each step change, the first included even though it is not buzzed ("Rep 3 of 6. 400 metres at 4 minutes per kilometre.", "Walk 1 of 8. 1 minute 30 seconds."; an unpaced distance step drops the pace; miles mode says yards, miles and per-mile pace), and "Workout complete. Nice work." at the end. In `full` verbosity they also speak the end-of-step warning ("Fifty metres to go", "Fifty yards to go", "Ten seconds to go" on a timed step) and the drift cue (Wear OS speaks the step's seconds-behind sentence; watchOS still says "Pick up the pace / Slow down"). `minimal` keeps step changes and completion; voice off or the `workout_steps` cue off silences all of it, and the haptics fire regardless. A step cue waits behind a sentence already being spoken rather than cutting it off, goes ahead of a waiting split, and replaces an older unsaid step cue. Wear OS reads the three switches from the universal bag (`workout/WorkoutSpeech.kt`, `cueQueueMode`); the Apple Watch receives `voice_feedback_verbosity` and `voice_cue_workout_steps` in the phone's settings push (`apple_watch_prefs_bridge.dart` → `PhoneSettings`) and speaks through `RunSpeech`'s `SpeechQueue`.
- **Review.** The run carries `plan_workout_id`, `workout_step_results` and `workout_adherence`, so the database matcher links it (§ 2079). Both watches keep the review in their crash checkpoint (the step in progress as `skipped`), so a recovered run keeps the link. Wear OS uploads it directly in `buildRunMetadata`; the Apple Watch sends it in the `transferFile` envelope, where an unmeasured pace is omitted rather than sent as `NSNull` (a non-plist value would cost the whole transfer), and the phone's `runFromWatchPayload` forwards the three keys as a group or not at all. A watchOS run continued after a termination saves the review its checkpoint carried; the runner itself is not rebuilt mid-step.
- **Not built here.** The custom watch's product push surface stays deferred (§ 71 / § 80).

## Lock screen, phone haptics and glances

The phone surfaces a runner reads without opening the app ([decisions § 2140](../architecture/decisions.md)–§ 2144).

- **Lock screen.** While a workout runs, the current step leads both lock screens. `LockScreenStep` (`apps/mobile_android/lib/lock_screen_step.dart`) builds it from the live `WorkoutRunner`, naming the step with `workoutStepName` (the same words the spoken cue uses) plus what is left and the target pace: "Rep 3 of 6 · 280 m to go · @ 4:00 /km", or "Walk · 1:30 to go" for a timed, effort-led step. Android puts it in the ongoing notification's title, with time / distance / pace as the collapsed line (a paused run keeps its paused title and moves the step into the body). The iOS Live Activity shows it above the stats on the lock screen and in the expanded Dynamic Island; a step change is pushed at once, outside the ~10 s cadence, and a timed step counts down on-device from an end date like the run clock. On completion it reads "Workout complete · tap stop to save"; after an abandon it disappears.
- **Phone haptics.** Every `StepTransitionEvent` buzzes the phone: three long pulses into a rep or steady block, two into a warm-up, recovery, walk or cool-down, including the first step, a skip and a rewind. `WorkoutCompleteEvent` gets one long pulse then two short; pace alerts use short pulses. Progress, drift and abandon stay voice-only. The decision is `stepHapticFor` (`lib/step_haptics.dart`); playback is the native `run_app/haptics` channel (Android vibrator waveforms in the notification category, iOS the system vibrate sound repeated), because `HapticFeedback` is dropped with the screen off. It is gated only on `haptic_feedback_enabled` ("Vibration cues"), so minimal voice mode and audio-off still get it.
- **Home-screen widget.** Android's `TodayWorkoutWidgetProvider` and iOS's `TodayWorkoutWidget` render a Dart-written seven-day snapshot (`lib/today_widget.dart`, fed from the same plan-overview read as the watch push), so they roll over at local midnight without the app and never format or translate. A tap opens the workout detail (`com.threkir.app://plans/<id>/workouts/<wid>`), from which Start arms the runner; the widget never starts a session itself.
- **Wrist glances.** The Wear OS tile's idle state and the Run stats complication, and all four Apple Watch complication families, show today's pushed workout only on the watch's own day and drop it at local midnight through a timeline entry. On Wear OS a tap arms the workout on the pre-run screen, and a workout this watch already ran is not offered again (`LastRun.planWorkoutId`).

## Failure modes

- **GPS lost mid-step**: step distance stalls (recorder's distance doesn't grow without a fix). Clock keeps running. Auto-advance doesn't trigger; user has to skip manually or wait for GPS. Same degradation path the rest of the recorder already has — no new fallback code.
- **Phone call / app backgrounded**: foreground service keeps recording. Runner is an in-process consumer; it picks back up when the app resumes because snapshots keep flowing. No persisted runner state needed for v1.
- **Process killed mid-run**: the run is recovered on next launch via `LocalRunStore.loadInProgress()` (the same path that's covered ultra-length runs since the May 2026 hardening). As of 7d, the workout review trail survives too — `_saveInProgress` calls `WorkoutRunner.reviewMetadata` on every tick, so the recovered run lands with `plan_workout_id`, `workout_step_results`, and `workout_adherence` already on its metadata bag. The in-progress step shows as `skipped` (the user crashed before completing it); adherence reads `partial`. A separate "resume the live recording session" mode (re-spawn GPS, re-enter the runner mid-step) is still out of scope — what's shipped is preservation of the review, not continuation of the run.
- **Empty workout structure**: expansion produces zero steps. The runner treats this as an instant `isComplete` and the band doesn't mount. No null-deref.
- **Plan paces missing**: symbolic paces resolve to defaults (`easy = 360 s/km`, `jog = 420`) with a `debugPrint`. Better than crashing.

## Testing

New test file **`packages/run_recorder/test/workout_runner_test.dart`**:

- Expansion: 6×400 workout → 14 steps with correct labels; no-structure workout → 1 step; `steady`-only workout → 3 steps.
- Auto-advance: inject synthetic snapshots with increasing distance; assert the runner advances exactly when `stepDistance >= target`.
- Skip: manual skip advances and marks the step `status: 'skipped'` in results.
- Rewind: rewinds one step and re-entering that step resets step distance to zero.
- Abandon: no more events after abandon, even when snapshot distance crosses the would-be target.
- Pace adherence: given target 240 s/km and a step lasting 400 m over 110 s (275 s/km, 35 s slow), the runner reports `wayBehind`.
- Results: `snapshotResults()` covers all expanded steps, with the right kinds / rep numbering / skipped flags.

Widget-level coverage for the band is out of scope (there are no widget tests on `mobile_android` — the repo-wide gap mentioned in `CLAUDE.md`). The unit-tested runner is the behaviour that matters; the band is a thin reader over its state.

## File list

Net new:
- `packages/run_recorder/lib/src/workout_runner.dart` — state machine + events
- `packages/run_recorder/test/workout_runner_test.dart` — the tests above
- `apps/mobile_android/lib/widgets/workout_execution_band.dart` — the overlay

Modified:
- `packages/run_recorder/lib/run_recorder.dart` — re-export the runner + events
- `apps/mobile_android/lib/screens/run_screen.dart` — preload / snapshot / save wiring, route-argument plumbing for the incoming `PlanWorkoutRow`
- `apps/mobile_android/lib/screens/workout_detail_screen.dart` — primary **Start workout** button navigates to the run screen with the workout attached
- `apps/mobile_android/lib/widgets/todays_workout_card.dart` — an explicit **Start workout** button loads the runner; tapping the rest of the card opens the workout detail (the Start / Details sheet it used to open was removed, decisions § 2077)
- `apps/mobile_android/lib/audio_cues.dart` — new cue kinds
- `apps/mobile_android/lib/screens/run_detail_screen.dart` — "Workout" section when `plan_workout_id` is set
- `apps/web/src/routes/runs/[id]/+page.svelte` — same section on the web run detail

## Open questions

1. **Duration-based steps.** *Shipped (v2 follow-up).* `WorkoutStep.targetDurationSec` is a nullable int — when positive, the step is duration-based and `WorkoutRunner` swaps the distance-axis checks for time-axis ones (auto-advance, halfway cue, end-of-step warning at last 10 s for `> 20 s` steps, emitted as `StepProgressKind.lastTenSeconds` so the voice says "ten seconds to go" rather than a distance). `expandWorkoutSteps` honours `duration_s` in any block (warmup / repeats.rep / repeats.recovery / steady / cooldown); when both `distance_m` and `duration_s` are present, distance wins for backwards-compatibility. The band header renders `Stride · 30s @ 4:00/km` and the footer shows `12s to go`; the post-run review table renders time on the plan + actual columns when `target_duration_s` is on the result row. `runs.metadata.workout_step_results[].target_duration_s` is the optional registered key (see `docs/backend/metadata.md`).
2. **Audio cue wording** — "four hundred metres" vs "point four kilometres" vs "four hundred" (metric unit implied). Stick with the verbose-and-clear form for v1; revisit if users flag it.
3. **Tolerance default** — 10 s/km is tight for a beginner, loose for a racer. The existing `plan_workouts.target_pace_tolerance_sec_per_km` is editable; default stays 10 but surface it in the workout editor.
4. **Skip vs abandon ergonomics** — two buttons that sound similar. If user testing shows confusion, collapse to one "stop workout" that the user confirms to "stop entirely" or "convert to free run".
5. **Ghost pacer on the map?** *Shipped (v2 follow-up).* Pure-geometry helper `apps/mobile_android/lib/widgets/ghost_pacer.dart#ghostPacerPosition` walks the planned route by `elapsed × target speed` and returns an interpolated lat/lng; `run_screen.dart` feeds it to `LiveRunMap` via the new `ghostPosition` field, which renders a faint outline-only dot UNDER the live blue dot. No animation — only the live position pulses — so the ghost reads as secondary signal. Returns null when the ghost overshoots the path end so it doesn't bunch on `path.last` for the rest of the step.

## Rough sizing

- `WorkoutRunner` + tests: ~1 day
- Band widget: ~0.5 day
- `run_screen.dart` integration (preload, snapshot, save, route args): ~1 day
- Audio cues: ~0.5 day
- `run_detail_screen.dart` + `apps/web` workout section: ~0.5 day
- Polish / manual device QA: ~0.5 day

**Total: ~4 dev-days of concentrated work.** Fits inside one focused week with buffer for the inevitable audio / device-QA surprises.

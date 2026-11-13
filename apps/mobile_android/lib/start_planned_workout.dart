import 'package:core_models/core_models.dart' show PlanWorkoutRow;
import 'package:flutter/widgets.dart';

import 'main.dart' show pendingStartWorkout;
import 'return_to_shell.dart';
import 'run_stop_dock.dart';
import 'screens/run_screen.dart' show runSummaryShowing;

/// Start [workout] now: load it on the recorder and ask for the start, so the
/// countdown begins with it armed (issue #1374, "Start always starts the
/// run"). A Start on a planned workout used to load it onto the idle Run page
/// only, and the runner pressed Start a second time there.
///
/// Nothing here starts a session. The recorder loads the workout from
/// [pendingStartWorkout], then takes the [RunStartRequest.start] through its
/// own `_beginCountdown`, which waits for the load and runs the permission,
/// GPS, background-location and battery checks before the cancellable 3-2-1.
/// A recorder that is not on its start screen drops the request.
void requestPlannedWorkoutStart(PlanWorkoutRow workout) {
  // The recorder loads a workout only from its start screen, so a finished
  // run's summary is closed first, as the centre button closes it.
  if (runSummaryShowing.value) runSummaryDismissRequests.request();
  // Cleared first: the recorder leaves a handoff it could not honour in
  // place, and writing the same row again would notify nobody.
  pendingStartWorkout.value = null;
  pendingStartWorkout.value = workout;
  runStartRequests.request(RunStartRequest.start);
}

/// [requestPlannedWorkoutStart] from a screen above the shell: the shell is
/// brought back first through [returnToShell], so a form above it is asked to
/// discard, and keeping it cancels the start. Resolves whether it started.
Future<bool> startPlannedWorkout(
  NavigatorState navigator,
  PlanWorkoutRow workout, {
  RoutePredicate? isShell,
}) async {
  if (!await returnToShell(navigator, isShell: isShell)) return false;
  requestPlannedWorkoutStart(workout);
  return true;
}

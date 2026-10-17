import 'dart:convert';

import 'package:core_models/core_models.dart' show PlanWorkoutRow;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:run_recorder/run_recorder.dart'
    show WorkoutStep, WorkoutStepKind;

import 'plan_workout_steps.dart' show expandPlanWorkoutSteps, planPaceBag;
import 'training.dart' show toIsoDate;
import 'training_service.dart' show ActivePlanOverview;
import 'watch_workout.dart' show encodeWorkoutSteps;
import 'widgets/runner_menu.dart' show todaysOpenWorkout;

/// Version of the today's-workout payload both watches decode. A watch
/// refuses any other value rather than guessing at a shape it was not built
/// for (`parseWorkoutPush` on Wear OS, `PushedWorkout.decode` on watchOS).
const int kWatchWorkoutPayloadVersion = 1;

/// Build the today's-workout payload the phone pushes to Wear OS (a Data
/// Layer item at `/todays_workout`) and to the Apple Watch
/// (`transferUserInfo`, key `todays_workout`). Both carry the SAME JSON text,
/// so one fixture (`fixtures/watch_workout_payload.json`) holds all three
/// rails to it.
///
/// The steps travel pre-expanded, the custom watch's §354 model: the plan's
/// structure and its pace bag live on the phone, so the watch receives the
/// flat list [expandPlanWorkoutSteps] produces and runs it as given. A watch
/// never re-derives a pace.
///
/// A payload with no `plan_workout_id` is the explicit "nothing today" value:
/// no plan, a rest day, a workout already done or skipped, or one with
/// nothing to follow. It is pushed rather than omitted, so a watch holding
/// yesterday's push, or a workout the runner has since done on the phone,
/// drops it. The watch also refuses a push whose `scheduled_date` is not its
/// own today, so an app left open past midnight cannot arm a stale session.
///
/// The steps are held to the custom watch's `WKT1` plausibility gate
/// ([encodeWorkoutSteps]): at most 64 steps, one positive end axis each, a
/// pace inside the 2:00–99:00 /km band, a tolerance inside a byte. A session
/// that fails it is not offered on any wrist, rather than offered on two and
/// refused on the third.
///
/// Shaped so a Wear tile, a watch complication or a phone widget can read the
/// same value later: everything a "today" glance needs (kind, date, steps,
/// distance or duration) is here, and nothing is phone-only.
Map<String, Object> buildWatchWorkoutPayload(
  ActivePlanOverview? overview,
  DateTime now,
) {
  const none = <String, Object>{'v': kWatchWorkoutPayloadVersion};
  if (overview == null) return none;
  final workout = todaysOpenWorkout(overview.workouts, now);
  if (workout == null) return none;
  final steps = expandPlanWorkoutSteps(
    workout,
    paces: planPaceBag(overview.plan),
  );
  if (steps.isEmpty) return none;
  try {
    encodeWorkoutSteps(steps);
  } on ArgumentError catch (e) {
    debugPrint('watch workout push: ${workout.id} not offered: $e');
    return none;
  }
  return watchWorkoutPayloadFor(workout, steps);
}

/// The payload for [workout] expanded to [steps], which must already have
/// passed the `WKT1` gate. Split out so the fixture test can drive the exact
/// shape from known steps.
@visibleForTesting
Map<String, Object> watchWorkoutPayloadFor(
  PlanWorkoutRow workout,
  List<WorkoutStep> steps,
) {
  return <String, Object>{
    'v': kWatchWorkoutPayloadVersion,
    'plan_workout_id': workout.id,
    'scheduled_date': toIsoDate(workout.scheduledDate),
    'workout_kind': workout.kind,
    // Whole-session, as `WKT1` flag bit 0 is: the expander makes a walk-run
    // session unpaced throughout or not at all, and the gate above refuses a
    // mix.
    'unpaced': steps.every((s) => !s.paced),
    'steps': [for (final s in steps) _stepJson(s)],
  };
}

Map<String, Object> _stepJson(WorkoutStep s) => <String, Object>{
      'kind': _kindToken(s.kind),
      if (s.repIndex != null) 'rep_index': s.repIndex!,
      if (s.repTotal != null) 'rep_total': s.repTotal!,
      // One end axis, as on the wire to the custom watch: a duration step
      // carries no distance even when its source block had one.
      if (s.isDurationBased)
        'duration_s': s.targetDurationSec!
      else
        'distance_m': s.targetDistanceMetres.round(),
      'pace_s_per_km': s.targetPaceSecPerKm,
      'tolerance_s_per_km': s.toleranceSecPerKm,
    };

String _kindToken(WorkoutStepKind kind) => switch (kind) {
      WorkoutStepKind.warmup => 'warmup',
      WorkoutStepKind.rep => 'rep',
      WorkoutStepKind.recovery => 'recovery',
      WorkoutStepKind.walk => 'walk',
      WorkoutStepKind.steady => 'steady',
      WorkoutStepKind.cooldown => 'cooldown',
    };

/// Keeps both watches holding today's planned workout.
///
/// Fed from the shell's plan-overview read (`home_screen.dart`), which runs
/// at start and on every training change, so a workout edited, moved, done or
/// skipped on the phone reaches the wrist on the next read. A failed read
/// pushes nothing: the watch keeps what it had, and its own date check stops
/// that from outliving the day.
///
/// Fire-and-forget. Nothing on the phone waits on it, so a channel failure is
/// logged and the diff cache left unset, and the next read tries again.
class WatchWorkoutBridge {
  /// One instance per process, so the diff cache is shared by every caller.
  factory WatchWorkoutBridge() => _instance;

  WatchWorkoutBridge._();

  static final WatchWorkoutBridge _instance = WatchWorkoutBridge._();

  @visibleForTesting
  static const String wearChannelName = 'run_app/wear_workout';

  /// The Apple Watch route channel, whose native half
  /// (`WatchIngestBridge.swift`) owns the one `WCSession` delegate slot.
  @visibleForTesting
  static const String appleChannelName = 'run_app/watch_route';

  static const _wear = MethodChannel(wearChannelName);
  static const _apple = MethodChannel(appleChannelName);

  /// The last JSON text that reached the native side. `transferUserInfo` is a
  /// durable queue, so an identical re-push is a wasted slot, not a wasted
  /// packet.
  String? _lastPushed;

  @visibleForTesting
  void resetForTest() => _lastPushed = null;

  /// Push today's workout from [overview] (null: the runner has no plan).
  Future<void> publish(ActivePlanOverview? overview, {DateTime? now}) async {
    final json = jsonEncode(buildWatchWorkoutPayload(
      overview,
      now ?? DateTime.now(),
    ));
    if (json == _lastPushed) return;
    final bool delivered;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        delivered = await _invoke(_wear, 'push', {
          'workout_json': json,
          'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
        });
      case TargetPlatform.iOS:
        delivered = await _invoke(_apple, 'push_workout', {
          'workout_json': json,
        });
      default:
        return;
    }
    if (delivered) _lastPushed = json;
  }

  Future<bool> _invoke(
    MethodChannel channel,
    String method,
    Map<String, Object> args,
  ) async {
    try {
      await channel.invokeMethod<void>(method, args);
      return true;
    } on MissingPluginException catch (e) {
      debugPrint('watch workout push has no native side: $e');
      return false;
    } on PlatformException catch (e) {
      // No paired watch, no Play services, or a refused payload: the phone
      // is unaffected either way.
      debugPrint('watch workout push refused: $e');
      return false;
    }
  }
}

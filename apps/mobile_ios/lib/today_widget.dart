import 'dart:async';
import 'dart:convert';

import 'package:core_models/core_models.dart' show DistanceUnit, PlanWorkoutRow;
import 'package:flutter/foundation.dart'
    show
        Listenable,
        TargetPlatform,
        debugPrint,
        defaultTargetPlatform,
        visibleForTesting;
import 'package:flutter/services.dart';

import 'l10n/gen/app_localizations.dart';
import 'l10n/locale_support.dart'
    show activeLocaleTag, defaultLocale, localeFromTag;
import 'preferences.dart' show UnitFormat, activeDistanceUnit;
import 'training.dart' show isWorkoutCompleted, toIsoDate, workoutKindFromDb;
import 'training_labels.dart' show workoutKindLabel;
import 'training_service.dart' show ActivePlanOverview;
import 'widgets/runner_menu.dart' show workoutCardSummary;

/// Version of the home-screen widget snapshot. A widget refuses any other
/// value and renders its stale state rather than guessing at the shape.
const int kTodayWidgetSnapshotVersion = 1;

/// How many local calendar days a snapshot carries, starting at the day it
/// is written, so the widget rolls over at midnight for a week without the
/// app running.
const int kTodayWidgetDays = 7;

/// Build the today's-workout snapshot both home-screen widgets render: the
/// Android `TodayWorkoutWidgetProvider` and the iOS `TodayWorkoutWidget`.
///
/// Dart owns locale and units, as it does for the Live Activity: every string
/// a widget shows arrives here already translated and unit-formatted, so
/// neither widget formats or translates anything of its own. The shape is the
/// contract in `fixtures/today_widget_snapshot.json`, which the Kotlin reader
/// is held to as well.
///
/// A null [overview] is a runner with no active plan: no `plan_id`, and every
/// day `none`.
Map<String, Object> buildTodayWidgetSnapshot(
  ActivePlanOverview? overview, {
  required DateTime now,
  required AppLocalizations l10n,
  required DistanceUnit unit,
}) {
  final days = <Map<String, Object>>[];
  for (var i = 0; i < kTodayWidgetDays; i++) {
    // Calendar arithmetic, not `add(Duration(days: i))`, so a DST change
    // inside the window cannot repeat or drop a date.
    final date = DateTime(now.year, now.month, now.day + i);
    days.add(_dayEntry(overview, date, l10n, unit));
  }
  return <String, Object>{
    'v': kTodayWidgetSnapshotVersion,
    'written_at_ms': now.millisecondsSinceEpoch,
    if (overview != null) 'plan_id': overview.plan.id,
    'labels': <String, Object>{
      'header': l10n.phoneSurfaceWidgetHeader,
      'no_plan': l10n.phoneSurfaceWidgetNoPlan,
      'no_plan_action': l10n.phoneSurfaceWidgetNoPlanAction,
      'nothing_scheduled': l10n.phoneSurfaceWidgetNothingScheduled,
      'stale': l10n.phoneSurfaceWidgetStale,
      'rest_day': l10n.phoneSurfaceWidgetRestDay,
      'done': l10n.phoneSurfaceWidgetDone,
      'skipped': l10n.phoneSurfaceWidgetSkipped,
    },
    'days': days,
  };
}

Map<String, Object> _dayEntry(
  ActivePlanOverview? overview,
  DateTime date,
  AppLocalizations l10n,
  DistanceUnit unit,
) {
  final iso = toIsoDate(date);
  final rows = overview == null
      ? const <PlanWorkoutRow>[]
      : overview.workouts
            .where((w) => toIsoDate(w.scheduledDate) == iso)
            .toList(growable: false);
  final sessions = rows.where((w) => w.kind != 'rest');
  // One entry per day. A day holding several sessions shows the one still
  // to do before one already done, and a done one before a skipped one: the
  // widget answers "what is left today".
  final open = sessions
      .where((w) => !isWorkoutCompleted(w) && w.skippedAt == null)
      .firstOrNull;
  final done = sessions.where(isWorkoutCompleted).firstOrNull;
  final skipped = sessions
      .where((w) => !isWorkoutCompleted(w) && w.skippedAt != null)
      .firstOrNull;
  final (state, workout) = open != null
      ? ('workout', open)
      : done != null
      ? ('done', done)
      : skipped != null
      ? ('skipped', skipped)
      : rows.isNotEmpty
      ? ('rest', null)
      : ('none', null);
  if (workout == null) {
    return <String, Object>{
      'date': iso,
      'state': state,
      'title': state == 'rest' ? l10n.phoneSurfaceWidgetRestDay : '',
      'detail': '',
    };
  }
  return <String, Object>{
    'date': iso,
    'state': state,
    'title': _title(workout, l10n),
    'detail': todayWidgetDetail(workout, l10n, unit),
    'plan_workout_id': workout.id,
  };
}

String _title(PlanWorkoutRow w, AppLocalizations l10n) {
  final race = w.raceName?.trim();
  if (w.kind == 'race' && race != null && race.isNotEmpty) return race;
  return workoutKindLabel(l10n, workoutKindFromDb(w.kind));
}

/// The session's size and pace on one line, "8.00 km · 4:45 /km": the
/// distance the runner menu's card shows (the plan's target, else the sum of
/// the distance steps), else the target duration, then the target pace.
@visibleForTesting
String todayWidgetDetail(
  PlanWorkoutRow w,
  AppLocalizations l10n,
  DistanceUnit unit,
) {
  final distance = workoutCardSummary(w).distanceMetres;
  final duration = w.targetDurationSeconds;
  final pace = w.targetPaceSecPerKm;
  return [
    if (distance != null)
      UnitFormat.distance(distance, unit)
    else if (duration != null && duration > 0)
      l10n.workoutSummaryMin((duration / 60).round()),
    if (pace != null && pace > 0)
      '${UnitFormat.pace(pace.toDouble(), unit)} ${UnitFormat.paceLabel(unit)}',
  ].join(' · ');
}

/// Keeps the home-screen widget holding the runner's next seven days.
///
/// Fed from the shell's plan-overview read (`home_screen.dart`), the same
/// read that feeds `WatchWorkoutBridge`, so a workout edited, moved, done or
/// skipped on the phone reaches the widget on the next read. A failed read
/// publishes nothing: the widget keeps its snapshot, which still covers the
/// week, and says it is stale once it no longer does.
///
/// Re-renders the last overview when the unit or locale changes
/// ([refreshOn]), since every string in the snapshot is already formatted.
/// Signing out [clear]s the snapshot, so the next account never sees the
/// last one's plan on the home screen.
///
/// An L4 effect: fire-and-forget, a missing or failing native side is logged
/// and left for the next read.
class TodayWidgetBridge {
  /// One instance per process, so the diff cache is shared by every caller.
  factory TodayWidgetBridge() => _instance;

  TodayWidgetBridge._();

  static final TodayWidgetBridge _instance = TodayWidgetBridge._();

  @visibleForTesting
  static const String channelName = 'run_app/home_widget';

  static const _channel = MethodChannel(channelName);

  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  ActivePlanOverview? _overview;
  bool _hasOverview = false;

  /// The last snapshot that reached the native side, minus its write stamp:
  /// a redraw the widget would render identically is not worth a write.
  String? _lastKey;

  @visibleForTesting
  void resetForTest() {
    _overview = null;
    _hasOverview = false;
    _lastKey = null;
    clock = DateTime.now;
  }

  bool get _supported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Publish the week from [overview] (null: the runner has no plan).
  Future<void> publish(ActivePlanOverview? overview, {DateTime? now}) async {
    _overview = overview;
    _hasOverview = true;
    if (!_supported) return;
    final Map<String, Object> snapshot;
    try {
      snapshot = buildTodayWidgetSnapshot(
        overview,
        now: now ?? clock(),
        l10n: lookupAppLocalizations(
          localeFromTag(activeLocaleTag) ?? defaultLocale,
        ),
        unit: activeDistanceUnit,
      );
    } catch (e) {
      debugPrint('today widget: snapshot not built: $e');
      return;
    }
    final key = jsonEncode(Map.of(snapshot)..remove('written_at_ms'));
    if (key == _lastKey) return;
    if (await _invoke('update', {'snapshot_json': jsonEncode(snapshot)})) {
      _lastKey = key;
    }
  }

  /// Re-publish the last overview, if one has been published since the last
  /// [clear].
  Future<void> refresh() async {
    if (_hasOverview) await publish(_overview);
  }

  /// Re-publish whenever [source] notifies: the unit preference and the
  /// locale, whose strings the snapshot carries.
  void refreshOn(Listenable source) {
    source.addListener(() => unawaited(refresh()));
  }

  /// Drop the snapshot (sign-out). The state is reset before the channel
  /// call, so a refresh racing the sign-out cannot republish the departing
  /// account's plan.
  Future<void> clear() async {
    _overview = null;
    _hasOverview = false;
    _lastKey = null;
    if (!_supported) return;
    await _invoke('clear', null);
  }

  Future<bool> _invoke(String method, Object? args) async {
    try {
      await _channel.invokeMethod<void>(method, args);
      return true;
    } on MissingPluginException catch (e) {
      debugPrint('today widget has no native side: $e');
      return false;
    } on PlatformException catch (e) {
      debugPrint('today widget refused $method: $e');
      return false;
    }
  }
}

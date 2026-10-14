import 'package:core_models/core_models.dart' show PlanWorkoutRow;
import 'package:flutter/material.dart';
import 'package:run_recorder/run_recorder.dart' show expandWorkoutSteps;

import '../l10n/gen/app_localizations.dart';
import '../training.dart' show toIsoDate, workoutKindFromDb;
import '../training_labels.dart' show workoutKindLabel;

/// What a long-press on the centre button can offer (decisions § R10MENU-1).
/// The tap already does one thing — start a run, or fan Run / Lift / Food —
/// so the long-press holds the rest: shortcuts into the recorder that would
/// otherwise cost a trip to its idle page, the manual entry web's Log run is,
/// and the modalities the tap leaves out.
enum RunnerMenuAction { todaysWorkout, followRoute, pastRun, lift, food }

/// The menu's items, in order. Pure so the per-state rules are tested without
/// pumping the shell.
///
/// [tapFans] is whether a tap on the button opens the capture fan, in which
/// case Lift and Food are already a tap away and are not repeated here. When
/// the tap starts a run instead, a shown modality is reachable from this
/// button only through the long-press, so it is listed. Every conditional item
/// is left out when it would land on nothing: no workout today, no saved
/// route.
List<RunnerMenuAction> runnerMenuActions({
  required bool tapFans,
  required bool hasTodaysWorkout,
  required bool hasRoutes,
  required bool gymShown,
  required bool nutritionShown,
}) =>
    [
      if (hasTodaysWorkout) RunnerMenuAction.todaysWorkout,
      if (hasRoutes) RunnerMenuAction.followRoute,
      RunnerMenuAction.pastRun,
      if (!tapFans && gymShown) RunnerMenuAction.lift,
      if (!tapFans && nutritionShown) RunnerMenuAction.food,
    ];

/// The plan workout a "Start today's workout" item would load, or null when
/// there is none worth offering. Read against [now] at menu time rather than
/// taken from a cached overview's `todayWorkout`, so a menu opened after
/// midnight does not offer yesterday's session.
///
/// A rest day, a workout already completed or skipped, and one with nothing
/// the runner could follow (no structure and no target distance, which the
/// recorder answers with "no structure") are all left out: each would open
/// the recorder onto a dead end.
PlanWorkoutRow? todaysOpenWorkout(
  Iterable<PlanWorkoutRow> workouts,
  DateTime now,
) {
  final today = toIsoDate(now);
  for (final w in workouts) {
    if (toIsoDate(w.scheduledDate) != today) continue;
    if (w.kind == 'rest') continue;
    if (w.completedRunId != null || w.manuallyCompleted) continue;
    if (w.skippedAt != null) continue;
    final structure = w.structure is Map<String, dynamic>
        ? w.structure as Map<String, dynamic>
        : null;
    final steps = expandWorkoutSteps(
      structure: structure,
      paces: const {},
      toleranceSecPerKm: w.targetPaceToleranceSec ?? 10,
      fallbackDistanceMetres: w.targetDistanceM,
      fallbackPaceSecPerKm: w.targetPaceSecPerKm,
    );
    if (steps.isEmpty) continue;
    return w;
  }
  return null;
}

/// The long-press menu: a bottom sheet of list rows rather than the tap's
/// arc. The arc holds three items, its labels wrap and ellipsise in the
/// longer locales, and it has no room to grow with the text size; a list row
/// does all three, and the bottom edge is where a thumb already is.
///
/// Resolves to the picked action, or null on dismiss. The caller (HomeScreen)
/// owns the navigation, as it does for the fan.
Future<RunnerMenuAction?> showRunnerMenu({
  required BuildContext context,
  required List<RunnerMenuAction> actions,
  PlanWorkoutRow? todaysWorkout,
}) {
  return showModalBottomSheet<RunnerMenuAction>(
    context: context,
    // Scroll-controlled so five rows at the largest text size scroll rather
    // than overflow the default 9/16 cap.
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        _RunnerMenu(actions: actions, todaysWorkout: todaysWorkout),
  );
}

class _RunnerMenu extends StatelessWidget {
  final List<RunnerMenuAction> actions;
  final PlanWorkoutRow? todaysWorkout;
  const _RunnerMenu({required this.actions, required this.todaysWorkout});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        // One focus group so a screen reader presents the rows as one menu,
        // as the Log sheet does.
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: l10n.logMoreTitle,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(l10n.logMoreTitle,
                    style: theme.textTheme.titleMedium),
              ),
              for (final a in actions) _tile(context, l10n, a),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(
      BuildContext context, AppLocalizations l10n, RunnerMenuAction a) {
    final workout = todaysWorkout;
    final (icon, label, subtitle) = switch (a) {
      RunnerMenuAction.todaysWorkout => (
          Icons.calendar_month,
          l10n.logMoreTodaysWorkout,
          workout == null
              ? null
              : workoutKindLabel(l10n, workoutKindFromDb(workout.kind)),
        ),
      RunnerMenuAction.followRoute => (Icons.route, l10n.runChooseRoute, null),
      RunnerMenuAction.pastRun => (Icons.history, l10n.historyAddPastRun, null),
      RunnerMenuAction.lift => (Icons.fitness_center, l10n.logLift, null),
      RunnerMenuAction.food => (Icons.restaurant, l10n.logFood, null),
    };
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: subtitle == null ? null : Text(subtitle),
      onTap: () => Navigator.of(context).pop(a),
    );
  }
}

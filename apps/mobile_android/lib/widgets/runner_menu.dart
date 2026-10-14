import 'package:core_models/core_models.dart' as cm;
import 'package:core_models/core_models.dart' show DistanceUnit, PlanWorkoutRow;
import 'package:flutter/material.dart';
import 'package:run_recorder/run_recorder.dart' show WorkoutStep, expandWorkoutSteps;

import '../l10n/gen/app_localizations.dart';
import '../preferences.dart' show UnitFormat;
import '../training.dart' show toIsoDate, workoutKindFromDb;
import '../training_labels.dart' show workoutKindLabel;

/// What a long-press on the centre button can offer (decisions § R10MENU-1).
/// The tap already does one thing — start a run, or fan Run / Lift / Food —
/// so the long-press holds the rest: shortcuts into the recorder that would
/// otherwise cost a trip to its idle page, the manual entry web's Log run is,
/// and the modalities the tap leaves out.
///
/// [followRoute] is the whole route section: the recent routes inline, and
/// "All routes…" when there are more than fit.
enum RunnerMenuAction { todaysWorkout, followRoute, pastRun, lift, food }

/// How many saved routes the sheet shows inline before "All routes…".
const int kRunnerMenuInlineRoutes = 3;

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
    if (_steps(w).isEmpty) continue;
    return w;
  }
  return null;
}

List<WorkoutStep> _steps(PlanWorkoutRow w) {
  final structure = w.structure is Map<String, dynamic>
      ? w.structure as Map<String, dynamic>
      : null;
  return expandWorkoutSteps(
    structure: structure,
    paces: const {},
    toleranceSecPerKm: w.targetPaceToleranceSec ?? 10,
    fallbackDistanceMetres: w.targetDistanceM,
    fallbackPaceSecPerKm: w.targetPaceSecPerKm,
  );
}

/// What the workout card says under the session's kind: its distance, and
/// its step count when it is more than one steady run. [distanceMetres] is
/// the plan's target when it sets one, else the sum of the distance-based
/// steps; null when neither gives a figure (an all-timed session).
({double? distanceMetres, int steps}) workoutCardSummary(PlanWorkoutRow w) {
  final steps = _steps(w);
  final target = w.targetDistanceM;
  if (target != null && target > 0) {
    return (distanceMetres: target, steps: steps.length);
  }
  final summed = steps
      .where((s) => !s.isDurationBased)
      .fold<double>(0, (sum, s) => sum + s.targetDistanceMetres);
  return (distanceMetres: summed > 0 ? summed : null, steps: steps.length);
}

/// The saved routes the sheet shows inline, most recently followed first.
///
/// The store's own list order is not recency — a cold start loads it in
/// directory order — so recency is read off the runs: a route's last run on
/// it, then, for routes never run, when the route was saved. Ties keep the
/// store's order.
List<cm.Route> recentRoutes(
  List<cm.Route> routes,
  Iterable<cm.Run> runs, {
  int limit = kRunnerMenuInlineRoutes,
}) {
  final lastRun = <String, DateTime>{};
  for (final r in runs) {
    final id = r.routeId;
    if (id == null) continue;
    final prev = lastRun[id];
    if (prev == null || r.startedAt.isAfter(prev)) lastRun[id] = r.startedAt;
  }
  final indexed = [for (var i = 0; i < routes.length; i++) (i, routes[i])];
  int byTime(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }

  indexed.sort((a, b) {
    final ra = lastRun[a.$2.id], rb = lastRun[b.$2.id];
    if ((ra == null) != (rb == null)) return ra == null ? 1 : -1;
    final c = ra != null
        ? byTime(ra, rb)
        : byTime(a.$2.createdAt, b.$2.createdAt);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed.take(limit)) e.$2];
}

/// What the sheet resolved to. A route picked inline carries the route, so
/// the caller starts the run on it without a second picker.
sealed class RunnerMenuChoice {
  const RunnerMenuChoice();
}

/// One of the sheet's items. [RunnerMenuAction.followRoute] here means
/// "All routes…": open the full picker.
final class RunnerMenuActionChoice extends RunnerMenuChoice {
  final RunnerMenuAction action;
  const RunnerMenuActionChoice(this.action);
}

/// An inline route: start the run following it.
final class RunnerMenuRouteChoice extends RunnerMenuChoice {
  final cm.Route route;
  const RunnerMenuRouteChoice(this.route);
}

/// The long-press menu: a "start options" sheet in the speed dial's visual
/// language (secondaryContainer tiles), rather than the tap's arc. The arc
/// holds three items and has no room to grow with the text size; a sheet
/// does, and the bottom edge is where a thumb already is.
///
/// [routes] are the inline routes, already chosen by [recentRoutes];
/// [hasMoreRoutes] adds "All routes…" for the rest. Resolves to the choice,
/// or null on dismiss. The caller (HomeScreen) owns the navigation, as it
/// does for the fan.
Future<RunnerMenuChoice?> showRunnerMenu({
  required BuildContext context,
  required List<RunnerMenuAction> actions,
  required DistanceUnit unit,
  PlanWorkoutRow? todaysWorkout,
  List<cm.Route> routes = const [],
  bool hasMoreRoutes = false,
}) {
  return showModalBottomSheet<RunnerMenuChoice>(
    context: context,
    // Scroll-controlled so the sheet at the largest text size scrolls rather
    // than overflow the default 9/16 cap.
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _RunnerMenu(
      actions: actions,
      unit: unit,
      todaysWorkout: todaysWorkout,
      routes: routes,
      hasMoreRoutes: hasMoreRoutes,
    ),
  );
}

class _RunnerMenu extends StatelessWidget {
  final List<RunnerMenuAction> actions;
  final DistanceUnit unit;
  final PlanWorkoutRow? todaysWorkout;
  final List<cm.Route> routes;
  final bool hasMoreRoutes;
  const _RunnerMenu({
    required this.actions,
    required this.unit,
    required this.todaysWorkout,
    required this.routes,
    required this.hasMoreRoutes,
  });

  void _pick(BuildContext context, RunnerMenuChoice c) =>
      Navigator.of(context).pop(c);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final workout = todaysWorkout;
    final secondary = [
      for (final a in actions)
        if (a == RunnerMenuAction.pastRun ||
            a == RunnerMenuAction.lift ||
            a == RunnerMenuAction.food)
          a,
    ];
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        // One focus group so a screen reader presents the sheet as one menu,
        // as the Log fan does.
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: l10n.logMoreTitle,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: Text(l10n.logMoreTitle,
                    style: theme.textTheme.titleMedium),
              ),
              if (workout != null &&
                  actions.contains(RunnerMenuAction.todaysWorkout))
                _WorkoutCard(
                  workout: workout,
                  unit: unit,
                  onTap: () => _pick(
                    context,
                    const RunnerMenuActionChoice(
                        RunnerMenuAction.todaysWorkout),
                  ),
                ),
              if (actions.contains(RunnerMenuAction.followRoute) &&
                  (routes.isNotEmpty || hasMoreRoutes)) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                  child: Text(
                    l10n.runnerMenuFollowRoute,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final r in routes)
                      _RouteChip(
                        route: r,
                        unit: unit,
                        onTap: () =>
                            _pick(context, RunnerMenuRouteChoice(r)),
                      ),
                    if (hasMoreRoutes)
                      _Tile(
                        icon: Icons.more_horiz,
                        label: l10n.runnerMenuAllRoutes,
                        onTap: () => _pick(
                          context,
                          const RunnerMenuActionChoice(
                              RunnerMenuAction.followRoute),
                        ),
                      ),
                  ],
                ),
              ],
              if (secondary.isNotEmpty) const SizedBox(height: 12),
              for (final a in secondary)
                _SecondaryRow(
                  icon: switch (a) {
                    RunnerMenuAction.lift => Icons.fitness_center,
                    RunnerMenuAction.food => Icons.restaurant,
                    _ => Icons.history,
                  },
                  label: switch (a) {
                    RunnerMenuAction.lift => l10n.logLift,
                    RunnerMenuAction.food => l10n.logFood,
                    _ => l10n.historyAddPastRun,
                  },
                  onTap: () => _pick(context, RunnerMenuActionChoice(a)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Today's workout: the session's kind and size, the whole card one tap.
class _WorkoutCard extends StatelessWidget {
  final PlanWorkoutRow workout;
  final DistanceUnit unit;
  final VoidCallback onTap;
  const _WorkoutCard({
    required this.workout,
    required this.unit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final kind = workoutKindLabel(l10n, workoutKindFromDb(workout.kind));
    final s = workoutCardSummary(workout);
    final summary = [
      if (s.distanceMetres != null) UnitFormat.distance(s.distanceMetres!, unit),
      if (s.steps > 1) l10n.runnerMenuWorkoutSteps(s.steps),
    ].join(' · ');
    final on = scheme.onSecondaryContainer;
    return Material(
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.calendar_month, color: on),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.logMoreTodaysWorkout,
                        style: text.labelMedium?.copyWith(color: on)),
                    Text(kind, style: text.titleMedium?.copyWith(color: on)),
                    if (summary.isNotEmpty)
                      Text(summary,
                          style: text.bodySmall?.copyWith(color: on)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Material(
                color: scheme.primary,
                shape: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(Icons.play_arrow, color: scheme.onPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An inline route: its name and length, one tap to start following it.
class _RouteChip extends StatelessWidget {
  final cm.Route route;
  final DistanceUnit unit;
  final VoidCallback onTap;
  const _RouteChip({
    required this.route,
    required this.unit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final distance = UnitFormat.distance(route.distanceMetres, unit);
    return Semantics(
      button: true,
      label: '${l10n.runnerMenuFollowRouteNamed(route.name)}, $distance',
      excludeSemantics: true,
      child: _Tile(
        icon: Icons.route,
        label: route.name,
        detail: distance,
        onTap: onTap,
      ),
    );
  }
}

/// A rounded secondaryContainer tile, the speed dial's chip grown a label
/// beside its icon. Capped at the sheet's width so a long route name wraps
/// to a second line and then ellipsises rather than overflowing.
class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? detail;
  final VoidCallback onTap;
  const _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final on = scheme.onSecondaryContainer;
    return LayoutBuilder(
      builder: (context, constraints) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: constraints.maxWidth),
        child: Material(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: on),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelLarge?.copyWith(color: on),
                        ),
                        if (detail != null)
                          Text(detail!,
                              style: text.bodySmall?.copyWith(color: on)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A quieter row for what is not a start: no container, the icon in the
/// surface's secondary tone.
class _SecondaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SecondaryRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Text(label,
                    style: Theme.of(context).textTheme.bodyLarge),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

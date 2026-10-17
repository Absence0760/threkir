import 'package:core_models/core_models.dart' show PlanWorkoutRow;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show AppIconSize;

import '../l10n/gen/app_localizations.dart';
import '../plan_current.dart';
import '../training.dart';
import '../training_labels.dart';
import 'plan_workout_status_style.dart';

/// Today's planned workout, on Home (the plan hero), the Run tab's idle state
/// and plan detail. On the Run tab it beats the last-run summary, which is
/// already behind the upcoming-event card in priority.
///
/// The fill is solid `primary` under `onPrimary`: a gradient into
/// `surfaceContainerHighest` left the white type at about 1.3:1 at the far
/// corner in light mode (WCAG 1.4.3), pinned in `contrast_guard_test.dart`.
///
/// [onStart] adds an explicit Start button, which is hidden once the workout
/// is done or skipped. Home passes none: its card opens plan detail, because
/// the dashboard's role is overview, not starting a run.
class TodaysWorkoutCard extends StatelessWidget {
  final PlanWorkoutRow workout;
  final VoidCallback? onTap;
  final VoidCallback? onStart;
  const TodaysWorkoutCard({
    super.key,
    required this.workout,
    this.onTap,
    this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final w = workout;
    final kind = workoutKindFromDb(w.kind);
    final done = isWorkoutCompleted(w);
    final skipped = !done && isWorkoutSkipped(w.skippedAt);
    final doneLook = planWorkoutStatusLook(
        theme,
        done
            ? PlanWorkoutStatus.done
            : skipped
                ? PlanWorkoutStatus.skipped
                : PlanWorkoutStatus.upcoming);
    final showStart = onStart != null && !done && !skipped;
    final pace = w.targetPaceSecPerKm == null
        ? null
        : l10n.todaysWorkoutAtPace(fmtPace(w.targetPaceSecPerKm));
    final label = [
      done ? l10n.todaysWorkoutDone : l10n.todaysWorkoutToday,
      workoutKindLabel(l10n, kind),
      if (w.targetDistanceM != null) fmtKm(w.targetDistanceM),
      ?pace,
    ].join(', ');

    final summary = Semantics(
      button: onTap != null,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.surface,
                ),
                child: Icon(
                  doneLook.glyph != null && (done || skipped)
                      ? doneLook.glyph
                      : _iconFor(kind),
                  color: done || skipped
                      ? doneLook.glyphColor
                      : theme.colorScheme.primary,
                  size: AppIconSize.material,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      done ? l10n.todaysWorkoutDone : l10n.todaysWorkoutToday,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        letterSpacing: 0.7,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      workoutKindLabel(l10n, kind),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 10,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (w.targetDistanceM != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.straighten,
                                size: 14,
                                color: theme.colorScheme.onPrimary,
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  fmtKm(w.targetDistanceM),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: theme.colorScheme.onPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        if (pace != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.speed,
                                size: 14,
                                color: theme.colorScheme.onPrimary,
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  pace,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: theme.colorScheme.onPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Material(
      color: theme.colorScheme.primary,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: showStart
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                summary,
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: FilledButton.icon(
                    key: const Key('todaysWorkoutStart'),
                    onPressed: onStart,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(l10n.workoutStart),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.onPrimary,
                      foregroundColor: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            )
          : summary,
    );
  }

  IconData _iconFor(WorkoutKind k) => switch (k) {
    WorkoutKind.easy || WorkoutKind.recovery => Icons.directions_walk,
    WorkoutKind.long => Icons.directions_run,
    WorkoutKind.tempo => Icons.speed,
    WorkoutKind.interval => Icons.timelapse,
    WorkoutKind.walkRun => Icons.directions_walk,
    WorkoutKind.marathonPace => Icons.flag_outlined,
    WorkoutKind.race => Icons.emoji_events,
    WorkoutKind.rest => Icons.self_improvement,
  };
}

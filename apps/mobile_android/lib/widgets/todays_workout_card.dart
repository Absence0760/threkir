import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../training.dart';
import '../training_labels.dart';
import '../training_service.dart';

/// Today's planned workout, on Home (the plan hero), the Run tab's idle state
/// and plan detail. On the Run tab it beats the last-run summary, which is
/// already behind the upcoming-event card in priority.
///
/// The fill is solid `primary` under `onPrimary`: a gradient into
/// `surfaceContainerHighest` left the white type at about 1.3:1 at the far
/// corner in light mode (WCAG 1.4.3), pinned in `contrast_guard_test.dart`.
class TodaysWorkoutCard extends StatelessWidget {
  final ActivePlanOverview overview;
  final VoidCallback? onTap;
  const TodaysWorkoutCard({super.key, required this.overview, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final w = overview.todayWorkout!;
    final kind = workoutKindFromDb(w.kind);
    final done = w.completedRunId != null || w.manuallyCompleted;

    return Material(
      color: theme.colorScheme.primary,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
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
                  done ? Icons.check_circle : _iconFor(kind),
                  color: theme.colorScheme.primary,
                  size: 24,
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
                        if (w.targetPaceSecPerKm != null)
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
                                  '@ ${fmtPace(w.targetPaceSecPerKm)}',
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

import 'package:core_models/core_models.dart' show PlanWorkoutRow;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show AppIconSize;

import '../l10n/gen/app_localizations.dart';
import '../training.dart' show isWorkoutCompleted, toIsoDate;
import '../walk_run_graduation.dart';

/// The couch-to-5K completion moment on plan detail: shown to the owner once
/// the plan's last walk-run session is done ([walkRunGraduation]), with the
/// next step. A header only; the finish-plan card may sit under it. Web twin:
/// `WalkRunGraduationCard.svelte`.
class WalkRunGraduationCard extends StatelessWidget {
  final WalkRunGraduation graduation;

  /// Opens the plan wizard on a 10K goal.
  final VoidCallback onTrainForTenK;

  const WalkRunGraduationCard({
    super.key,
    required this.graduation,
    required this.onTrainForTenK,
  });

  /// The graduation for a loaded plan's rows, or null.
  static WalkRunGraduation? fromRows(List<PlanWorkoutRow> workouts) =>
      walkRunGraduation([
        for (final w in workouts)
          GraduationWorkout(
            id: w.id,
            kind: w.kind,
            scheduledDate: toIsoDate(w.scheduledDate),
            done: isWorkoutCompleted(w),
            linkedRun: w.completedRunId != null,
            runDistanceM: structureRunDistanceM(w.structure),
          ),
      ]);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      key: const Key('walkRunGraduationCard'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(Icons.emoji_events_outlined,
                  size: AppIconSize.material,
                  color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.walkRunGraduationTitle,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    graduation.ranFiveK
                        ? l10n.walkRunGraduationBodyFiveK
                        : l10n.walkRunGraduationBodyFinished,
                    key: const Key('walkRunGraduationBody'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                  const SizedBox(height: 12),
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.walkRunGraduationNextTitle,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    key: const Key('walkRunGraduationTenK'),
                    onPressed: onTrainForTenK,
                    child: Text(l10n.walkRunGraduationTenK),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.walkRunGraduationKeepRunning,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

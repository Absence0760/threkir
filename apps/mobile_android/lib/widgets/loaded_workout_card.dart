import 'package:core_models/core_models.dart' show PlanWorkoutRow;
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../planned_size_label.dart';
import '../training.dart';
import '../training_labels.dart';

/// The plan workout the next run will execute, on the Run tab's idle screen.
/// The execution band only mounts once recording starts, so without this a
/// loaded workout was invisible before GO. The x unloads it without a
/// confirm: loading it again from the plan restores it.
class LoadedWorkoutCard extends StatelessWidget {
  final PlanWorkoutRow workout;
  final VoidCallback onUnload;

  const LoadedWorkoutCard({
    super.key,
    required this.workout,
    required this.onUnload,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final title = l10n.runWorkoutLoadedTitle(
        workoutKindLabel(l10n, workoutKindFromDb(workout.kind)));
    final size = plannedSizeLabel(l10n, workout);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
              child: Row(
                children: [
                  Icon(Icons.timelapse, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (size != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            size,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            key: const Key('runUnloadWorkout'),
            icon: const Icon(Icons.close),
            tooltip: l10n.runUnloadWorkoutTooltip,
            onPressed: onUnload,
          ),
        ],
      ),
    );
  }
}

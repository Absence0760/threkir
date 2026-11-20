import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

/// The big, short message the recording screen shows when a followed park
/// course's timing starts ("Timing started") or the board would now time the
/// run ("Finished! 8:42:10"), #1446. One line, the biggest text on the
/// screen, on the success colour so it reads at a glance mid-stride.
/// Screen readers hear it through the run screen's own announcement, so the
/// card adds no second one.
class CourseTimingCue extends StatelessWidget {
  const CourseTimingCue({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    final theme = Theme.of(context);
    return ExcludeSemantics(
      child: ListCard(
        key: const ValueKey('course-timing-cue'),
        color: semantic.success,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: semantic.onSuccess,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// The one line the finished summary shows when the runner stopped a park
/// course after its timing started and before the board would time it
/// (#1446): the run is kept, the course time is not.
class CourseStoppedShortNote extends StatelessWidget {
  const CourseStoppedShortNote({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      key: const ValueKey('course-stopped-short'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.info_outline, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Flexible(
          child: Text(message, style: theme.textTheme.bodyLarge),
        ),
      ],
    );
  }
}

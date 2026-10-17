import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';

import '../auth_error.dart';
import '../backend_timeout.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../plan_move.dart';
import '../training.dart';
import '../training_labels.dart';
import '../training_service.dart';

/// "Move to another day": the days [days] (from `workoutMoveDays`) as a
/// list, and a tap moves [workout] there through
/// [TrainingService.moveWorkout]. A day that already holds a workout says
/// what it swaps with, because the two trade days (decisions § 2073). Web
/// twin: the Day field in `WorkoutEditor.svelte`. Returns true once a move
/// was saved.
Future<bool> showWorkoutMoveSheet(
  BuildContext context, {
  required PlanWorkoutRow workout,
  required List<WorkoutMoveDay> days,
  required TrainingService training,
}) async {
  final moved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _WorkoutMoveSheet(
      workout: workout,
      days: days,
      training: training,
    ),
  );
  return moved == true;
}

class _WorkoutMoveSheet extends StatefulWidget {
  final PlanWorkoutRow workout;
  final List<WorkoutMoveDay> days;
  final TrainingService training;

  const _WorkoutMoveSheet({
    required this.workout,
    required this.days,
    required this.training,
  });

  @override
  State<_WorkoutMoveSheet> createState() => _WorkoutMoveSheetState();
}

class _WorkoutMoveSheetState extends State<_WorkoutMoveSheet> {
  String? _saving;
  String? _error;

  Future<void> _move(WorkoutMoveDay day) async {
    if (_saving != null) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _saving = day.date;
      _error = null;
    });
    try {
      await widget.training
          .moveWorkout(widget.workout.id, day.date)
          .timeout(kBackendLoadTimeout);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('workout move error: $e');
      if (mounted) {
        setState(() {
          _saving = null;
          _error = l10n.workoutMoveError(friendlyError(l10n, e));
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Semantics(
                header: true,
                child: Text(l10n.workoutMoveAction,
                    style: theme.textTheme.titleLarge),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(l10n.workoutMoveHint,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
            ),
            const SizedBox(height: 8),
            for (final day in widget.days)
              ListTile(
                key: Key('workoutMoveDay-${day.date}'),
                enabled: _saving == null,
                title: Text(formatDowDateShort(parseIsoDate(day.date), tag)),
                subtitle: day.occupant == null
                    ? null
                    : Text(l10n.workoutMoveSwapsWith(workoutKindLabel(
                        l10n, workoutKindFromDb(day.occupant!.kind)))),
                trailing: _saving == day.date
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: () => _move(day),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Semantics(
                  liveRegion: true,
                  child: Text(_error!,
                      style: TextStyle(color: theme.colorScheme.error)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

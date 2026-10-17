import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';

import '../auth_error.dart';
import '../goal_time.dart';
import '../l10n/gen/app_localizations.dart';
import '../plan_move.dart';
import '../plan_races.dart';
import '../training.dart';
import '../training_labels.dart';
import '../training_service.dart';
import '../typed_decimal.dart';
import 'full_screen_form.dart';
import 'workout_move_sheet.dart';

/// Full-screen dialog for inline editing of a planned workout's kind,
/// target distance, target pace, and notes, plus — on a `race` workout — the
/// race's name, A/B/C priority and goal time. The caller is responsible
/// for refreshing the plan view after the sheet returns. Presentation
/// goes through [showFullScreenForm], the shared create/edit-entity wrapper.
/// A non-empty [moveDays] (from `workoutMoveDays`) adds "Move to another
/// day", which opens [showWorkoutMoveSheet].
Future<bool> showWorkoutEditSheet(
  BuildContext context, {
  required PlanWorkoutRow workout,
  required TrainingService training,
  List<WorkoutMoveDay> moveDays = const [],
}) async {
  final formKey = GlobalKey<_WorkoutEditSheetState>();
  final ok = await showFullScreenForm<bool>(
    context,
    title: AppLocalizations.of(context).workoutEditTitle,
    isDirty: () => formKey.currentState?.isDirty ?? false,
    builder: (ctx) => _WorkoutEditSheet(
      key: formKey,
      workout: workout,
      training: training,
      moveDays: moveDays,
    ),
  );
  return ok == true;
}

class _WorkoutEditSheet extends StatefulWidget {
  final PlanWorkoutRow workout;
  final TrainingService training;
  final List<WorkoutMoveDay> moveDays;
  const _WorkoutEditSheet({
    super.key,
    required this.workout,
    required this.training,
    required this.moveDays,
  });

  @override
  State<_WorkoutEditSheet> createState() => _WorkoutEditSheetState();
}

class _WorkoutEditSheetState extends State<_WorkoutEditSheet> {
  late WorkoutKind _kind;
  late final TextEditingController _distanceCtl;
  late final TextEditingController _paceCtl;
  late final TextEditingController _notesCtl;
  late final TextEditingController _raceNameCtl;
  late final TextEditingController _raceGoalCtl;
  String? _racePriority;
  bool _saving = false;
  String? _distanceError;
  String? _paceError;
  String? _raceGoalError;
  String? _error;

  @override
  void initState() {
    super.initState();
    final w = widget.workout;
    _kind = workoutKindFromDb(w.kind);
    _distanceCtl = TextEditingController(
      text: w.targetDistanceM == null
          ? ''
          : (w.targetDistanceM! / 1000).toStringAsFixed(1),
    );
    _paceCtl = TextEditingController(
      text: w.targetPaceSecPerKm == null
          ? ''
          : _paceToEditText(w.targetPaceSecPerKm!),
    );
    _notesCtl = TextEditingController(text: w.notes ?? '');
    _raceNameCtl = TextEditingController(text: w.raceName ?? '');
    _raceGoalCtl = TextEditingController(
      text: w.kind != 'race' || w.targetDurationSeconds == null
          ? ''
          : formatRaceGoalTimeS(w.targetDurationSeconds!),
    );
    _racePriority =
        racePriorities.contains(w.racePriority) ? w.racePriority : null;
    _initialSnapshot = _snapshot();
  }

  late final String _initialSnapshot;

  String _snapshot() => [
        _kind.name,
        _distanceCtl.text,
        _paceCtl.text,
        _notesCtl.text,
        _raceNameCtl.text,
        _raceGoalCtl.text,
        _racePriority ?? '',
      ].join('\u0000');

  bool get isDirty => _snapshot() != _initialSnapshot;

  @override
  void dispose() {
    _distanceCtl.dispose();
    _paceCtl.dispose();
    _notesCtl.dispose();
    _raceNameCtl.dispose();
    _raceGoalCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // Heading lives in the host AppBar (showFullScreenForm).
    return FullScreenFormBody(
      children: [
          DropdownButtonFormField<WorkoutKind>(
            initialValue: _kind,
            decoration: InputDecoration(labelText: l10n.workoutEditKindLabel),
            items: [
              for (final k in WorkoutKind.values)
                DropdownMenuItem(value: k, child: Text(workoutKindLabel(l10n, k))),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _kind = v);
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _distanceCtl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.workoutEditDistanceLabel,
              hintText: l10n.workoutEditDistanceHint,
              errorText: _distanceError,
            ),
            onChanged: (_) {
              if (_distanceError != null) {
                setState(() => _distanceError = null);
              }
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _paceCtl,
            keyboardType: TextInputType.text,
            decoration: InputDecoration(
              labelText: l10n.workoutEditPaceLabel,
              hintText: l10n.workoutEditPaceHint,
              errorText: _paceError,
            ),
            onChanged: (_) {
              if (_paceError != null) {
                setState(() => _paceError = null);
              }
            },
          ),
          if (_kind == WorkoutKind.race) ..._raceFields(l10n),
          const SizedBox(height: 8),
          TextField(
            controller: _notesCtl,
            maxLines: 2,
            decoration: InputDecoration(labelText: l10n.workoutEditNotesLabel),
          ),
          if (widget.moveDays.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const Key('workoutEditMove'),
                onPressed: _saving ? null : _openMove,
                icon: const Icon(Icons.event_repeat),
                label: Text(l10n.workoutMoveAction),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).maybePop(false),
                  child: Text(l10n.workoutEditCancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.workoutEditSave),
                ),
              ),
            ],
          ),
        ],
      );
  }

  List<Widget> _raceFields(AppLocalizations l10n) => [
        const SizedBox(height: 8),
        TextField(
          key: const Key('workoutEditRaceName'),
          controller: _raceNameCtl,
          maxLength: 120,
          textCapitalization: TextCapitalization.words,
          decoration:
              InputDecoration(labelText: l10n.workoutEditRaceNameLabel),
        ),
        DropdownButtonFormField<String?>(
          key: const Key('workoutEditRacePriority'),
          initialValue: _racePriority,
          decoration:
              InputDecoration(labelText: l10n.workoutEditRacePriorityLabel),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(l10n.workoutEditRacePriorityAuto),
            ),
            for (final p in racePriorities)
              DropdownMenuItem<String?>(
                value: p,
                child: Text(racePriorityOptionLabel(l10n, p)),
              ),
          ],
          onChanged: (v) => setState(() => _racePriority = v),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('workoutEditRaceGoal'),
          controller: _raceGoalCtl,
          keyboardType: TextInputType.datetime,
          decoration: InputDecoration(
            labelText: l10n.workoutEditRaceGoalTimeLabel,
            hintText: l10n.workoutEditRaceGoalTimeHint,
            errorText: _raceGoalError,
          ),
          onChanged: (_) {
            if (_raceGoalError != null) {
              setState(() => _raceGoalError = null);
            }
          },
        ),
      ];

  /// The move saves on its own, so unsaved edits would be lost with the
  /// form; ask for them to be saved or discarded first.
  Future<void> _openMove() async {
    if (isDirty) {
      setState(() => _error = AppLocalizations.of(context).workoutMoveSaveFirst);
      return;
    }
    final moved = await showWorkoutMoveSheet(
      context,
      workout: widget.workout,
      days: widget.moveDays,
      training: widget.training,
    );
    if (moved && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    // Validate both targets in one pass so each invalid field is flagged
    // inline at once (sign_up_screen idiom).
    final distanceText = _distanceCtl.text.trim();
    double? distanceM;
    String? distanceError;
    if (distanceText.isNotEmpty) {
      final km = parseTypedDecimal(distanceText);
      if (km == null || km <= 0) {
        distanceError = l10n.workoutEditErrDistance;
      } else {
        distanceM = km * 1000;
      }
    }

    final paceText = _paceCtl.text.trim();
    int? paceSecPerKm;
    String? paceError;
    if (paceText.isNotEmpty) {
      paceSecPerKm = _parsePaceMmSs(paceText);
      if (paceSecPerKm == null) {
        paceError = l10n.workoutEditErrPace;
      }
    }

    final isRace = _kind == WorkoutKind.race;
    final goalText = _raceGoalCtl.text.trim();
    int? goalTimeSec;
    String? raceGoalError;
    if (isRace && goalText.isNotEmpty) {
      goalTimeSec = parseRaceGoalTimeS(goalText);
      if (goalTimeSec == null) raceGoalError = l10n.workoutEditErrRaceGoalTime;
    }

    setState(() {
      _distanceError = distanceError;
      _paceError = paceError;
      _raceGoalError = raceGoalError;
    });
    if (distanceError != null || paceError != null || raceGoalError != null) {
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.training.updateWorkout(
        widget.workout.id,
        kind: workoutKindDbValue(_kind),
        fromKind: widget.workout.kind,
        targetDistanceM: distanceM,
        targetPaceSecPerKm: paceSecPerKm,
        notes: _notesCtl.text.trim(),
        race: isRace
            ? (
                name: _raceNameCtl.text,
                priority: _racePriority,
                goalTimeSec: goalTimeSec,
              )
            : null,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('workout edit save error: $e');
      if (mounted) {
        setState(() {
          _saving = false;
          _error = l10n.workoutEditSaveError(friendlyError(l10n, e));
        });
      }
    }
  }

  static String _paceToEditText(int secPerKm) {
    final m = secPerKm ~/ 60;
    final s = secPerKm % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  static int? _parsePaceMmSs(String s) {
    final parts = s.split(':');
    if (parts.length != 2) return null;
    final m = int.tryParse(parts[0]);
    final sec = int.tryParse(parts[1]);
    if (m == null || sec == null || sec < 0 || sec >= 60 || m < 0) return null;
    final total = m * 60 + sec;
    if (total <= 0) return null;
    return total;
  }
}

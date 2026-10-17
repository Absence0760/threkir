import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../auth_error.dart';
import '../goal_time.dart';
import '../hr_prescription_flag.dart';
import '../l10n/gen/app_localizations.dart';
import '../plan_move.dart';
import '../plan_races.dart';
import '../preferences.dart' show activeDistanceUnit;
import '../training.dart';
import '../training_labels.dart';
import '../training_service.dart';
import '../typed_decimal.dart';
import '../workout_prescription.dart';
import 'full_screen_form.dart';
import 'workout_move_sheet.dart';

/// Full-screen dialog for inline editing of a planned workout's kind,
/// target distance, target pace (both in the runner's unit; empty clears),
/// and notes, plus — on a `race` workout — the
/// race's name, A/B/C priority and goal time. The caller is responsible
/// for refreshing the plan view after the sheet returns. Presentation
/// goes through [showFullScreenForm], the shared create/edit-entity wrapper.
/// A non-empty [moveDays] (from `workoutMoveDays`) adds "Move to another
/// day", which opens [showWorkoutMoveSheet]. Every non-rest workout also
/// takes an effort range (RPE), and a heart-rate range when [hrPrescription]
/// is on (null reads the deploy gate, decisions § 2087).
Future<bool> showWorkoutEditSheet(
  BuildContext context, {
  required PlanWorkoutRow workout,
  required TrainingService training,
  List<WorkoutMoveDay> moveDays = const [],
  bool? hrPrescription,
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
      hrPrescription: hrPrescription ?? hrPrescriptionGate,
    ),
  );
  return ok == true;
}

class _WorkoutEditSheet extends StatefulWidget {
  final PlanWorkoutRow workout;
  final TrainingService training;
  final List<WorkoutMoveDay> moveDays;
  final bool hrPrescription;
  const _WorkoutEditSheet({
    super.key,
    required this.workout,
    required this.training,
    required this.moveDays,
    required this.hrPrescription,
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
  late final TextEditingController _rpeMinCtl;
  late final TextEditingController _rpeMaxCtl;
  late final TextEditingController _hrMinCtl;
  late final TextEditingController _hrMaxCtl;
  String? _rpeError;
  String? _hrError;
  String? _racePriority;
  // Targets are typed and shown in the runner's unit and stored per km.
  late final bool _miles;
  late final String _initialDistanceText;
  late final String _initialPaceText;
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
    _miles = activeDistanceUnit == DistanceUnit.mi;
    _initialDistanceText = w.targetDistanceM == null
        ? ''
        : (w.targetDistanceM! / _metresPerUnit).toStringAsFixed(1);
    _initialPaceText = w.targetPaceSecPerKm == null
        ? ''
        : _paceToEditText((w.targetPaceSecPerKm! * _kmPerUnit).round());
    _distanceCtl = TextEditingController(text: _initialDistanceText);
    _paceCtl = TextEditingController(text: _initialPaceText);
    _notesCtl = TextEditingController(text: w.notes ?? '');
    _raceNameCtl = TextEditingController(text: w.raceName ?? '');
    _raceGoalCtl = TextEditingController(
      text: w.kind != 'race' || w.targetDurationSeconds == null
          ? ''
          : formatRaceGoalTimeS(w.targetDurationSeconds!),
    );
    _racePriority =
        racePriorities.contains(w.racePriority) ? w.racePriority : null;
    _rpeMinCtl = TextEditingController(text: w.targetRpeMin?.toString() ?? '');
    _rpeMaxCtl = TextEditingController(text: w.targetRpeMax?.toString() ?? '');
    _hrMinCtl = TextEditingController(text: w.targetHrMinBpm?.toString() ?? '');
    _hrMaxCtl = TextEditingController(text: w.targetHrMaxBpm?.toString() ?? '');
    _initialSnapshot = _snapshot();
  }

  late final String _initialSnapshot;

  double get _metresPerUnit => _miles ? 1609.344 : 1000;
  double get _kmPerUnit => _metresPerUnit / 1000;
  String get _unitLabel => _miles ? 'mi' : 'km';

  String _snapshot() => [
        _kind.name,
        _distanceCtl.text,
        _paceCtl.text,
        _notesCtl.text,
        _raceNameCtl.text,
        _raceGoalCtl.text,
        _racePriority ?? '',
        _rpeMinCtl.text,
        _rpeMaxCtl.text,
        _hrMinCtl.text,
        _hrMaxCtl.text,
      ].join('\u0000');

  bool get isDirty => _snapshot() != _initialSnapshot;

  @override
  void dispose() {
    _distanceCtl.dispose();
    _paceCtl.dispose();
    _notesCtl.dispose();
    _raceNameCtl.dispose();
    _raceGoalCtl.dispose();
    _rpeMinCtl.dispose();
    _rpeMaxCtl.dispose();
    _hrMinCtl.dispose();
    _hrMaxCtl.dispose();
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
            key: const Key('workoutEditDistance'),
            controller: _distanceCtl,
            enabled: _kind != WorkoutKind.rest,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.workoutEditDistanceLabel(_unitLabel),
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
            key: const Key('workoutEditPace'),
            controller: _paceCtl,
            enabled: _kind != WorkoutKind.rest,
            keyboardType: TextInputType.text,
            decoration: InputDecoration(
              labelText: l10n.workoutEditPaceLabel(_unitLabel),
              hintText: l10n.workoutEditPaceHint,
              errorText: _paceError,
            ),
            onChanged: (_) {
              if (_paceError != null) {
                setState(() => _paceError = null);
              }
            },
          ),
          if (_kind != WorkoutKind.rest) ..._targetRangeFields(l10n),
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

  Widget _rangeRow({
    required Key fromKey,
    required Key toKey,
    required TextEditingController fromCtl,
    required TextEditingController toCtl,
    required String fromLabel,
    required String toLabel,
    required String? error,
    required VoidCallback onEdit,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            key: fromKey,
            controller: fromCtl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: fromLabel, errorText: error),
            onChanged: (_) => onEdit(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            key: toKey,
            controller: toCtl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
                labelText: toLabel, errorText: error == null ? null : ''),
            onChanged: (_) => onEdit(),
          ),
        ),
      ],
    );
  }

  List<Widget> _targetRangeFields(AppLocalizations l10n) => [
        const SizedBox(height: 8),
        _rangeRow(
          fromKey: const Key('workoutEditRpeMin'),
          toKey: const Key('workoutEditRpeMax'),
          fromCtl: _rpeMinCtl,
          toCtl: _rpeMaxCtl,
          fromLabel: l10n.workoutEditRpeFromLabel,
          toLabel: l10n.workoutEditRpeToLabel,
          error: _rpeError,
          onEdit: () {
            if (_rpeError != null) setState(() => _rpeError = null);
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(l10n.workoutEditRpeHint,
              style: Theme.of(context).textTheme.bodySmall),
        ),
        if (widget.hrPrescription) ...[
          const SizedBox(height: 8),
          _rangeRow(
            fromKey: const Key('workoutEditHrMin'),
            toKey: const Key('workoutEditHrMax'),
            fromCtl: _hrMinCtl,
            toCtl: _hrMaxCtl,
            fromLabel: l10n.workoutEditHrFromLabel,
            toLabel: l10n.workoutEditHrToLabel,
            error: _hrError,
            onEdit: () {
              if (_hrError != null) setState(() => _hrError = null);
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(l10n.workoutEditHrHint,
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ];

  /// Read one end of a typed range: empty is an open end, anything that is
  /// not a number is refused as not whole.
  static ({bool ok, num? value}) _rangeEnd(String text) {
    final t = text.trim();
    if (t.isEmpty) return (ok: true, value: null);
    final v = num.tryParse(t.replaceAll(',', '.'));
    return v == null ? (ok: false, value: null) : (ok: true, value: v);
  }

  ParsedRange _parseRange(
      TextEditingController lo, TextEditingController hi, RangeBounds b) {
    final a = _rangeEnd(lo.text);
    final c = _rangeEnd(hi.text);
    if (!a.ok || !c.ok) return const ParsedRange.refused(RangeRefusal.notWhole);
    return parseTargetRange(a.value, c.value, b);
  }

  String? _rangeErrorText(
      AppLocalizations l10n, ParsedRange r, RangeBounds b) {
    if (r.ok) return null;
    return r.reason == RangeRefusal.reversed
        ? l10n.workoutEditErrRangeReversed
        : l10n.workoutEditErrRangeBounds(b.min, b.max);
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
    // An emptied field clears its target. A field left as it was keeps the
    // stored value: the text is rounded for display, and re-reading it
    // would nudge an untouched 8.05 km target to 8.1.
    final distanceText = _distanceCtl.text.trim();
    double? distanceM;
    String? distanceError;
    if (distanceText == _initialDistanceText) {
      distanceM = widget.workout.targetDistanceM;
    } else if (distanceText.isNotEmpty) {
      final v = parseTypedDecimal(distanceText);
      if (v == null || v <= 0) {
        distanceError = l10n.workoutEditErrDistance(_unitLabel);
      } else {
        distanceM = v * _metresPerUnit;
      }
    }

    final paceText = _paceCtl.text.trim();
    int? paceSecPerKm;
    String? paceError;
    if (paceText == _initialPaceText) {
      paceSecPerKm = widget.workout.targetPaceSecPerKm;
    } else if (paceText.isNotEmpty) {
      final perUnit = _parsePaceMmSs(paceText);
      if (perUnit == null) {
        paceError = l10n.workoutEditErrPace;
      } else {
        paceSecPerKm = (perUnit / _kmPerUnit).round();
      }
    }

    final isRest = _kind == WorkoutKind.rest;
    final rpe = _parseRange(_rpeMinCtl, _rpeMaxCtl, rpeBounds);
    final hr = _parseRange(_hrMinCtl, _hrMaxCtl, targetHrBounds);
    var rpeError = _rangeErrorText(l10n, rpe, rpeBounds);
    var hrError =
        widget.hrPrescription ? _rangeErrorText(l10n, hr, targetHrBounds) : null;

    // A rest day has no targets to validate: the patch clears them all.
    if (isRest) {
      distanceError = null;
      paceError = null;
      rpeError = null;
      hrError = null;
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
      _rpeError = rpeError;
      _hrError = hrError;
    });
    if (distanceError != null ||
        paceError != null ||
        raceGoalError != null ||
        rpeError != null ||
        hrError != null) {
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
        targets: (distanceM: distanceM, paceSecPerKm: paceSecPerKm),
        notes: _notesCtl.text.trim(),
        race: isRace
            ? (
                name: _raceNameCtl.text,
                priority: _racePriority,
                goalTimeSec: goalTimeSec,
              )
            : null,
        rpe: isRest ? null : (min: rpe.min, max: rpe.max),
        hr: isRest || !widget.hrPrescription
            ? null
            : (min: hr.min, max: hr.max),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('workout edit save error: $e');
      if (mounted) {
        final needsConsent = e is PostgrestException &&
            e.code == '42501' &&
            (hr.min != null || hr.max != null);
        setState(() {
          _saving = false;
          _error = needsConsent
              ? l10n.workoutEditErrHrNeedsConsent
              : l10n.workoutEditSaveError(friendlyError(l10n, e));
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

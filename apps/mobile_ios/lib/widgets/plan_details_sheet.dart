import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/gen/app_localizations.dart';
import '../plan_races.dart' show raceGoalMaxHours;

/// What the plan-details sheet hands back on Save.
class PlanDetailsEdit {
  final String name;
  final String? notes;
  final int daysPerWeek;
  final int? goalTimeSec;
  final List<String>? rules;

  const PlanDetailsEdit({
    required this.name,
    required this.notes,
    required this.daysPerWeek,
    required this.goalTimeSec,
    required this.rules,
  });
}

/// Edits a plan's name, days per week, goal time, notes and rules. Web twin:
/// `PlanMetaEditor.svelte`. Pops a [PlanDetailsEdit], or nothing on cancel;
/// the caller writes it, because a goal-time change re-derives paces.
Future<PlanDetailsEdit?> showPlanDetailsSheet(
    BuildContext context, TrainingPlanRow plan) {
  return showModalBottomSheet<PlanDetailsEdit>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _PlanDetailsSheet(plan: plan),
  );
}

class _PlanDetailsSheet extends StatefulWidget {
  final TrainingPlanRow plan;
  const _PlanDetailsSheet({required this.plan});

  @override
  State<_PlanDetailsSheet> createState() => _PlanDetailsSheetState();
}

class _PlanDetailsSheetState extends State<_PlanDetailsSheet> {
  late final _name = TextEditingController(text: widget.plan.name);
  late final _notes = TextEditingController(text: widget.plan.notes ?? '');
  late final _rules = TextEditingController(
    text: widget.plan.rules is List
        ? (widget.plan.rules as List).map((r) => '$r').join('\n')
        : '',
  );
  late final int? _goal = widget.plan.goalTimeSeconds;
  late final _hours =
      TextEditingController(text: _goal == null ? '' : '${_goal ~/ 3600}');
  late final _minutes = TextEditingController(
      text: _goal == null ? '' : '${(_goal % 3600) ~/ 60}');
  late final _seconds =
      TextEditingController(text: _goal == null ? '' : '${_goal % 60}');
  late int _days = widget.plan.daysPerWeek.clamp(3, 7);
  String? _nameError;
  String? _goalError;

  @override
  void dispose() {
    for (final c in [_name, _notes, _rules, _hours, _minutes, _seconds]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final l10n = AppLocalizations.of(context);
    final name = _name.text.trim();
    final parts = [_hours, _minutes, _seconds].map((c) => c.text.trim());
    int? goal;
    String? goalError;
    if (parts.any((p) => p.isNotEmpty)) {
      final h = int.tryParse(_hours.text.trim().isEmpty ? '0' : _hours.text.trim());
      final m =
          int.tryParse(_minutes.text.trim().isEmpty ? '0' : _minutes.text.trim());
      final s =
          int.tryParse(_seconds.text.trim().isEmpty ? '0' : _seconds.text.trim());
      if (h == null ||
          m == null ||
          s == null ||
          h > raceGoalMaxHours ||
          m > 59 ||
          s > 59 ||
          h * 3600 + m * 60 + s == 0) {
        goalError = l10n.planDetailGoalTimeInvalid;
      } else {
        goal = h * 3600 + m * 60 + s;
      }
    }
    setState(() {
      _nameError = name.isEmpty ? l10n.planNewNameRequired : null;
      _goalError = goalError;
    });
    if (_nameError != null || _goalError != null) return;
    final rules = _rules.text
        .split('\n')
        .map((r) => r.trim())
        .where((r) => r.isNotEmpty)
        .toList();
    Navigator.pop(
      context,
      PlanDetailsEdit(
        name: name,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        daysPerWeek: _days,
        goalTimeSec: goal,
        rules: rules.isEmpty ? null : rules,
      ),
    );
  }

  Widget _timeField(TextEditingController c, String label, Key key) =>
      Expanded(
        child: TextField(
          key: key,
          controller: c,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: label),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.planDetailEditDetails, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              key: const Key('planDetailsName'),
              controller: _name,
              maxLength: 120,
              decoration: InputDecoration(
                labelText: l10n.planNewNameLabel,
                errorText: _nameError,
              ),
            ),
            DropdownButtonFormField<int>(
              key: const Key('planDetailsDays'),
              initialValue: _days,
              decoration: InputDecoration(labelText: l10n.planNewDaysPerWeek),
              items: [
                for (var n = 3; n <= 7; n++)
                  DropdownMenuItem(
                      value: n, child: Text(l10n.planNewDaysOption(n))),
              ],
              onChanged: (v) => setState(() => _days = v ?? _days),
            ),
            const SizedBox(height: 16),
            Text(l10n.planNewGoalTimeSection, style: theme.textTheme.titleSmall),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _timeField(_hours, l10n.planNewHoursLabel,
                    const Key('planDetailsGoalHours')),
                const SizedBox(width: 8),
                _timeField(_minutes, l10n.planNewMinutesLabel,
                    const Key('planDetailsGoalMinutes')),
                const SizedBox(width: 8),
                _timeField(_seconds, l10n.planNewSecondsLabel,
                    const Key('planDetailsGoalSeconds')),
              ],
            ),
            if (_goalError != null) ...[
              const SizedBox(height: 4),
              Text(_goalError!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 4),
            Text(l10n.planDetailGoalTimeRepaceHint, style: muted),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLength: 500,
              maxLines: 2,
              decoration: InputDecoration(labelText: l10n.planDetailNotesLabel),
            ),
            TextField(
              controller: _rules,
              maxLines: 4,
              minLines: 2,
              decoration: InputDecoration(labelText: l10n.planDetailRulesLabel),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.commonCancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('planDetailsSave'),
                  onPressed: _save,
                  child: Text(l10n.planDetailSaveDetails),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

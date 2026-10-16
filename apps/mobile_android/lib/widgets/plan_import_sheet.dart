import 'package:flutter/material.dart';

import '../backend_timeout.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../plan_serialize.dart';
import '../training.dart';
import '../training_service.dart';
import 'plan_overlap_dialog.dart';

/// Opens the plan import sheet: paste a plan table (web's export, or a
/// coach's hand-built table in the same shape) or a JSON export, preview the
/// weeks and races it reads as, then create it. Resolves to the new plan's
/// id, or null when the runner backs out.
Future<String?> showPlanImportSheet(
  BuildContext context,
  TrainingService training,
) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => PlanImportSheet(training: training),
);

/// Days a week the imported plan trains on: the busiest week's non-rest
/// sessions, held to the 3–7 the plan row accepts.
int importedDaysPerWeek(GeneratedPlan plan) {
  var most = 0;
  for (final w in plan.weeks) {
    final n = w.workouts.where((wo) => wo.kind != WorkoutKind.rest).length;
    if (n > most) most = n;
  }
  return most.clamp(3, 7);
}

class PlanImportSheet extends StatefulWidget {
  final TrainingService training;
  const PlanImportSheet({super.key, required this.training});

  @override
  State<PlanImportSheet> createState() => _PlanImportSheetState();
}

class _PlanImportSheetState extends State<PlanImportSheet> {
  final _textCtl = TextEditingController();
  ParsedPlan? _parsed;
  String? _parseError;
  String? _createError;
  bool _creating = false;
  bool _checkingOverlap = false;

  @override
  void dispose() {
    _textCtl.dispose();
    super.dispose();
  }

  void _load() {
    final text = _textCtl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _createError = null;
      try {
        _parsed = text.startsWith('{')
            ? parsePlanJson(text)
            : parsePlanMarkdown(text);
        _parseError = null;
      } on PlanParseError catch (e) {
        _parsed = null;
        _parseError = e.message;
      }
    });
  }

  Future<void> _create() async {
    final parsed = _parsed;
    if (parsed == null || _creating || _checkingOverlap) return;
    final l10n = AppLocalizations.of(context);
    // The overlap lookup is a network read; Create stays disabled across it
    // so a second tap cannot start a second create.
    setState(() => _checkingOverlap = true);
    final action = await confirmPlanOverlap(
      context,
      widget.training,
      startIso: parsed.startDate,
      endIso: toIsoDate(parsed.generated.endDate),
    );
    if (!mounted) return;
    setState(() {
      _checkingOverlap = false;
      if (action != null) {
        _creating = true;
        _createError = null;
      }
    });
    if (action == null) return;
    try {
      final plan = await widget.training
          .createPlan(
            name: parsed.name,
            goalEvent: parsed.goalEvent,
            goalDistanceM: parsed.goalDistanceM,
            goalTimeSec: parsed.goalTimeSec,
            startDate: parseIsoDate(parsed.startDate),
            daysPerWeek: importedDaysPerWeek(parsed.generated),
            generated: parsed.generated,
            onOverlap: action,
          )
          .timeout(kBackendLoadTimeout);
      if (mounted) Navigator.of(context).pop(plan.id);
    } catch (e) {
      debugPrint('plan import create failed: $e');
      if (mounted) {
        setState(() {
          _creating = false;
          _createError =
              planOverlapErrorText(context, e) ?? l10n.planImportCreateFailed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final parsed = _parsed;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.planImportTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              l10n.planImportIntro,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('planImportText'),
              controller: _textCtl,
              minLines: 6,
              maxLines: 12,
              keyboardType: TextInputType.multiline,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                labelText: l10n.planImportPasteLabel,
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
                errorText: _parseError == null
                    ? null
                    : l10n.planImportParseError(_parseError!),
                errorMaxLines: 4,
              ),
              // The preview must always describe the text in the box, so an
              // edit after Load drops it until the runner loads again.
              onChanged: (_) {
                if (_parsed != null || _parseError != null) {
                  setState(() {
                    _parsed = null;
                    _parseError = null;
                  });
                }
              },
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                key: const Key('planImportLoad'),
                onPressed: _creating ? null : _load,
                child: Text(l10n.planImportLoad),
              ),
            ),
            if (parsed != null) ...[
              const SizedBox(height: 12),
              _Preview(plan: parsed),
              const SizedBox(height: 12),
              if (_createError != null) ...[
                Text(
                  _createError!,
                  key: const Key('planImportCreateError'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton(
                key: const Key('planImportCreate'),
                onPressed: _creating || _checkingOverlap ? null : _create,
                child: _creating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.planImportCreate),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  final ParsedPlan plan;
  const _Preview({required this.plan});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    final g = plan.generated;
    final workoutCount = g.weeks.fold<int>(0, (n, w) => n + w.workouts.length);
    final races = [
      for (final w in g.weeks)
        for (final wo in w.workouts)
          if (wo.kind == WorkoutKind.race) wo,
    ];
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Container(
      key: const Key('planImportPreview'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            plan.name,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.planImportPreviewDates(
              formatDateMed(parseIsoDate(plan.startDate), tag),
              formatDateMed(g.endDate, tag),
            ),
            style: muted,
          ),
          Text(
            l10n.planImportPreviewCounts(g.weeks.length, workoutCount),
            style: muted,
          ),
          const SizedBox(height: 8),
          for (final w in g.weeks)
            Text(
              l10n.planImportPreviewWeek(w.weekIndex + 1, w.workouts.length),
              style: theme.textTheme.bodySmall,
            ),
          if (races.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final r in races)
              Text(
                l10n.planImportPreviewRace(
                  r.raceName ?? l10n.planImportPreviewRaceUnnamed,
                  formatDateMed(r.scheduledDate, tag),
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

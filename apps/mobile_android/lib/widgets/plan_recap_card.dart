import 'package:core_models/core_models.dart' show PlanWorkoutRow, TrainingPlanRow;
import 'package:flutter/material.dart';

import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../plan_recap.dart';
import '../training.dart' show fmtHms, fmtKm, parseIsoDate, toIsoDate;
import '../training_service.dart';

/// The label of a `personal_records.distance` bracket; an unknown bracket
/// renders its raw key.
String planRecapBracketLabel(AppLocalizations l10n, String key) {
  switch (key) {
    case '1_mile':
      return l10n.planRecapBracketMile;
    case '5k':
      return l10n.planRecapBracket5k;
    case '8k':
      return l10n.planRecapBracket8k;
    case '10k':
      return l10n.planRecapBracket10k;
    case '12k':
      return l10n.planRecapBracket12k;
    case 'half_marathon':
      return l10n.planRecapBracketHalf;
    case 'marathon':
      return l10n.planRecapBracketMarathon;
    default:
      return key;
  }
}

/// The end-of-plan recap (issue #1186), for a plan the runner has filed as
/// completed: sessions, volume, long runs, the race and records set inside
/// the plan, and the next plan's start. Web twin: `PlanRecapCard.svelte`.
class PlanRecapCard extends StatefulWidget {
  final TrainingService training;
  final TrainingPlanRow plan;
  final List<PlanWorkoutRow> workouts;
  final DateTime now;

  /// Opens the new-plan wizard on [startIso], seeded with [seed5kSec].
  final void Function(String startIso, int? seed5kSec) onBuildNext;

  const PlanRecapCard({
    super.key,
    required this.training,
    required this.plan,
    required this.workouts,
    required this.now,
    required this.onBuildNext,
  });

  /// Whether the plan detail shows the recap: the owner's own completed plan.
  static bool shows({required String status, required bool isTemplate}) =>
      status == 'completed' && !isTemplate;

  @override
  State<PlanRecapCard> createState() => _PlanRecapCardState();
}

class _PlanRecapCardState extends State<PlanRecapCard> {
  ({List<PlanRecapRun> runs, List<PlanRecapRecord> records})? _sources;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_failed) setState(() => _failed = false);
    try {
      final sources = await widget.training.fetchPlanRecapSources(
        toIsoDate(widget.plan.startDate),
        toIsoDate(widget.plan.endDate),
      );
      if (mounted) setState(() => _sources = sources);
    } catch (e) {
      // L4: the plan page stands without its recap.
      debugPrint('fetchPlanRecapSources failed: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  PlanRecap? get _recap {
    final s = _sources;
    if (s == null) return null;
    final p = widget.plan;
    return assemblePlanRecap(
      plan: RecapPlan(
        startDate: toIsoDate(p.startDate),
        endDate: toIsoDate(p.endDate),
        goalDistanceM: p.goalDistanceM,
        goalTimeSeconds: p.goalTimeSeconds,
        trimmedAt: p.trimmedAt,
      ),
      workouts: [for (final w in widget.workouts) RecapWorkout.fromRow(w)],
      runs: s.runs,
      records: s.records,
      todayIso: toIsoDate(widget.now),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    final recap = _recap;
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    final List<Widget> body;
    if (_failed) {
      body = [
        Text(l10n.planRecapLoadFailed,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.error)),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('planRecapRetry'),
          onPressed: _load,
          child: Text(l10n.planRecapRetry),
        ),
      ];
    } else if (recap == null) {
      body = [Text(l10n.planRecapLoading, style: muted)];
    } else {
      body = _stats(theme, l10n, tag, recap, muted);
    }

    return Card(
      key: const Key('planRecapCard'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flag_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      l10n.planRecapTitle(widget.plan.name),
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...body,
          ],
        ),
      ),
    );
  }

  String _time(AppLocalizations l10n, double sec) {
    final total = (sec / 60).round();
    return l10n.planRecapTimeValue(total ~/ 60, total % 60);
  }

  Widget _stat(ThemeData theme, String label, String value, List<String> notes,
      TextStyle? muted, Key key) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: muted),
          Text(value,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600)),
          for (final n in notes) Text(n, style: muted),
        ],
      ),
    );
  }

  List<Widget> _stats(ThemeData theme, AppLocalizations l10n, String tag,
      PlanRecap recap, TextStyle? muted) {
    final sessions = recap.sessions;
    final volume = recap.volume;
    final longRuns = recap.longRuns;
    final race = recap.race;
    final isTime = volume.basis == RecapVolumeBasis.time;
    String fmtVolume(double v) => isTime ? _time(l10n, v) : fmtKm(v);

    final longNotes = <String>[
      if (longRuns.first != null &&
          longRuns.longest != null &&
          longRuns.longest! > longRuns.first!)
        l10n.planRecapLongRunsRange(
            fmtKm(longRuns.first), fmtKm(longRuns.longest))
      else if (longRuns.longest != null)
        l10n.planRecapLongRunsLongest(fmtKm(longRuns.longest)),
    ];

    String? raceValue;
    final raceNotes = <String>[];
    if (race != null) {
      final run = race.run;
      if (run != null) {
        raceValue = run.isDnf
            ? l10n.planRecapRaceDnf
            : l10n.planRecapRaceRun(fmtHms(run.durationS), fmtKm(run.distanceM));
        if (race.vdot != null) {
          raceNotes.add(l10n.metricVdotValue(race.vdot!.toStringAsFixed(1)));
        }
      } else {
        raceValue =
            race.raced ? l10n.planRecapRaceNoRun : l10n.planRecapRaceNotRun;
      }
    }

    final next = recap.next;
    final nextStart = formatDateMed(parseIsoDate(next.startIso), tag);
    return [
      _stat(
        theme,
        l10n.planRecapSessionsLabel,
        l10n.planRecapSessionsValue(sessions.completed, sessions.total),
        [
          l10n.planRecapSessionsPct(sessions.pct),
          if (sessions.missed > 0) l10n.planRecapMissed(sessions.missed),
          if (sessions.skipped > 0) l10n.planRecapSkipped(sessions.skipped),
        ],
        muted,
        const Key('planRecapSessions'),
      ),
      _stat(
        theme,
        isTime ? l10n.planRecapTimeLabel : l10n.planRecapDistanceLabel,
        l10n.planRecapVolumeValue(
            fmtVolume(volume.done), fmtVolume(volume.planned)),
        const [],
        muted,
        const Key('planRecapVolume'),
      ),
      if (longRuns.planned > 0)
        _stat(
          theme,
          l10n.planRecapLongRunsLabel,
          l10n.planRecapSessionsValue(longRuns.done, longRuns.planned),
          longNotes,
          muted,
          const Key('planRecapLongRuns'),
        ),
      if (race != null && raceValue != null)
        _stat(
          theme,
          '${race.name ?? l10n.planRecapRaceLabel} · '
              '${formatDateShort(parseIsoDate(race.date), tag)}',
          raceValue,
          raceNotes,
          muted,
          const Key('planRecapRace'),
        ),
      const SizedBox(height: 4),
      Text(l10n.planRecapRecordsLabel,
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      if (recap.records.isEmpty)
        Text(l10n.planRecapRecordsNone,
            key: const Key('planRecapNoRecords'), style: muted)
      else
        for (final r in recap.records)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(Icons.emoji_events_outlined,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${planRecapBracketLabel(l10n, r.distance)}  '
                    '${fmtHms(r.timeS)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Text(formatDateShort(parseIsoDate(r.date), tag), style: muted),
              ],
            ),
          ),
      const SizedBox(height: 12),
      Text(l10n.planRecapNextTitle,
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      if (next.recovery case final recovery?)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            l10n.planRecapRecovery(recovery.days,
                formatDateMed(parseIsoDate(recovery.untilIso), tag)),
            key: const Key('planRecapRecovery'),
          ),
        ),
      Text(next.seed5kSec != null
          ? l10n.planRecapNextPlanSeeded(nextStart, fmtHms(next.seed5kSec))
          : l10n.planRecapNextPlan(nextStart)),
      const SizedBox(height: 8),
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: FilledButton.icon(
          key: const Key('planRecapNextPlan'),
          onPressed: () => widget.onBuildNext(next.startIso, next.seed5kSec),
          icon: const Icon(Icons.arrow_forward),
          label: Text(l10n.planRecapNextPlanCta),
        ),
      ),
    ];
  }
}

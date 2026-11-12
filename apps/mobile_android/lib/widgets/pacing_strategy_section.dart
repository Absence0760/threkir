import 'package:core_models/core_models.dart' show DistanceUnit, Waypoint;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show AppSemanticColors, StatusPill;

import '../goal_time.dart' show formatGoalTimeS;
import '../l10n/gen/app_localizations.dart';
import '../preferences.dart' show UnitFormat;
import '../race_phases.dart';

/// Post-run review of the race strategy the run was executed under. Reads
/// `runs.metadata.pacing_strategy` (registered in `docs/backend/metadata.md`),
/// grades the recorded track against it with [gradePhases], and renders one
/// row per phase. Hidden when the run carries no strategy, or one whose preset
/// this build does not know.
///
/// Mirrors the web `/runs/[id]` "Pacing strategy" section (decisions § 1915).
class PacingStrategySection extends StatelessWidget {
  final Map<String, dynamic>? metadata;
  final List<Waypoint> track;
  final DistanceUnit unit;
  const PacingStrategySection({
    super.key,
    required this.metadata,
    required this.track,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final strategy = parsePacingStrategy(metadata?['pacing_strategy']);
    if (strategy == null) return const SizedBox.shrink();
    final review = gradePhases(track, strategy);

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final noteStyle = theme.textTheme.bodySmall?.copyWith(color: muted);
    final goal = strategy.goalTimeS;
    final subtitle = [
      _presetLabel(l10n, strategy.preset),
      UnitFormat.distance(strategy.distanceM, unit),
      if (goal != null) l10n.runDetailStrategyGoal(formatGoalTimeS(goal.round())),
    ].join(' · ');

    final notes = <String>[
      if (review.ungradedReason == PhaseUngradedReason.noTrack)
        l10n.runDetailStrategyNoTrack
      else if (review.ungradedReason == PhaseUngradedReason.noGoal)
        l10n.runDetailStrategyNoGoal
      else ...[
        if (!review.completed)
          l10n.runDetailStrategyStoppedShort(
            UnitFormat.distance(review.trackDistanceM, unit),
            UnitFormat.distance(strategy.distanceM, unit),
          ),
        if (review.basis == PhaseTargetBasis.average)
          l10n.runDetailStrategyAverageBasis,
        l10n.runDetailStrategyBand,
      ],
    ];

    return Column(
      key: const Key('pacing-strategy-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(l10n.runDetailStrategyTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium),
              ),
              if (review.verdict != PhaseReviewVerdict.ungraded)
                _VerdictPill(verdict: review.verdict),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(subtitle, style: noteStyle),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                _headerRow(theme, l10n),
                for (var i = 0; i < review.phases.length; i++)
                  _phaseRow(theme, l10n, review, review.phases[i],
                      last: i == review.phases.length - 1),
              ],
            ),
          ),
        ),
        for (final note in notes)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(note, style: noteStyle),
          ),
        const SizedBox(height: 12),
        const Divider(),
      ],
    );
  }

  Widget _headerRow(ThemeData theme, AppLocalizations l10n) {
    final outline = theme.colorScheme.onSurfaceVariant;
    Widget cell(String label, {int flex = 1, TextAlign align = TextAlign.start}) {
      return Expanded(
        flex: flex,
        child: Text(
          label.toUpperCase(),
          textAlign: align,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: outline,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          cell(l10n.runDetailStrategyColPhase, flex: 3),
          cell(l10n.runDetailStrategyColTarget, flex: 2, align: TextAlign.right),
          cell(l10n.workoutReviewColActual, flex: 2, align: TextAlign.right),
          cell(l10n.workoutReviewColDelta, flex: 2, align: TextAlign.right),
        ],
      ),
    );
  }

  Widget _phaseRow(ThemeData theme, AppLocalizations l10n, PhaseReview review,
      PhaseResult p,
      {required bool last}) {
    final muted = theme.colorScheme.onSurfaceVariant;
    final semantic = AppSemanticColors.ofTheme(theme);
    final unreached = p.coverage == PhaseCoverage.notReached;
    final range =
        '${UnitFormat.distance(p.startM, unit)}–${UnitFormat.distance(p.endM, unit)}'
        '${p.coverage == PhaseCoverage.partial ? ' · ${l10n.runDetailStrategyPartial}' : ''}';

    String pace(int? secPerKm) => secPerKm == null
        ? '—'
        : '${UnitFormat.pace(secPerKm.toDouble(), unit)} ${UnitFormat.paceLabel(unit)}';
    final actual = p.actualPaceSecPerKm != null
        ? pace(p.actualPaceSecPerKm)
        : unreached && review.ungradedReason != PhaseUngradedReason.noTrack
            ? l10n.runDetailStrategyNotReached
            : '—';
    final gapColor = switch (p.grade) {
      null => muted,
      PhaseGrade.onTarget => semantic.success,
      PhaseGrade.fast || PhaseGrade.slow => semantic.warning,
    };

    Widget cell(String text, {int flex = 2, Color? color, FontWeight? weight}) {
      return Expanded(
        flex: flex,
        child: Text(
          text,
          textAlign: TextAlign.right,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: color ?? (unreached ? muted : null),
            fontWeight: weight,
          ),
        ),
      );
    }

    return Container(
      key: Key('pacing-strategy-phase-${p.intent.wire}'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border(
            bottom: last ? BorderSide.none : BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_intentLabel(l10n, p.intent),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: unreached ? muted : null,
                    )),
                Text(range,
                    maxLines: 2,
                    style: theme.textTheme.labelSmall?.copyWith(color: muted)),
              ],
            ),
          ),
          cell(pace(p.targetPaceSecPerKm)),
          cell(actual),
          cell(_gapLabel(l10n, p), color: gapColor, weight: FontWeight.w700),
        ],
      ),
    );
  }

  /// Same per-unit conversion as the workout table's delta: the pace cells
  /// beside it read per preferred unit, so the seconds must too.
  String _gapLabel(AppLocalizations l10n, PhaseResult p) {
    final gap = p.gapSecPerKm;
    if (gap == null) return '—';
    const metresPerMile = 1609.344;
    final d = unit == DistanceUnit.mi ? gap * (metresPerMile / 1000) : gap.toDouble();
    final r = d.round();
    if (r == 0) return l10n.runDetailStrategyOnPace;
    return '${r > 0 ? '+' : '−'}${r.abs()}s';
  }
}

String _presetLabel(AppLocalizations l10n, RacePhasePreset p) => switch (p) {
      RacePhasePreset.tenTenTen => l10n.runStrategyTenTenTen,
      RacePhasePreset.negativeSplit => l10n.runStrategyNegativeSplit,
      RacePhasePreset.even => l10n.runStrategyEven,
    };

String _intentLabel(AppLocalizations l10n, RacePhaseIntent i) => switch (i) {
      RacePhaseIntent.holdBack => l10n.phaseIntentHoldBack,
      RacePhaseIntent.settle => l10n.phaseIntentSettle,
      RacePhaseIntent.race => l10n.phaseIntentRace,
      RacePhaseIntent.even => l10n.phaseIntentEven,
    };

class _VerdictPill extends StatelessWidget {
  final PhaseReviewVerdict verdict;
  const _VerdictPill({required this.verdict});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final l10n = AppLocalizations.of(context);
    final (label, fill, fg) = switch (verdict) {
      PhaseReviewVerdict.onPlan => (
          l10n.runDetailStrategyVerdictOnPlan,
          semantic.success,
          semantic.onSuccess
        ),
      PhaseReviewVerdict.negativeSplit => (
          l10n.runDetailStrategyVerdictNegativeSplit,
          semantic.success,
          semantic.onSuccess
        ),
      PhaseReviewVerdict.fasterThanPlan => (
          l10n.runDetailStrategyVerdictFasterThanPlan,
          theme.colorScheme.surfaceContainerHighest,
          theme.colorScheme.onSurfaceVariant
        ),
      PhaseReviewVerdict.wentOutTooFast => (
          l10n.runDetailStrategyVerdictWentOutTooFast,
          semantic.warning,
          semantic.onWarning
        ),
      PhaseReviewVerdict.faded => (
          l10n.runDetailStrategyVerdictFaded,
          semantic.warning,
          semantic.onWarning
        ),
      PhaseReviewVerdict.slowerThanPlan => (
          l10n.runDetailStrategyVerdictSlowerThanPlan,
          semantic.warning,
          semantic.onWarning
        ),
      PhaseReviewVerdict.ungraded => (
          '',
          theme.colorScheme.surfaceContainerHighest,
          theme.colorScheme.onSurfaceVariant
        ),
    };
    return StatusPill(label: label, foreground: fg, fill: fill);
  }
}

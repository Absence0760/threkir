import 'package:core_models/core_models.dart' show Waypoint;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart'
    show AppInsets, AppSpace, ListCard, TermValueRow;

import '../l10n/gen/app_localizations.dart';
import '../race_match.dart';
import '../race_service.dart';
import '../screens/races_screen.dart' show showRaceImportSheet;
import 'top_banner.dart';

/// Run-detail race section (race_calendar.md). Owner-only. When the run already
/// carries an official result it renders it; otherwise it runs the inform-tier
/// auto-match check — a listing on the run's day that its start, distance or
/// course also agrees with ([bestRaceMatch]) surfaces a non-blocking "Was this
/// the {race}?" prompt that never writes without a tap.
///
/// Layered-resilience: every fetch is best-effort + swallowed (an L4 auxiliary
/// effect) so a race lookup can never break the rest of run detail.
class RunRaceSection extends StatefulWidget {
  final RaceService service;
  final String runId;
  final String startedAt;
  final double? distanceM;

  /// The run's stored track, read for its start point and for whether it
  /// crossed a candidate course's timing lines.
  final List<Waypoint>? track;

  const RunRaceSection({
    super.key,
    required this.service,
    required this.runId,
    required this.startedAt,
    required this.distanceM,
    this.track,
  });

  @override
  State<RunRaceSection> createState() => _RunRaceSectionState();
}

class _RunRaceSectionState extends State<RunRaceSection> {
  bool _loading = true;
  RaceResultForRun? _result;
  RaceListingView? _candidate;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await widget.service.fetchRaceResultForRun(widget.runId);
      RaceListingView? candidate;
      if (result == null || !result.hasResult) {
        try {
          final fixes = raceMatchFixes(widget.track);
          final listings = await widget.service.findRaceMatchCandidates(
            widget.startedAt,
            start: fixes.isEmpty ? null : fixes.first,
          );
          candidate = bestRaceMatch(
            RunMatchInput(
              startedAt: widget.startedAt,
              distanceM: widget.distanceM,
              track: fixes,
            ),
            listings,
            (c) => c.match,
          )?.listing;
        } catch (e, s) {
          debugPrint('RunRaceSection race match failed: $e\n$s');
          candidate = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _result = result;
        _candidate = candidate;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmMatch() async {
    final candidate = _candidate;
    if (candidate == null) return;
    final done = await showRaceImportSheet(
      context,
      service: widget.service,
      race: candidate,
      matchRunId: widget.runId,
    );
    if (done == true && mounted) {
      showTopBanner(context, AppLocalizations.of(context).racesImported);
      setState(() => _candidate = null);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final result = _result;
    if (result != null && result.hasResult) {
      final rows = <Widget>[
        if (result.raceName != null) _row(l.racesTitle, result.raceName!),
        if (result.chipTime != null) _row(l.racesChipTime, result.chipTime!),
        if (result.gunTime != null) _row(l.racesGunTime, result.gunTime!),
        if (result.overallPlace != null)
          _row(l.racesOverallPlace, '${result.overallPlace}'),
        if (result.ageGroupPlace != null)
          _row(
            l.racesAgeGroupPlace,
            result.ageGroup != null
                ? '${result.ageGroupPlace} (${result.ageGroup})'
                : '${result.ageGroupPlace}',
          ),
        if (result.divisionAwardPlace != null && result.divisionAward != null)
          _row(
            l.racesDivisionAwardPlace,
            '${result.divisionAwardPlace} (${result.divisionAward})',
          ),
        if (result.bib != null) _row(l.racesBib, result.bib!),
      ];
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.racesOfficialResult, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ...rows,
          ],
        ),
      );
    }

    final candidate = _candidate;
    if (candidate != null && !_dismissed) {
      return ListCard(
        margin: const EdgeInsets.fromLTRB(AppInsets.gutter, AppSpace.smPlus,
          AppInsets.gutter, AppSpace.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.racesMatchPrompt(candidate.name)),
            const SizedBox(height: 8),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => setState(() => _dismissed = true),
                  child: Text(l.racesMatchDismiss),
                ),
                FilledButton(
                  onPressed: _confirmMatch,
                  child: Text(l.racesMatchConfirm),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  /// A result line: the term and its value share a line while they fit,
  /// and the value drops under the term when not, so the place the runner
  /// came for is never the part that is cut (#1374 TO-5).
  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: TermValueRow(term: label, value: value),
      );
}

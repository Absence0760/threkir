import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../backend_timeout.dart';
import '../l10n/gen/app_localizations.dart';
import '../preferences.dart' show UnitFormat;
import '../screens/park_courses_screen.dart';
import 'single_flight.dart';
import 'top_banner.dart';

/// The owner's park courses on run detail that the run started but got no
/// time on, one card each saying which rule it missed and how far along it
/// got, opening the course. The same words as web run detail.
/// Nothing while loading, for a run with no attempt, or signed out; a failed
/// read leaves the section out, so run detail never depends on it.
class RunParkCourseAttempts extends StatefulWidget {
  final ApiClient api;
  final String runId;
  final DistanceUnit unit;

  const RunParkCourseAttempts({
    super.key,
    required this.api,
    required this.runId,
    required this.unit,
  });

  @override
  State<RunParkCourseAttempts> createState() => _RunParkCourseAttemptsState();
}

class _RunParkCourseAttemptsState extends State<RunParkCourseAttempts> {
  List<ParkCourseAttempt> _attempts = const [];
  final _opening = SingleFlight();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.api.userId == null) return;
    try {
      final rows = await widget.api
          .fetchParkCourseAttempts(widget.runId)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() => _attempts = rows);
    } catch (e) {
      debugPrint('run park course attempts: read failed: $e');
    }
  }

  Future<void> _open(ParkCourseAttempt a) => _opening.openOnce(() async {
    try {
      final found = await widget.api
          .fetchParkCourseBySlugs(a.parkSlug, a.courseSlug)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      if (found == null) {
        showTopBanner(
          context,
          AppLocalizations.of(context).runDetailParkCourseOpenFailed,
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ParkCourseScreen(
            api: widget.api,
            listing: found.park,
            course: found.course,
          ),
        ),
      );
    } catch (e) {
      debugPrint('run park course attempts: open failed: $e');
      if (!mounted) return;
      showTopBanner(
        context,
        AppLocalizations.of(context).runDetailParkCourseOpenFailed,
      );
    }
  });

  @override
  Widget build(BuildContext context) => ParkCourseAttemptCards(
    attempts: _attempts,
    unit: widget.unit,
    onOpen: _open,
  );
}

/// One card per attempt: the sentence saying why there is no time, then a bar
/// of how far along the course the run got with "2.10 km of 5.00 km" under
/// it. The reason is always words, never a colour.
class ParkCourseAttemptCards extends StatelessWidget {
  final List<ParkCourseAttempt> attempts;
  final DistanceUnit unit;
  final void Function(ParkCourseAttempt attempt) onOpen;

  const ParkCourseAttemptCards({
    super.key,
    required this.attempts,
    required this.unit,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    if (attempts.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // semantics-children: a group name, read once before the cards inside it
    return Semantics(
      container: true,
      label: l10n.runDetailParkCourseAttempts,
      child: Column(
        key: const Key('run-park-course-attempts'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final a in attempts)
            ListCard(
              key: Key('run-park-course-attempt-${a.parkCourseId}'),
              margin: const EdgeInsets.fromLTRB(
                AppInsets.gutter,
                AppSpace.sm,
                AppInsets.gutter,
                0,
              ),
              onTap: () => onOpen(a),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    parkCourseAttemptText(l10n, a, unit),
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpace.sm),
                  _ProgressLine(attempt: a, unit: unit),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  final ParkCourseAttempt attempt;
  final DistanceUnit unit;

  const _ProgressLine({required this.attempt, required this.unit});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final text = parkCourseAttemptProgressText(l10n, attempt, unit);
    return Semantics(
      container: true,
      label: l10n.runDetailParkCourseAttemptProgressLabel,
      value: text,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProgressBar(value: parkCourseAttemptFraction(attempt)),
            const SizedBox(height: AppSpace.xs),
            Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How far along the course the run got, 0..1.
double parkCourseAttemptFraction(ParkCourseAttempt a) =>
    a.courseM <= 0 ? 0 : (a.progressM / a.courseM).clamp(0.0, 1.0);

/// "2.10 km of 5.00 km" in the runner's unit.
String parkCourseAttemptProgressText(
  AppLocalizations l10n,
  ParkCourseAttempt a,
  DistanceUnit unit,
) => l10n.runDetailParkCourseAttemptProgress(
  UnitFormat.distance(a.progressM.toDouble(), unit),
  UnitFormat.distance(a.courseM.toDouble(), unit),
);

/// The one sentence saying why [a] got no time and what to do next time.
String parkCourseAttemptText(
  AppLocalizations l10n,
  ParkCourseAttempt a,
  DistanceUnit unit,
) {
  switch (a.outcome) {
    case ParkCourseAttemptOutcome.stoppedShort:
      return l10n.runDetailParkCourseAttemptStoppedShort(
        a.courseName,
        UnitFormat.distance(a.progressM.toDouble(), unit),
        UnitFormat.distance(a.courseM.toDouble(), unit),
      );
    case ParkCourseAttemptOutcome.skippedCheckpoint:
      return l10n.runDetailParkCourseAttemptSkippedCheckpoint(
        a.courseName,
        a.missedCheckpoint ?? 1,
        a.checkpointCount,
      );
    case ParkCourseAttemptOutcome.offCourse:
      return l10n.runDetailParkCourseAttemptOffCourse(a.courseName);
    case ParkCourseAttemptOutcome.wrongDirection:
      return l10n.runDetailParkCourseAttemptWrongDirection(a.courseName);
  }
}

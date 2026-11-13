import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../backend_timeout.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../park_courses.dart' show BoardPeriod, RunParkCourseTime;
import '../preferences.dart' show formatEffortTime;
import '../screens/park_courses_screen.dart';
import 'top_banner.dart';

/// The owner's park course chips on run detail: one per park course the run
/// completed, with the time and its places on that month's and that season's
/// fastest boards, each opening the course on the effort's month. Mirrors web `RunParkCourseChips.svelte`. Nothing
/// while loading or when the run completed no course; a failed read is a quiet
/// line with Retry, so run detail never depends on it.
class RunParkCourseChips extends StatefulWidget {
  final ApiClient api;
  final String runId;

  const RunParkCourseChips({super.key, required this.api, required this.runId});

  @override
  State<RunParkCourseChips> createState() => _RunParkCourseChipsState();
}

class _RunParkCourseChipsState extends State<RunParkCourseChips> {
  List<RunParkCourseTime> _times = const [];
  bool _loading = true;
  bool _failed = false;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.api.userId == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final rows = await widget.api
          .fetchRunParkCourseTimes(widget.runId)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _times = [for (final r in rows) RunParkCourseTime.fromRow(r)];
        _loading = false;
      });
    } catch (e) {
      debugPrint('run park course chips: read failed: $e');
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _open(RunParkCourseTime t) async {
    if (_opening) return;
    _opening = true;
    try {
      final found = await widget.api
          .fetchParkCourseBySlugs(t.parkSlug, t.courseSlug)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      if (found == null) {
        showTopBanner(
            context, AppLocalizations.of(context).runDetailParkCourseOpenFailed);
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ParkCourseScreen(
          api: widget.api,
          listing: found.park,
          course: found.course,
          initialPeriod: BoardPeriod.month(t.season, t.month),
        ),
      ));
    } catch (e) {
      debugPrint('run park course chips: open failed: $e');
      if (!mounted) return;
      showTopBanner(
          context, AppLocalizations.of(context).runDetailParkCourseOpenFailed);
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (_loading) return const SizedBox.shrink();
    if (_failed) {
      return Padding(
        key: const Key('run-park-courses-error'),
        padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.runDetailParkCoursesLoadFailed,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton(onPressed: _load, child: Text(l10n.parksRetry)),
          ],
        ),
      );
    }
    if (_times.isEmpty) return const SizedBox.shrink();
    // semantics-children: a group name, read once before the controls inside it
    return Semantics(
      container: true,
      label: l10n.runDetailParkCourses,
      child: Padding(
        key: const Key('run-park-courses'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in _times)
              ActionChip(
                key: Key('run-park-course-${t.effortId}'),
                avatar: Icon(Icons.park_outlined,
                    size: 18, color: theme.colorScheme.primary),
                label: Text(
                  [
                    t.courseName,
                    formatEffortTime(t.timeSeconds.toDouble()),
                    ?parkCourseRankText(
                      l10n,
                      t,
                      localeToTag(Localizations.localeOf(context)),
                    ),
                  ].join(' · '),
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: () => _open(t),
              ),
          ],
        ),
      ),
    );
  }
}

/// "#2 in November, #9 in 2026": a park course time's place on its month's
/// board where the park is, then on its season's, each when it holds one;
/// null when it holds neither. Mirrors web `RunParkCourseChips.rank`.
String? parkCourseRankText(
  AppLocalizations l10n,
  RunParkCourseTime t,
  String localeTag,
) {
  final month = formatMonthName(DateTime(t.season, t.month), localeTag);
  final monthRank = t.monthRank;
  final seasonRank = t.seasonRank;
  if (monthRank != null && seasonRank != null) {
    return l10n.runDetailParkCourseRanks(
        '$monthRank', month, '$seasonRank', '${t.season}');
  }
  if (monthRank != null) {
    return l10n.runDetailParkCourseMonthRank('$monthRank', month);
  }
  if (seasonRank != null) {
    return l10n.runDetailParkCourseRank('$seasonRank', '${t.season}');
  }
  return null;
}

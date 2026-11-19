import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show SheetScaffold;

import '../l10n/gen/app_localizations.dart';
import '../park_course_distance.dart';
import '../preferences.dart';
import '../route_guide.dart';
import '../screens/park_courses_screen.dart'
    show courseDistanceForPref, courseShapeLabel;
import 'park_course_map.dart';

/// Opens the park page's preview of one course: the course on its own map
/// with its start and finish, its distance, climb, laps and shape, the one
/// sentence that says where to start, and an Open course button. Mobile twin
/// of the web park page's preview panel. Tapping a course card opens it, so
/// the card never navigates on a tap the reader meant as a look.
Future<void> showParkCoursePreviewSheet(
  BuildContext context, {
  required ParkCourseListing course,
  required VoidCallback onOpen,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => ParkCoursePreviewSheet(course: course, onOpen: onOpen),
  );
}

class ParkCoursePreviewSheet extends StatelessWidget {
  final ParkCourseListing course;
  final VoidCallback onOpen;

  const ParkCoursePreviewSheet({
    super.key,
    required this.course,
    required this.onOpen,
  });

  /// Where to start, in one plain sentence: the guide's own getting-there
  /// note, else its first line. Null without a guide.
  static String? startSentence(AppLocalizations l10n, RouteGuide? guide) {
    if (guide == null) return null;
    final note = guide.gettingThere;
    if (note != null) return note;
    final lines = routeGuideLines(guide);
    if (lines.isEmpty) return null;
    return formatGuideLine(
      lines.first,
      GuideFormat(
        message: (key, params) => guideLineMessage(l10n, key, params),
        distance: formatDistanceForPref,
        short: formatElevationForPref,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final segment = course.segment;
    final row = course.course;
    final line = ApiClient.globalSegmentGeometry(segment);
    final laps = courseLapsChip(row.laps);
    final climb = segment.elevationM;
    final start = startSentence(l10n, parseRouteGuide(row.routeGuide));
    final facts = <(String, String, Key)>[
      (
        l10n.parksStatDistance,
        courseDistanceForPref(segment.distanceM),
        const Key('park-preview-distance'),
      ),
      if (climb != null && climb > 0)
        (
          l10n.parksStatElevation,
          formatElevationForPref(climb),
          const Key('park-preview-climb'),
        ),
      if (laps != null)
        (l10n.parksStatLaps, '$laps', const Key('park-preview-laps')),
      (
        l10n.parksStatShape,
        courseShapeLabel(l10n, row.courseShape),
        const Key('park-preview-shape'),
      ),
    ];
    return SheetScaffold(
      key: const Key('park-course-preview'),
      title: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                courseDisplayName(segment.name),
                key: const Key('park-preview-title'),
              ),
            ),
          ),
          IconButton(
            key: const Key('park-preview-close'),
            tooltip: l10n.parksPreviewClose,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (line.length >= 2)
            ParkCourseMap(
              key: const Key('park-preview-map'),
              line: line,
              aspectRatio: 1.6,
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              for (final (label, value, key) in facts)
                MergeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        value,
                        key: key,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (start != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    Icons.place,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    start,
                    key: const Key('park-preview-start'),
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: FilledButton.icon(
        key: const Key('park-preview-open'),
        onPressed: () {
          Navigator.of(context).pop();
          onOpen();
        },
        icon: const Icon(Icons.arrow_forward),
        iconAlignment: IconAlignment.end,
        label: Text(l10n.parksOpenCourse),
      ),
    );
  }
}

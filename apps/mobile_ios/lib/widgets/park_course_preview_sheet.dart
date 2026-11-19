import 'dart:io' show Platform;

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show SheetScaffold;
import 'package:url_launcher/url_launcher.dart';

import '../course_drive.dart' show MapsApp, mapsStartUrl;
import '../l10n/gen/app_localizations.dart';
import '../park_course_distance.dart';
import '../park_courses.dart' show courseEnds;
import '../preferences.dart';
import '../route_guide.dart';
import '../screens/park_courses_screen.dart'
    show
        courseDifficultyLabel,
        courseDistanceForPref,
        courseShapeLabel,
        courseStatusPill;
import 'park_course_map.dart';
import 'top_banner.dart';

/// Opens the park page's preview of one course: the course on its own map
/// with its start and finish, its distance, climb, laps, shape and
/// difficulty, its status when it is not open, the one sentence that says
/// where to start, directions to the start and an Open course button. Mobile
/// twin of the web park page's preview panel. Tapping a course card opens
/// it, so the card never navigates on a tap the reader meant as a look; the
/// course opens on top of the sheet, so back lands on the preview again.
Future<void> showParkCoursePreviewSheet(
  BuildContext context, {
  required ParkCourseListing course,
  required String title,
  required VoidCallback onOpen,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) =>
        ParkCoursePreviewSheet(course: course, title: title, onOpen: onOpen),
  );
}

class ParkCoursePreviewSheet extends StatelessWidget {
  final ParkCourseListing course;

  /// The name its card shows (`courseDisplayNames`), so the two agree.
  final String title;
  final VoidCallback onOpen;
  @visibleForTesting
  final Future<bool> Function(Uri uri)? launch;

  const ParkCoursePreviewSheet({
    super.key,
    required this.course,
    required this.title,
    required this.onOpen,
    this.launch,
  });

  Future<void> _directions(BuildContext context, double lat, double lng) async {
    final l10n = AppLocalizations.of(context);
    final app = Platform.isIOS ? MapsApp.apple : MapsApp.google;
    var opened = false;
    try {
      opened =
          await (launch ??
              (u) => launchUrl(u, mode: LaunchMode.externalApplication))(
            Uri.parse(mapsStartUrl(app, lat, lng)),
          );
    } catch (e) {
      debugPrint('park course preview: Maps launch failed: $e');
    }
    if (!opened && context.mounted) {
      showTopBanner(context, l10n.courseDriveOpenFailed);
    }
  }

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
    final closed = row.status == 'closed';
    final start = closed
        ? null
        : startSentence(l10n, parseRouteGuide(row.routeGuide));
    final difficulty = courseDifficultyLabel(l10n, row.difficulty);
    final status = courseStatusPill(context, row.status);
    final note = row.statusNote?.trim();
    final ends = closed
        ? null
        : courseEnds(
            line: [for (final w in line) (lat: w.lat, lng: w.lng)],
            startGate: (lat: segment.startGateLat, lng: segment.startGateLng),
            endGate: (lat: segment.endGateLat, lng: segment.endGateLng),
            shape: row.courseShape,
          );
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
      if (difficulty != null)
        (l10n.parksStatDifficulty, difficulty, const Key('park-preview-difficulty')),
    ];
    return SheetScaffold(
      key: const Key('park-course-preview'),
      title: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, key: const Key('park-preview-title')),
            ),
          ),
          ?status,
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
          if (closed) ...[
            Text(
              note != null && note.isNotEmpty ? note : l10n.parksClosedBanner,
              key: const Key('park-preview-closed'),
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
          ],
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
      actions: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          if (ends != null)
            OutlinedButton.icon(
              key: const Key('park-preview-directions'),
              onPressed: () =>
                  _directions(context, ends.start.lat, ends.start.lng),
              icon: const Icon(Icons.directions),
              label: Text(
                ends.finish == null
                    ? l10n.parksEndsDirectionsStartFinish
                    : l10n.parksEndsDirectionsStart,
              ),
            ),
          FilledButton.icon(
            key: const Key('park-preview-open'),
            onPressed: onOpen,
            icon: const Icon(Icons.arrow_forward),
            iconAlignment: IconAlignment.end,
            label: Text(l10n.parksOpenCourse),
          ),
        ],
      ),
    );
  }
}

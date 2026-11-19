import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui_kit/ui_kit.dart' show SectionHeader;
import 'package:url_launcher/url_launcher.dart';

import '../course_drive.dart' show MapsApp, mapsStartUrl;
import '../l10n/gen/app_localizations.dart';
import '../park_courses.dart' show CourseEnds, formatLatLng;
import 'top_banner.dart';

/// A course's start and finish as coordinates to copy, and directions to
/// each in the phone's maps app. Mirrors web's `CourseEndsBlock`. [ends]
/// comes from `courseEnds` over the line the screen already draws.
class CourseEndsCard extends StatelessWidget {
  final CourseEnds ends;

  /// Test seam; production opens the link in the maps app.
  final Future<bool> Function(Uri uri)? launch;

  /// The course page's one sentence about its start and finish boxes. Set,
  /// the card leads with it and a button to the start, and folds the
  /// coordinates away under it (decisions § 2582).
  final String? instruction;

  /// Whether "Get directions to the start" is the screen's one filled action:
  /// not when the screen has Navigate this course.
  final bool primary;

  const CourseEndsCard({
    super.key,
    required this.ends,
    this.launch,
    this.instruction,
    this.primary = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final points = _points(l10n);
    final text = instruction;
    return Column(
      key: const Key('course-ends'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader.title(label: l10n.parksEndsTitle),
        const SizedBox(height: 4),
        if (text == null)
          ...points
        else ...[
          Text(
            text,
            key: const Key('course-ends-instruction'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (primary)
            FilledButton.icon(
              key: const Key('course-ends-get-directions'),
              onPressed: () => _openDirections(context, ends.start, launch),
              icon: const Icon(Icons.directions),
              label: Text(l10n.parksEndsGetDirections),
            )
          else
            OutlinedButton.icon(
              key: const Key('course-ends-get-directions'),
              onPressed: () => _openDirections(context, ends.start, launch),
              icon: const Icon(Icons.directions),
              label: Text(l10n.parksEndsGetDirections),
            ),
          ExpansionTile(
            key: const Key('course-ends-coordinates'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            title: Text(l10n.parksEndsCoordinates),
            children: points,
          ),
        ],
      ],
    );
  }

  List<Widget> _points(AppLocalizations l10n) {
    final finish = ends.finish;
    return [
      if (finish == null)
        _EndRow(
          which: 'start-finish',
          label: l10n.parksLegendStartFinish,
          copyLabel: l10n.parksEndsCopyStartFinish,
          directionsLabel: l10n.parksEndsDirectionsStartFinish,
          point: ends.start,
          launch: launch,
        )
      else ...[
        _EndRow(
          which: 'start',
          label: l10n.parksLegendStart,
          copyLabel: l10n.parksEndsCopyStart,
          directionsLabel: l10n.parksEndsDirectionsStart,
          point: ends.start,
          launch: launch,
        ),
        _EndRow(
          which: 'finish',
          label: l10n.parksLegendFinish,
          copyLabel: l10n.parksEndsCopyFinish,
          directionsLabel: l10n.parksEndsDirectionsFinish,
          point: finish,
          launch: launch,
        ),
      ],
    ];
  }
}

// The Drive this course hand-off's link, to the platform's own maps app.
Future<void> _openDirections(
  BuildContext context,
  ({double lat, double lng}) point,
  Future<bool> Function(Uri uri)? launch,
) async {
  final l10n = AppLocalizations.of(context);
  final app = Platform.isIOS ? MapsApp.apple : MapsApp.google;
  var opened = false;
  try {
    opened =
        await (launch ??
            (u) => launchUrl(u, mode: LaunchMode.externalApplication))(
          Uri.parse(mapsStartUrl(app, point.lat, point.lng)),
        );
  } catch (e) {
    debugPrint('CourseEndsCard: Maps launch failed: $e');
  }
  if (!opened && context.mounted) {
    showTopBanner(context, l10n.courseDriveOpenFailed);
  }
}

class _EndRow extends StatelessWidget {
  final String which;
  final String label;
  final String copyLabel;
  final String directionsLabel;
  final ({double lat, double lng}) point;
  final Future<bool> Function(Uri uri)? launch;

  const _EndRow({
    required this.which,
    required this.label,
    required this.copyLabel,
    required this.directionsLabel,
    required this.point,
    required this.launch,
  });

  Future<void> _copy(BuildContext context, String text) async {
    final l10n = AppLocalizations.of(context);
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) showTopBanner(context, l10n.parksEndsCopied);
    } catch (e) {
      debugPrint('CourseEndsCard: copy failed: $e');
      if (context.mounted) showTopBanner(context, l10n.parksEndsCopyFailed);
    }
  }

  Future<void> _directions(BuildContext context) =>
      _openDirections(context, point, launch);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final text = formatLatLng(point);
    return Padding(
      key: Key('course-ends-$which'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.titleSmall),
          SelectableText(
            text,
            key: Key('course-ends-$which-coords'),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              Semantics(
                label: copyLabel,
                button: true,
                excludeSemantics: true,
                onTap: () => _copy(context, text),
                child: OutlinedButton.icon(
                  key: Key('course-ends-$which-copy'),
                  onPressed: () => _copy(context, text),
                  icon: const Icon(Icons.content_copy),
                  label: Text(l10n.parksEndsCopy),
                ),
              ),
              Semantics(
                label: directionsLabel,
                button: true,
                excludeSemantics: true,
                onTap: () => _directions(context),
                child: OutlinedButton.icon(
                  key: Key('course-ends-$which-directions'),
                  onPressed: () => _directions(context),
                  icon: const Icon(Icons.directions),
                  label: Text(l10n.parksEndsDirections),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

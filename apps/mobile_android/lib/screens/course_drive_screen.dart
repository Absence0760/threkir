import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../audio_cues.dart';
import '../course_drive.dart';
import '../course_drive_check.dart' as check;
import '../course_drive_location.dart';
import '../course_drive_notice.dart';
import '../course_drive_speech.dart';
import '../course_drive_tracker.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart' show activeLocaleTag;
import '../preferences.dart' show activeDistanceUnit, formatDistanceForPref;
import '../widgets/error_state.dart';
import '../widgets/loading_skeletons.dart';
import '../widgets/top_banner.dart';

/// The course a drive follows: the line the viewer was served (clipped for a
/// non-owner) and the markers `route_markers_for_viewer` returned.
class CourseDriveCourse {
  const CourseDriveCourse({required this.line, required this.markers});
  final List<DrivePoint> line;
  final List<DriveMarkerInput> markers;
}

enum _DriveRun { idle, running, finished, abandoned }

/// Drive this course (docs/features/course_drive.md): the Maps hand-off and
/// the spoken course notes. Nothing here records anything — the drive has
/// its own tracker, never the run recorder (gotcha 1), and every speech or
/// Maps-launch call is walled off so its failure cannot stop the tracking
/// (layered resilience).
class CourseDriveScreen extends StatefulWidget {
  const CourseDriveScreen({
    super.key,
    required this.title,
    required this.load,
    this.checkDrivable,
    this.positions,
    this.ensurePermission,
    this.speak,
    this.launch,
    this.readNoticeAck,
    this.writeNoticeAck,
  });

  final String title;
  final Future<CourseDriveCourse> Function() load;

  /// Test seams. Each defaults to the real implementation.
  final Future<List<CourseStretch>?> Function(List<DrivePoint> line)?
  checkDrivable;
  final Stream<DrivePosition> Function()? positions;
  final Future<bool> Function()? ensurePermission;
  final Future<void> Function(String text)? speak;
  final Future<bool> Function(Uri url)? launch;
  final Future<bool> Function()? readNoticeAck;
  final Future<void> Function()? writeNoticeAck;

  @override
  State<CourseDriveScreen> createState() => _CourseDriveScreenState();
}

class _CourseDriveScreenState extends State<CourseDriveScreen> {
  bool _loading = true;
  bool _loadFailed = false;
  List<DrivePoint> _line = const [];
  List<DriveNote> _notes = const [];
  MapsApp _app = MapsApp.google;

  String _check = 'checking';
  List<CourseStretch> _stretches = const [];

  _DriveRun _run = _DriveRun.idle;
  CourseDriveTracker? _tracker;
  DriveCueAnnouncer? _announcer;
  DriveFix? _fix;
  int _legIndex = 0;
  StreamSubscription<DrivePosition>? _sub;
  AudioCues? _audio;

  List<DriveLeg> get _legs => planDriveLegs(_line, switch (_app) {
    MapsApp.google => kMapsWaypointCapGoogle,
    MapsApp.apple => kMapsWaypointCapApple,
    MapsApp.waze => kMapsWaypointCapWaze,
  });

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    CourseDriveCourse? course;
    try {
      course = await widget.load();
    } catch (e) {
      debugPrint('CourseDriveScreen: load failed: $e');
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadFailed = course == null;
      if (course != null) {
        _line = course.line;
        _notes = buildDriveNotes(course.markers, course.line);
      }
    });
    if (course == null) return;
    unawaited(_runCheck());
    unawaited(_showNoticeIfNeeded());
  }

  Future<void> _runCheck() async {
    List<CourseStretch>? result;
    try {
      result = await (widget.checkDrivable ?? check.checkDrivable)(_line);
    } catch (e) {
      debugPrint('CourseDriveScreen: drivable check failed: $e');
    }
    if (!mounted) return;
    setState(() {
      _check = result == null ? 'failed' : 'done';
      _stretches = result ?? const [];
    });
  }

  Future<void> _showNoticeIfNeeded() async {
    final acked =
        await (widget.readNoticeAck ?? courseDriveNoticeAcknowledged)();
    if (acked || !mounted) return;
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        key: const Key('course-drive-notice'),
        title: Text(l.courseDriveNoticeTitle),
        content: Text(l.courseDriveNoticeBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.courseDriveNoticeAccept),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (ok == true) {
      await (widget.writeNoticeAck ?? acknowledgeCourseDriveNotice)();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _open(String url) async {
    final l = AppLocalizations.of(context);
    var opened = false;
    try {
      opened =
          await (widget.launch ??
              (u) => launchUrl(u, mode: LaunchMode.externalApplication))(
            Uri.parse(url),
          );
    } catch (e) {
      debugPrint('CourseDriveScreen: Maps launch failed: $e');
    }
    if (!opened && mounted) showTopBanner(context, l.courseDriveOpenFailed);
  }

  // L4 — speech. Never awaited by the tracking path, never allowed to throw
  // into it.
  void _say(String text) {
    unawaited(() async {
      try {
        await (widget.speak ?? (_audio ??= AudioCues()).announceDriveText)(
          text,
        );
      } catch (e) {
        debugPrint('CourseDriveScreen: speech failed: $e');
      }
    }());
  }

  Future<void> _start() async {
    final l = AppLocalizations.of(context);
    final allowed =
        await (widget.ensurePermission ?? ensureDriveLocationPermission)();
    if (!mounted) return;
    if (!allowed) {
      showTopBanner(context, l.courseDriveLocationDenied);
      return;
    }
    final stream =
        (widget.positions ??
        () => drivePositions(
          notificationTitle: l.courseDriveTitle,
          notificationText: l.ttsDriveStarted,
        ))();
    setState(() {
      _run = _DriveRun.running;
      _tracker = CourseDriveTracker(_line);
      _announcer = null;
      _fix = null;
      _legIndex = 0;
    });
    _say(l.ttsDriveStarted);
    _sub = stream.listen(
      _onFix,
      onError: (Object e) {
        debugPrint('CourseDriveScreen: position stream error: $e');
      },
    );
  }

  void _stop(_DriveRun to) {
    _sub?.cancel();
    _sub = null;
    setState(() => _run = to);
  }

  void _onFix(DrivePosition p) {
    final tracker = _tracker;
    if (tracker == null || _run != _DriveRun.running) return;
    final l = AppLocalizations.of(context);
    final fix = tracker.update(p.lat, p.lng, p.at);
    final legs = _legs;
    if (fix.joined) {
      _announcer = DriveCueAnnouncer(_notes, fix.alongM);
      var i = 0;
      while (i < legs.length - 1 && fix.alongM >= legs[i].end.alongM) {
        i++;
      }
      _legIndex = i;
    }
    setState(() => _fix = fix);

    if (fix.state == DriveTrackState.finished) {
      _say(l.ttsDriveFinished);
      _stop(_DriveRun.finished);
      return;
    }
    if (fix.state == DriveTrackState.abandoned) {
      _say(l.ttsDriveAbandoned);
      _stop(_DriveRun.abandoned);
      return;
    }
    if (fix.state != DriveTrackState.onCourse) return;

    while (_legIndex < legs.length - 1 &&
        fix.alongM >= legs[_legIndex].end.alongM) {
      _legIndex++;
      _say(l.ttsDriveLegDone('$_legIndex', '${_legIndex + 1}'));
    }
    final announcer = _announcer;
    if (announcer == null) return;
    final tag = activeLocaleTag;
    for (
      var c = announcer.next(fix.alongM, fix.speedMps);
      c != null;
      c = announcer.next(fix.alongM, fix.speedMps)
    ) {
      _say(driveCueUtterance(l, c, activeDistanceUnit, tag));
    }
  }

  DriveNote? _nextNote() {
    final fix = _fix;
    if (fix == null) return null;
    for (final n in _notes) {
      if (n.alongM > fix.alongM) return n;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.courseDriveTitle)),
      body: _loading
          ? SectionedDetailSkeleton(label: l.courseDriveTitle, hasAction: true)
          : _loadFailed
          ? ErrorState(message: l.courseDriveLoadFailed, onRetry: _load)
          : _run == _DriveRun.running
          ? _driving(context, l)
          : _handOff(context, l),
    );
  }

  Widget _driving(BuildContext context, AppLocalizations l) {
    final theme = Theme.of(context);
    final fix = _fix;
    final next = _nextNote();
    final String status;
    if (fix == null || fix.state == DriveTrackState.approaching) {
      status = l.courseDriveWaiting;
    } else if (next == null) {
      status = l.courseDriveNoMoreNotes;
    } else {
      status = l.courseDriveNextIn(
        formatDistanceForPref(next.alongM - fix.alongM),
      );
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    status,
                    key: const Key('course-drive-status'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  if (next != null &&
                      fix != null &&
                      fix.state != DriveTrackState.approaching) ...[
                    const SizedBox(height: 12),
                    Text(
                      [
                        driveKindLabel(l, next.kind),
                        if (next.label.isNotEmpty) next.label,
                      ].join(' · '),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ],
              ),
            ),
            FilledButton(
              key: const Key('course-drive-stop'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(72),
              ),
              onPressed: () => _stop(_DriveRun.idle),
              child: Text(l.courseDriveStop),
            ),
          ],
        ),
      ),
    );
  }

  Widget _handOff(BuildContext context, AppLocalizations l) {
    final theme = Theme.of(context);
    final legs = _legs;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_run == _DriveRun.finished)
                Text(
                  l.courseDriveFinished,
                  key: const Key('course-drive-finished'),
                  style: theme.textTheme.titleMedium,
                ),
              if (_run == _DriveRun.abandoned)
                Text(
                  l.courseDriveAbandoned,
                  key: const Key('course-drive-abandoned'),
                  style: theme.textTheme.titleMedium,
                ),
              Text(l.courseDriveMapsApp, style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<MapsApp>(
                segments: [
                  ButtonSegment(
                    value: MapsApp.google,
                    label: Text(l.courseDriveAppGoogle),
                  ),
                  ButtonSegment(
                    value: MapsApp.apple,
                    label: Text(l.courseDriveAppApple),
                  ),
                  ButtonSegment(
                    value: MapsApp.waze,
                    label: Text(l.courseDriveAppWaze),
                  ),
                ],
                selected: {_app},
                onSelectionChanged: (s) => setState(() {
                  _app = s.first;
                  _legIndex = 0;
                }),
              ),
              const SizedBox(height: 12),
              if (_line.isNotEmpty)
                OutlinedButton.icon(
                  key: const Key('course-drive-to-start'),
                  icon: const Icon(Icons.directions_car_outlined),
                  label: Text(l.courseDriveToStart),
                  onPressed: () => _open(
                    mapsStartUrl(_app, _line.first.lat, _line.first.lng),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                l.courseDriveLegsHeading,
                style: theme.textTheme.titleMedium,
              ),
              for (final leg in legs)
                ListTile(
                  key: Key('course-drive-leg-${leg.index}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.open_in_new),
                  title: Text(
                    l.courseDriveLeg(
                      '${leg.index + 1}',
                      formatDistanceForPref(leg.start.alongM),
                      formatDistanceForPref(leg.end.alongM),
                    ),
                  ),
                  onTap: () => _open(mapsLegUrl(_app, leg)),
                ),
              Text(l.courseDriveGuidanceOnly, style: muted),
              const SizedBox(height: 12),
              ..._checkSection(theme, l, muted),
              const SizedBox(height: 16),
              Text(
                l.courseDriveNotesHeading,
                style: theme.textTheme.titleMedium,
              ),
              if (_notes.isEmpty)
                Text(l.courseDriveNoNotes, style: muted)
              else
                for (final n in _notes)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Text(
                      formatDistanceForPref(n.alongM),
                      style: theme.textTheme.labelLarge,
                    ),
                    title: Text(
                      [
                        driveKindLabel(l, n.kind),
                        if (n.label.isNotEmpty) n.label,
                      ].join(' · '),
                    ),
                    subtitle: switch (driveNoteDetailShown(
                      l,
                      n,
                      formatDistanceForPref,
                    )) {
                      final String d => Text(d),
                      null => null,
                    },
                  ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              key: const Key('course-drive-start'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              icon: const Icon(Icons.record_voice_over_outlined),
              label: Text(l.courseDriveStart),
              onPressed: _line.length < 2 ? null : _start,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _checkSection(
    ThemeData theme,
    AppLocalizations l,
    TextStyle? muted,
  ) {
    switch (_check) {
      case 'checking':
        return [Text(l.courseDriveChecking, style: muted)];
      case 'failed':
        return [
          Text(
            l.courseDriveCheckFailed,
            key: const Key('course-drive-check-failed'),
            style: muted,
          ),
        ];
      default:
        if (_stretches.isEmpty) {
          return [Text(l.courseDriveAllDrivable, style: muted)];
        }
        return [
          Text(
            l.courseDriveUndrivableHeading,
            style: theme.textTheme.titleSmall,
          ),
          for (final s in _stretches)
            Text(
              l.courseDriveStretch(
                formatDistanceForPref(s.startM),
                formatDistanceForPref(s.endM),
              ),
              key: const Key('course-drive-stretch'),
            ),
        ];
    }
  }
}

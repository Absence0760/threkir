import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart' show ImagePicker, ImageSource;
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ui_kit/ui_kit.dart'
    show ChoiceChipOption, ChoiceChipRow, SheetScaffold;
import 'package:url_launcher/url_launcher.dart';

import 'live_run_map.dart'
    show basemapTileLayer, basemapVoidColour, tileUrlFor;
import 'map_attribution.dart';

import '../l10n/date_format.dart';
import '../map_tile_readiness.dart';
import 'plan_recap_card.dart' show planRecapBracketLabel;
import 'badge_grid.dart' show badgeLabelFor, badgeTierLabel;
import '../run_stats.dart' show RunSplit, computeSplitDurations;
import '../pr_card.dart';
import '../activity_type_labels.dart';
import '../flyover_video_flag.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../mascot.dart';
import '../preferences.dart';
import '../privacy.dart';
import '../park_courses.dart' show RunParkCourseTime, shareCoursePlaces;
import '../run_share_stats.dart';
import '../share_look.dart';
import '../share_placement.dart';
import '../share_sheet.dart';
import 'capture_png.dart';
import 'head_to_head_card.dart';
import 'run_share_overlays.dart';
import '../web_base_url.dart';
import '../widgets/top_banner.dart';

export '../run_share_stats.dart' show runShareCardTrack, runShareCardHasMap;

/// What the share image is drawn on: the branded map [card], the runner's own
/// [photo] under a scrim, or nothing at all ([sticker], a transparent PNG to
/// lay over a story or photo in another app). [video] is not an image: it
/// hands the run to the web flyover export, which records the 3D course as a
/// 9:16 video in the browser (decisions § 2259), because the phone has no 3D
/// map stack to render one with (§ 8). [versus] is the head-to-head card: the
/// runner's best on this run's route against a mutual-follow friend's (§ 2267).
/// [pr] is one personal record the run set, offered only when it set one
/// (decisions § 2266).
enum RunShareStyle { card, photo, sticker, video, versus, pr }

/// Opens a URL outside the app; returns whether anything took it.
typedef RunShareUrlOpener = Future<bool> Function(Uri url);

Future<bool> _openExternally(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

/// The web page the Video style opens: the run's own page, with `video=1`
/// asking it to open the 3D preview where the export lives.
Uri runVideoExportUrl(String runId, {String? webBase}) =>
    Uri.parse(webPageUrl('/runs/${Uri.encodeComponent(runId)}?video=1',
        override: webBase));

/// Thrown by a [RunShareImageSaver] when the runner has refused the app access
/// to their photos, so the sheet can say how to grant it rather than report a
/// generic failure.
class ShareSaveDenied implements Exception {
  const ShareSaveDenied();
}

/// Writes a share PNG to the device's photo library.
typedef RunShareImageSaver = Future<void> Function(Uint8List png, String name);

/// The default [RunShareImageSaver]: the device's photo library, asking for
/// access first.
Future<void> saveShareImageToGallery(Uint8List png, String name) async {
  try {
    if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
      throw const ShareSaveDenied();
    }
    await Gal.putImageBytes(png, name: name);
  } on GalException catch (e) {
    if (e.type == GalExceptionType.accessDenied) throw const ShareSaveDenied();
    rethrow;
  }
}

/// Opens a modal sheet that shares [run] as an image in one of three
/// [RunShareStyle]s, or exports the raw GPX / TCX / FIT, via the system share
/// sheet — and saves the image straight to the photo library, which is the
/// step a sticker needs before a story editor can place it.
///
/// [privacyZones] is required so no entry point can open the sheet without
/// deciding what the image withholds; pass the owner's zones. Every style
/// draws the same clipped line. The GPX / TCX / FIT exports stay the full
/// track: they are the owner's own copy of their data, not a published
/// rendering.
///
/// [records] are the personal records the run set (`prCardEntries`, longest
/// first); the PR style is offered only when there is one, and
/// [initialStyle] opens the sheet on it from a personal_record notification.
///
/// [streakDays] is the streak day the run was, as of its own day, and
/// [badgeLoad] reads the single-run distance badge it earned and [courseLoad]
/// the park course time it set: with the records, the run's splits and the
/// race stamped on it, they decide which occasion stickers the sheet offers.
///
/// [showMascot] puts Grisnir beside the map card's title while the mark is
/// on; it defaults to the runner's `show_mascot` setting ([mascotShown]).
///
/// [pickPhotoOverride] and [saveImageOverride] replace the gallery picker and
/// the photo-library write so a widget test can drive both without platform
/// channels.
Future<void> showRunShareSheet(
  BuildContext context, {
  required Run run,
  required Preferences preferences,
  required String title,
  required List<PrivacyZone> privacyZones,
  List<PrCardEntry> records = const [],
  RunShareStyle initialStyle = RunShareStyle.card,
  int streakDays = 0,
  RunShareBadgeLoader? badgeLoad,
  RunShareCourseLoader? courseLoad,
  @visibleForTesting Future<XFile?> Function()? pickPhotoOverride,
  @visibleForTesting RunShareImageSaver? saveImageOverride,
  @visibleForTesting RunShareUrlOpener? openUrlOverride,
  ApiClient? api,
  Future<void> Function()? onShareLink,
  bool? showMascot,
  @visibleForTesting HeadToHeadLoader? headToHeadLoadOverride,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    builder: (ctx) => _ShareRunSheet(
      run: run,
      preferences: preferences,
      title: title,
      privacyZones: privacyZones,
      records: records,
      streakDays: streakDays,
      badgeLoad: badgeLoad,
      courseLoad: courseLoad,
      initialStyle: initialStyle == RunShareStyle.pr && records.isEmpty
          ? RunShareStyle.card
          : initialStyle,
      pickPhotoOverride: pickPhotoOverride,
      onShareLink: onShareLink,
      showMascot: showMascot ?? mascotShown(),
      saveImage: saveImageOverride ?? saveShareImageToGallery,
      openUrl: openUrlOverride ?? _openExternally,
      headToHeadLoad: headToHeadLoadOverride ??
          (api != null && run.routeId != null
              ? () => api.fetchHeadToHead('route', run.routeId!,
                  activityType:
                      run.metadata?['activity_type'] as String? ?? 'run')
              : null),
    ),
  );
}

/// The single-run distance badge a run earned, as the badge sticker prints it.
typedef RunShareBadge = ({String badgeKey, String tier});

/// Reads the badge a run earned; null when it earned none.
typedef RunShareBadgeLoader = Future<RunShareBadge?> Function();

/// Reads the park course time the course sticker prints (`pickShareCourse`);
/// null when the run completed no park course.
typedef RunShareCourseLoader = Future<RunParkCourseTime?> Function();

class _ShareRunSheet extends StatefulWidget {
  final Run run;
  final Preferences preferences;
  final String title;
  final List<PrivacyZone> privacyZones;
  final List<PrCardEntry> records;
  final RunShareStyle initialStyle;
  final int streakDays;
  final RunShareBadgeLoader? badgeLoad;
  final RunShareCourseLoader? courseLoad;
  final Future<XFile?> Function()? pickPhotoOverride;
  final RunShareImageSaver saveImage;
  final RunShareUrlOpener openUrl;
  final HeadToHeadLoader? headToHeadLoad;
  final Future<void> Function()? onShareLink;
  final bool showMascot;

  const _ShareRunSheet({
    required this.run,
    required this.preferences,
    required this.title,
    required this.privacyZones,
    required this.records,
    required this.initialStyle,
    this.streakDays = 0,
    this.badgeLoad,
    this.courseLoad,
    required this.saveImage,
    required this.openUrl,
    this.pickPhotoOverride,
    this.headToHeadLoad,
    this.onShareLink,
    this.showMascot = true,
  });

  @override
  State<_ShareRunSheet> createState() => _ShareRunSheetState();
}

class _ShareRunSheetState extends State<_ShareRunSheet> {
  final GlobalKey _cardKey = GlobalKey();
  final MapTileReadiness _tiles = MapTileReadiness();
  final SharePlacementProbe _probe = SharePlacementProbe();
  bool _busy = false;
  late RunShareStyle _style = widget.initialStyle;
  RunShareLook _look = const RunShareLook();
  int _prIndex = 0;

  PrCardEntry? get _record => widget.records.isEmpty
      ? null
      : widget.records[_prIndex.clamp(0, widget.records.length - 1)];
  File? _photo;
  bool _picking = false;

  RunShareBadge? _badge;
  RunParkCourseTime? _course;

  /// The run's splits, from its full track: the clipped share line would
  /// drop the first and last km. Mile ticks for a mile runner.
  late final List<RunSplit> _splits = computeSplitDurations(
    widget.run.track,
    widget.preferences.unit == DistanceUnit.mi ? 1609.344 : 1000,
    widget.run.startedAt,
    totalDistanceMetres: widget.run.distanceMetres,
  );

  /// The race the run is linked to, from the result stamped on it: the
  /// official chip time when there is one.
  late final ({String name, String? time})? _race = () {
    final meta = widget.run.metadata;
    final name = (meta?['race_name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return null;
    final time = (meta?['chip_time'] as String?)?.trim();
    return (name: name, time: time == null || time.isEmpty ? null : time);
  }();

  List<RunStickerKind> get _offeredKinds => offeredStickerKinds(
        RunStickerOccasions(
          splits: _splits.length,
          records: widget.records.length,
          streakDays: widget.streakDays,
          race: _race != null,
          course: _course != null,
          badge: _badge != null,
          route: runShareCardTrack(widget.run, widget.privacyZones).length >= 2,
        ),
      );

  /// The kind this run prints: the remembered one when the run has its data.
  RunStickerKind get _kind => stickerKindFor(_look.kind, _offeredKinds);

  bool get _usesKinds =>
      _style == RunShareStyle.sticker || _style == RunShareStyle.photo;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreLook());
    unawaited(_loadBadge());
    unawaited(_loadCourse());
  }

  /// L4: a failed read leaves the course sticker unoffered and nothing else.
  Future<void> _loadCourse() async {
    final load = widget.courseLoad;
    if (load == null) return;
    try {
      final course = await load();
      if (mounted && course != null) setState(() => _course = course);
    } catch (e) {
      debugPrint('share course read failed: $e');
    }
  }

  /// L4: a failed read leaves the badge sticker unoffered and nothing else.
  Future<void> _loadBadge() async {
    final load = widget.badgeLoad;
    if (load == null) return;
    try {
      final badge = await load();
      if (mounted && badge != null) setState(() => _badge = badge);
    } catch (e) {
      debugPrint('share badge read failed: $e');
    }
  }

  /// The occasion sticker the current kind draws, or null for the stats.
  RunOccasionBody? _occasion(AppLocalizations l10n) {
    if (!_usesKinds) return null;
    final hasRoute =
        runShareCardTrack(widget.run, widget.privacyZones).length >= 2;
    switch (_kind) {
      case RunStickerKind.stats:
        return null;
      case RunStickerKind.splits:
        final unit = widget.preferences.unit;
        final tick = unit == DistanceUnit.mi ? 1609.344 : 1000.0;
        final rows = [
          for (final sp in _splits)
            SplitsStickerRow(
              paceSecPerKm: sp.duration.inMilliseconds / tick,
              metres: tick,
            ),
        ];
        final avg = averageStickerPace(rows);
        return SplitsStickerBody(
          l10n.shareCardSplitsHeading(
            _splits.length,
            '${UnitFormat.pace(avg, unit)} ${UnitFormat.paceLabel(unit)}',
          ),
          [
            for (final (i, sp) in _splits.indexed)
              SplitsStickerEntry(
                '${sp.tick}',
                UnitFormat.pace(rows[i].paceSecPerKm, unit),
                rows[i],
              ),
          ],
        );
      case RunStickerKind.pr:
        final record = _record!;
        final improvement = formatPrImprovement(record);
        return prStickerBody(
          headline: record.kind == PrCardKind.held
              ? l10n.shareCardPrHeld
              : l10n.shareCardPrHeadline,
          distance: planRecapBracketLabel(l10n, record.distance),
          time: formatShareDuration(Duration(seconds: record.timeS)),
          improvement:
              improvement == null ? null : l10n.shareCardPrFaster(improvement),
          hasRoute: hasRoute,
        );
      case RunStickerKind.streak:
        return streakStickerBody(
          kicker: l10n.shareCardKindStreak,
          days: '${widget.streakDays}',
          caption: l10n.shareCardStreakCaption,
        );
      case RunStickerKind.race:
        final race = _race!;
        return raceStickerBody(
          name: race.name,
          finisher: l10n.shareCardRaceFinisher,
          time: race.time,
          hasRoute: hasRoute,
        );
      case RunStickerKind.course:
        final course = _course!;
        return courseStickerBody(
          kicker: l10n.shareCardCourseKicker,
          name: course.courseName,
          park: course.parkName,
          time: formatShareDuration(Duration(seconds: course.timeSeconds)),
          rank: _courseRankLine(l10n, course),
          hasRoute: hasRoute,
        );
      case RunStickerKind.badge:
        final badge = _badge!;
        return badgeStickerBody(
          kicker: l10n.shareCardBadgeKicker,
          name: badgeLabelFor(l10n, badge.badgeKey, badge.tier,
              unit: widget.preferences.unit),
          tier: badgeTierLabel(l10n, badge.tier),
        );
      case RunStickerKind.route:
        return routeStickerBody();
    }
  }

  Future<void> _restoreLook() async {
    final look = await loadShareLook();
    if (!mounted) return;
    setState(() => _look = _forThisRun(look));
  }

  /// [look] with the stats this run cannot print taken out, so the cap counts
  /// what the image shows. A look saved on a hill run with a strap keeps its
  /// climb and heart rate on disk for the next such run; only an edit made
  /// here writes the narrowed set back.
  RunShareLook _forThisRun(RunShareLook look) {
    final available = availableShareStats(widget.run);
    final printable = [
      for (final k in look.stats)
        if (available.contains(k)) k,
    ];
    return look.copyWith(
      stats: printable.isEmpty ? RunShareLook.defaultStats : printable,
    );
  }

  void _setLook(RunShareLook look) {
    if (look == _look) return;
    setState(() => _look = look);
    unawaited(saveShareLook(look));
  }

  /// A gesture's placement, shown at once and stored when the gesture ends.
  void _movePlacement(SharePlacement placement) {
    final look = _look.withPlacement(placement);
    if (look != _look) setState(() => _look = look);
  }

  void _resetPlacement() =>
      _setLook(_look.withPlacement(SharePlacement.initial));

  String _caption(AppLocalizations l10n) {
    final unit = widget.preferences.unit;
    final dist = UnitFormat.distance(widget.run.distanceMetres, unit);
    return l10n.shareCardCaption(
      widget.title,
      dist,
      formatShareDuration(widget.run.duration),
    );
  }

  bool get _hasImage =>
      _style != RunShareStyle.video &&
      _style != RunShareStyle.versus &&
      (_style != RunShareStyle.photo || _photo != null);
  bool get _canExportImage => !_busy && !_picking && _hasImage;

  /// The web export records the share card's clipped line, so the style is
  /// offered only when that line exists, and only while the web offers the
  /// export at all (decisions § 2271).
  bool get _canOfferVideo =>
      flyoverVideoGate && runShareCardHasMap(widget.run, widget.privacyZones);

  /// The logical width of the canvas being rasterised, so the PNG comes out
  /// [shareImageExportWidthPx] across whichever style it is.
  double get _canvasWidth => switch (_style) {
        RunShareStyle.card => RunShareCard.canvas.width,
        RunShareStyle.photo => RunPhotoShareCard.canvasFor(_look.aspect).width,
        RunShareStyle.sticker => RunStickerShareCard.canvasWidth(_look,
            occasion: _kind != RunStickerKind.stats),
        RunShareStyle.pr => RunPhotoShareCard.canvasFor(_look.aspect).width,
        RunShareStyle.video ||
        RunShareStyle.versus =>
          throw StateError('${_style.name} draws no canvas here'),
      };

  Future<XFile?> _pick() {
    final override = widget.pickPhotoOverride;
    if (override != null) return override();
    // The pick is re-rasterised into the share PNG, so the original's EXIF
    // (GPS included) never leaves the device. 2048 px covers the export.
    return ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
    );
  }

  Future<void> _pickPhoto() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final picked = await _pick();
      if (picked == null) return;
      final file = File(picked.path);
      // Decode before showing it, so a capture straight after the pick never
      // rasterises the photo slot empty. precacheImage completes normally on
      // a decode failure and only reports it, so the failure is caught here
      // and thrown: an undecodable pick must take the banner path, not leave
      // a blank photo the runner can share.
      if (!mounted) return;
      Object? decodeError;
      await precacheImage(
        FileImage(file),
        context,
        onError: (e, _) => decodeError = e,
      );
      final failure = decodeError;
      if (failure != null) throw failure;
      if (!mounted) return;
      setState(() => _photo = file);
    } catch (e) {
      debugPrint('Failed to load share photo: $e');
      if (mounted) {
        showTopBanner(context, AppLocalizations.of(context).shareCardPhotoError);
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _selectStyle(RunShareStyle style) {
    setState(() => _style = style);
    if (style == RunShareStyle.photo && _photo == null) unawaited(_pickPhoto());
  }

  /// The PNG of what the preview shows. Waits for the tiles the card is
  /// actually showing, not for a guessed interval: a fixed sleep rasterised a
  /// part-black map whenever a cold fetch outran it.
  Future<Uint8List> _render() async {
    if (_style == RunShareStyle.card &&
        runShareCardHasMap(widget.run, widget.privacyZones)) {
      await _tiles.settled();
    }
    // Decoded before the capture so the PNG never carries an empty corner.
    // A decode failure is reported, not thrown: the card exports without him.
    if (_style == RunShareStyle.card &&
        _look.mark &&
        widget.showMascot &&
        mounted) {
      await precacheImage(
        const AssetImage(kGrisnirBadgeAsset),
        context,
        onError: (e, _) => debugPrint('Grisnir badge failed to decode: $e'),
      );
    }
    await WidgetsBinding.instance.endOfFrame;
    return capturePngBytes(
      _cardKey,
      pixelRatio: shareImageExportWidthPx / _canvasWidth,
    );
  }

  String get _imageName => 'threkir-run-${widget.run.id}-${_style.name}';

  Future<void> _shareImage() async {
    if (!_canExportImage) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final bytes = await _render();
      final tmp = await getTemporaryDirectory();
      final file = File('${tmp.path}/$_imageName.png');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      await shareFilesFrom(
        context,
        files: [XFile(file.path, mimeType: 'image/png')],
        text: _caption(l10n),
      );
    } catch (e) {
      debugPrint('Failed to share run image: $e');
      if (mounted) {
        showTopBanner(
            context, AppLocalizations.of(context).shareCardImageError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveImage() async {
    if (!_canExportImage) return;
    setState(() => _busy = true);
    try {
      final bytes = await _render();
      await widget.saveImage(bytes, _imageName);
      if (!mounted) return;
      showTopBanner(context, AppLocalizations.of(context).shareCardSaved);
    } on ShareSaveDenied {
      if (mounted) {
        showTopBanner(context, AppLocalizations.of(context).shareCardSaveDenied);
      }
    } catch (e) {
      debugPrint('Failed to save run image: $e');
      if (mounted) {
        showTopBanner(context, AppLocalizations.of(context).shareCardSaveError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openVideoExport() async {
    if (_busy) return;
    final url = runVideoExportUrl(widget.run.id);
    var opened = false;
    try {
      opened = await widget.openUrl(url);
    } catch (e) {
      debugPrint('Failed to open the video export: $e');
    }
    if (!opened && mounted) {
      showTopBanner(context, AppLocalizations.of(context).shareCardVideoError);
    }
  }

  Widget _videoPanel(AppLocalizations l10n, ThemeData theme, double height) {
    return Container(
      constraints: BoxConstraints(minHeight: height * 0.6),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.movie_outlined,
              size: 40, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            l10n.shareCardVideoBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Future<void> _shareFile(String format) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final tmp = await getTemporaryDirectory();
      final run = widget.run;
      final title = widget.title;
      File file;
      switch (format) {
        case 'tcx':
          file = File('${tmp.path}/run-${run.id}.tcx');
          await file.writeAsString(_runToTcx(run, title));
        case 'fit':
          file = File('${tmp.path}/run-${run.id}.fit');
          await file.writeAsBytes(_runToFitBytes(run));
        default:
          file = File('${tmp.path}/run-${run.id}.gpx');
          await file.writeAsString(_runToGpx(run, title));
      }
      if (!mounted) return;
      await shareFilesFrom(context,
          files: [XFile(file.path)], text: _caption(l10n));
    } catch (e) {
      debugPrint('Failed to export run file: $e');
      if (mounted) {
        showTopBanner(context, AppLocalizations.of(context).shareCardFileError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The canvas the PNG is cut from, at its fixed logical size.
  Widget _canvas() {
    switch (_style) {
      case RunShareStyle.card:
        return SizedBox.fromSize(
          size: RunShareCard.canvas,
          child: RunShareCard(
            run: widget.run,
            preferences: widget.preferences,
            title: widget.title,
            privacyZones: widget.privacyZones,
            tileReadiness: _tiles,
            mark: _look.mark,
            mascot: widget.showMascot,
          ),
        );
      case RunShareStyle.photo:
        return RunPhotoShareCard(
          run: widget.run,
          preferences: widget.preferences,
          title: widget.title,
          privacyZones: widget.privacyZones,
          photo: FileImage(_photo!),
          look: _look,
          probe: _probe,
          occasion: _occasion(AppLocalizations.of(context)),
        );
      case RunShareStyle.video:
      case RunShareStyle.versus:
        throw StateError('${_style.name} draws no canvas here');
      case RunShareStyle.pr:
        return RunPrShareCard(
          run: widget.run,
          record: _record!,
          privacyZones: widget.privacyZones,
          look: _look,
        );
      case RunShareStyle.sticker:
        return RunStickerShareCard(
          run: widget.run,
          preferences: widget.preferences,
          privacyZones: widget.privacyZones,
          look: _look,
          occasion: _occasion(AppLocalizations.of(context)),
        );
    }
  }

  Widget _preview(AppLocalizations l10n, ThemeData theme, double height) {
    final Widget body;
    if (!_hasImage) {
      body = Center(
        child: _picking
            ? const CircularProgressIndicator()
            : FilledButton.tonalIcon(
                onPressed: _pickPhoto,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(l10n.shareCardPickPhoto),
              ),
      );
    } else {
      // The canvas keeps its own fixed size and is scaled to the preview, so
      // the image is the same on every phone. Text scaling is pinned off
      // inside it for the same reason: the OS text size is the viewer's
      // setting, not part of the picture.
      body = Padding(
        padding: const EdgeInsets.all(8),
        child: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: MediaQuery.withNoTextScaling(
              child: _style == RunShareStyle.photo
                  ? _PlacementGestures(
                      probe: _probe,
                      enabled: !_busy,
                      label: l10n.shareCardPlacementLabel,
                      hint: l10n.shareCardPlacementHint,
                      placement: () => _look.placement,
                      onChanged: _movePlacement,
                      onEnd: () => unawaited(saveShareLook(_look)),
                      onReset: _resetPlacement,
                      child: RepaintBoundary(key: _cardKey, child: _canvas()),
                    )
                  : RepaintBoundary(key: _cardKey, child: _canvas()),
            ),
          ),
        ),
      );
    }
    // semantics-children: the preview holds the stats placement control,
    // which keeps its own node
    return Semantics(
      label: l10n.shareCardPreviewLabel,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: height,
          width: double.infinity,
          // The sticker is transparent, so its preview sits on a checkerboard
          // OUTSIDE the boundary: the PNG keeps its alpha.
          child: CustomPaint(
            painter: _style == RunShareStyle.sticker
                ? const _CheckerboardPainter()
                : null,
            child: ColoredBox(
              color: _style == RunShareStyle.sticker
                  ? Colors.transparent
                  : theme.colorScheme.surfaceContainerHighest,
              child: body,
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(ThemeData theme, String label, Widget control) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            control,
          ],
        ),
      );

  String _kindLabel(AppLocalizations l10n, RunStickerKind kind) =>
      switch (kind) {
        RunStickerKind.stats => l10n.shareCardKindStats,
        RunStickerKind.splits => l10n.shareCardKindSplits,
        RunStickerKind.pr => l10n.shareCardKindPr,
        RunStickerKind.streak => l10n.shareCardKindStreak,
        RunStickerKind.race => l10n.shareCardKindRace,
        RunStickerKind.course => l10n.shareCardKindCourse,
        RunStickerKind.badge => l10n.shareCardKindBadge,
        RunStickerKind.route => l10n.shareCardLayoutRoute,
      };

  String _statLabel(AppLocalizations l10n, RunShareStatKind kind) {
    switch (kind) {
      case RunShareStatKind.distance:
        return l10n.shareCardStatDistance;
      case RunShareStatKind.pace:
        final activity = ActivityType.fromName(
            widget.run.metadata?['activity_type'] as String?);
        return activity.usesSpeed
            ? l10n.shareCardStatSpeed
            : l10n.shareCardStatPace;
      case RunShareStatKind.time:
        return l10n.shareCardStatTime;
      case RunShareStatKind.climb:
        return l10n.shareCardStatClimb;
      case RunShareStatKind.heartRate:
        return l10n.shareCardStatHeartRate;
    }
  }

  List<Widget> _lookControls(AppLocalizations l10n, ThemeData theme) {
    final enabled = !_busy;
    final available = availableShareStats(widget.run);
    final pr = _style == RunShareStyle.pr;
    final offered = _offeredKinds;
    final kind = stickerKindFor(_look.kind, offered);
    final stats = !pr && kind == RunStickerKind.stats;
    return [
      if (_usesKinds && offered.length > 1)
        _section(
          theme,
          l10n.shareCardKind,
          ChoiceChipRow<RunStickerKind>(
            options: [
              for (final k in offered)
                ChoiceChipOption(value: k, label: _kindLabel(l10n, k)),
            ],
            selected: kind,
            onChanged:
                enabled ? (v) => _setLook(_look.copyWith(kind: v)) : null,
          ),
        ),
      if ((pr || (_usesKinds && kind == RunStickerKind.pr)) &&
          widget.records.length > 1)
        _section(
          theme,
          l10n.shareCardPrRecord,
          ChoiceChipRow<int>(
            options: [
              for (var i = 0; i < widget.records.length; i++)
                ChoiceChipOption(
                  value: i,
                  label: planRecapBracketLabel(l10n, widget.records[i].distance),
                ),
            ],
            selected: _prIndex.clamp(0, widget.records.length - 1),
            onChanged: enabled ? (v) => setState(() => _prIndex = v) : null,
          ),
        ),
      if (stats)
      _section(
        theme,
        l10n.shareCardLayout,
        ChoiceChipRow<RunStickerLayout>(
          options: [
            ChoiceChipOption(
              value: RunStickerLayout.stack,
              label: l10n.shareCardLayoutStack,
              icon: Icons.view_agenda_outlined,
            ),
            ChoiceChipOption(
              value: RunStickerLayout.route,
              label: l10n.shareCardLayoutRoute,
              icon: Icons.route,
            ),
            ChoiceChipOption(
              value: RunStickerLayout.strip,
              label: l10n.shareCardLayoutStrip,
              icon: Icons.view_week_outlined,
            ),
            ChoiceChipOption(
              value: RunStickerLayout.hero,
              label: l10n.shareCardLayoutHero,
              icon: Icons.looks_one_outlined,
            ),
          ],
          selected: _look.layout,
          onChanged:
              enabled ? (v) => _setLook(_look.copyWith(layout: v)) : null,
        ),
      ),
      _section(
        theme,
        l10n.shareCardInk,
        ChoiceChipRow<RunShareInk>(
          options: [
            ChoiceChipOption(
                value: RunShareInk.light, label: l10n.shareCardInkLight),
            ChoiceChipOption(
                value: RunShareInk.dark, label: l10n.shareCardInkDark),
            ChoiceChipOption(
                value: RunShareInk.brand, label: l10n.shareCardInkBrand),
          ],
          selected: _look.ink,
          onChanged: enabled ? (v) => _setLook(_look.copyWith(ink: v)) : null,
        ),
      ),
      if (_style == RunShareStyle.photo || pr)
        _section(
          theme,
          l10n.shareCardAspect,
          ChoiceChipRow<RunPhotoAspect>(
            options: [
              ChoiceChipOption(
                value: RunPhotoAspect.story,
                label: l10n.shareCardAspectStory,
              ),
              ChoiceChipOption(
                value: RunPhotoAspect.post,
                label: l10n.shareCardAspectPost,
              ),
            ],
            selected: _look.aspect,
            onChanged:
                enabled ? (v) => _setLook(_look.copyWith(aspect: v)) : null,
          ),
        ),
      if (stats)
      _section(
        theme,
        l10n.shareCardStats,
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final kind in available)
              FilterChip(
                label: Text(_statLabel(l10n, kind)),
                selected: _look.stats.contains(kind),
                onSelected: !enabled ||
                        (_look.stats.contains(kind)
                            ? _look.stats.length <= 1
                            : _look.stats.length >= RunShareLook.maxStats)
                    ? null
                    : (_) => _setLook(_look.toggleStat(kind)),
              ),
          ],
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final previewHeight = (mq.size.height * 0.42).clamp(220.0, 440.0);
    return SheetScaffold.floating(
      scrollBody: false,
      body: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.shareCardRunTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            ChoiceChipRow<RunShareStyle>(
              alignment: WrapAlignment.center,
              options: [
                ChoiceChipOption(
                  value: RunShareStyle.card,
                  label: l10n.shareCardStyleCard,
                  icon: Icons.map_outlined,
                ),
                ChoiceChipOption(
                  value: RunShareStyle.photo,
                  label: l10n.shareCardStylePhoto,
                  icon: Icons.photo_outlined,
                ),
                ChoiceChipOption(
                  value: RunShareStyle.sticker,
                  label: l10n.shareCardStyleSticker,
                  icon: Icons.auto_awesome_motion_outlined,
                ),
                if (_canOfferVideo)
                  ChoiceChipOption(
                    value: RunShareStyle.video,
                    label: l10n.shareCardStyleVideo,
                    icon: Icons.movie_outlined,
                  ),
                if (widget.headToHeadLoad != null)
                  ChoiceChipOption(
                    value: RunShareStyle.versus,
                    label: l10n.headToHeadStyleVersus,
                    icon: Icons.people_outline,
                  ),
                if (widget.records.isNotEmpty)
                  ChoiceChipOption(
                    value: RunShareStyle.pr,
                    label: l10n.shareCardStylePr,
                    icon: Icons.military_tech,
                  ),
              ],
              selected: _style,
              onChanged: _busy ? null : _selectStyle,
            ),
            const SizedBox(height: 12),
            if (_style == RunShareStyle.video)
              _videoPanel(l10n, theme, previewHeight)
            else if (_style == RunShareStyle.versus)
              HeadToHeadPanel(
                load: widget.headToHeadLoad!,
                fileName: 'threkir-run-${widget.run.id}-versus',
                saveImage: widget.saveImage,
              )
            else
              _preview(l10n, theme, previewHeight),
            if (_style == RunShareStyle.photo && _photo != null) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.shareCardPlacementHint,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: _busy || _picking ? null : _pickPhoto,
                    icon: const Icon(Icons.swap_horiz),
                    label: Text(l10n.shareCardChangePhoto),
                  ),
                  TextButton.icon(
                    key: const ValueKey('share-placement-reset'),
                    onPressed: _busy ||
                            _look.placement == SharePlacement.initial
                        ? null
                        : _resetPlacement,
                    icon: const Icon(Icons.restart_alt),
                    label: Text(l10n.shareCardPlacementReset),
                  ),
                ],
              ),
            ],
            if (_style == RunShareStyle.sticker ||
                _style == RunShareStyle.pr)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _style == RunShareStyle.pr
                      ? l10n.shareCardPrHint
                      : l10n.shareCardStickerHint,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (_style != RunShareStyle.card &&
                _style != RunShareStyle.video &&
                _style != RunShareStyle.versus)
              ..._lookControls(l10n, theme),
            if (_style != RunShareStyle.video &&
                _style != RunShareStyle.versus)
              // A Row, not a SwitchListTile: the sheet's tinted
              // container would hide a ListTile's ink.
              MergeSemantics(
                child: Row(
                  children: [
                    Expanded(child: Text(l10n.shareCardMark)),
                    Switch(
                      key: const ValueKey('share-mark'),
                      value: _look.mark,
                      onChanged: _busy
                          ? null
                          : (v) => _setLook(_look.copyWith(mark: v)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            if (_style == RunShareStyle.video)
              FilledButton.icon(
                onPressed: _busy ? null : _openVideoExport,
                icon: const Icon(Icons.open_in_new),
                label: Text(l10n.shareCardVideoOpen),
              )
            else if (_style != RunShareStyle.versus) ...[
              // Stacked full width: the save label is the one the iOS photo
              // permission prompt names, and in French or Portuguese it
              // does not fit half a row.
              FilledButton.icon(
                onPressed: _canExportImage ? _shareImage : null,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.ios_share),
                label: Text(l10n.shareCardImage),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _canExportImage ? _saveImage : null,
                icon: const Icon(Icons.download_outlined),
                label: Text(l10n.shareCardSave),
              ),
            ],
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                if (widget.onShareLink != null)
                  TextButton.icon(
                    key: const ValueKey('share-run-link'),
                    onPressed: _busy ? null : widget.onShareLink,
                    icon: const Icon(Icons.link),
                    label: Text(l10n.shareCardShareLink),
                  ),
                PopupMenuButton<String>(
                  onSelected: _busy ? null : _shareFile,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'gpx', child: Text('GPX')),
                    PopupMenuItem(value: 'tcx', child: Text('TCX')),
                    PopupMenuItem(value: 'fit', child: Text('FIT')),
                  ],
                  child: TextButton.icon(
                    onPressed: _busy ? null : () {},
                    icon: const Icon(Icons.route),
                    label: Text(l10n.shareCardExport),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Moves and resizes the photo's title-and-stats block on the preview: a
/// one-finger drag moves it, a pinch resizes it, a double tap puts it back.
/// Only a gesture that starts on the block is taken, so a drag anywhere else
/// on the preview still scrolls the sheet; [child] sits at the canvas's own
/// logical size, so the gesture's offsets are canvas px.
class _PlacementGestures extends StatefulWidget {
  final SharePlacementProbe probe;
  final bool enabled;
  final String label;
  final String hint;
  final SharePlacement Function() placement;
  final ValueChanged<SharePlacement> onChanged;
  final VoidCallback onEnd;
  final VoidCallback onReset;
  final Widget child;

  const _PlacementGestures({
    required this.probe,
    required this.enabled,
    required this.label,
    required this.hint,
    required this.placement,
    required this.onChanged,
    required this.onEnd,
    required this.onReset,
    required this.child,
  });

  @override
  State<_PlacementGestures> createState() => _PlacementGesturesState();
}

class _PlacementGesturesState extends State<_PlacementGestures> {
  SharePlacement? _from;
  Offset _focal = Offset.zero;

  bool _onBlock(Offset local) =>
      widget.enabled && (widget.probe.placed?.rect.contains(local) ?? false);

  void _start(ScaleStartDetails d) {
    _from = widget.probe.placed?.placement ?? widget.placement();
    _focal = d.localFocalPoint;
  }

  void _update(ScaleUpdateDetails d) {
    final from = _from;
    final canvas = widget.probe.canvas;
    if (from == null || canvas == null) return;
    final delta = d.localFocalPoint - _focal;
    widget.onChanged(widget.probe
        .clamp(from.moved(delta.dx, delta.dy, canvas).resized(d.scale)));
  }

  void _end(ScaleEndDetails _) {
    if (_from == null) return;
    _from = null;
    widget.onEnd();
  }

  @override
  Widget build(BuildContext context) {
    // semantics-children: names the gesture surface; the blocks it moves keep their own nodes
    return Semantics(
      container: true,
      label: widget.label,
      hint: widget.hint,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          _BlockScaleRecognizer: GestureRecognizerFactoryWithHandlers<
              _BlockScaleRecognizer>(
            () => _BlockScaleRecognizer(_onBlock, debugOwner: this),
            (r) => r
              ..onStart = _start
              ..onUpdate = _update
              ..onEnd = _end,
          ),
          _BlockDoubleTapRecognizer: GestureRecognizerFactoryWithHandlers<
              _BlockDoubleTapRecognizer>(
            () => _BlockDoubleTapRecognizer(_onBlock, debugOwner: this),
            (r) => r.onDoubleTap = widget.onReset,
          ),
        },
        child: widget.child,
      ),
    );
  }
}

/// A scale gesture that starts only on the block, and claims the pointer as
/// soon as it moves a few px: under the sheet scroll's and the bottom sheet's
/// 18 px drag slop, so a drag on the block moves the block rather than the
/// sheet. A second finger may land anywhere once the first is down.
class _BlockScaleRecognizer extends ScaleGestureRecognizer {
  _BlockScaleRecognizer(this._onBlock, {super.debugOwner});

  final bool Function(Offset local) _onBlock;
  final Map<int, Offset> _downs = {};
  bool _claimed = false;

  static const double _claimSlop = 4;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      (_downs.isNotEmpty || _onBlock(event.localPosition)) &&
      super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _downs[event.pointer] = event.position;
    super.addAllowedPointer(event);
    if (_claimed) resolvePointer(event.pointer, GestureDisposition.accepted);
  }

  @override
  void handleEvent(PointerEvent event) {
    super.handleEvent(event);
    final down = _downs[event.pointer];
    if (!_claimed &&
        event is PointerMoveEvent &&
        down != null &&
        (event.position - down).distance > _claimSlop) {
      _claimed = true;
      resolve(GestureDisposition.accepted);
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _forget(event.pointer);
    }
  }

  @override
  void rejectGesture(int pointer) {
    _forget(pointer);
    super.rejectGesture(pointer);
  }

  void _forget(int pointer) {
    _downs.remove(pointer);
    if (_downs.isEmpty) _claimed = false;
  }
}

class _BlockDoubleTapRecognizer extends DoubleTapGestureRecognizer {
  _BlockDoubleTapRecognizer(this._onBlock, {super.debugOwner});

  final bool Function(Offset local) _onBlock;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      _onBlock(event.localPosition) && super.isPointerAllowed(event);
}

class _CheckerboardPainter extends CustomPainter {
  const _CheckerboardPainter();

  static const double _cell = 12;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.grey.shade700);
    final dark = Paint()..color = Colors.grey.shade800;
    for (var y = 0; y * _cell < size.height; y++) {
      for (var x = 0; x * _cell < size.width; x++) {
        if ((x + y).isOdd) continue;
        canvas.drawRect(
            Rect.fromLTWH(x * _cell, y * _cell, _cell, _cell), dark);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerboardPainter oldDelegate) => false;
}

/// Portrait run share card — route map on top, headline stats on the bottom
/// over a dark background. Wrap in a [RepaintBoundary] and grab it via
/// [RenderRepaintBoundary.toImage] to produce a shareable PNG. Intended to
/// be rendered at a 4:5 aspect ratio.
class RunShareCard extends StatelessWidget {
  final Run run;
  final Preferences preferences;
  final String title;

  /// The owner's privacy zones; the drawn line is [runShareCardTrack] of them.
  /// Required, like the sheet's, so a new mount cannot draw the unclipped
  /// track by omission.
  final List<PrivacyZone> privacyZones;

  /// Set by the sheet that rasterises this card, so it can wait for the
  /// basemap instead of sleeping. Null for a plain on-screen render.
  final MapTileReadiness? tileReadiness;

  /// Whether the card's footer carries the Threkir mark; off when the runner
  /// turned it off in the sheet.
  final bool mark;

  /// Whether Grisnir sits beside the title. He travels with the [mark], so
  /// the sheet's mark switch drops him too; this is the runner's standing
  /// `show_mascot` choice.
  final bool mascot;

  const RunShareCard({
    super.key,
    required this.run,
    required this.preferences,
    required this.title,
    required this.privacyZones,
    this.tileReadiness,
    this.mark = true,
    this.mascot = true,
  });

  /// Tile URL for the share card. Honours the `TILE_URL_TEMPLATE`
  /// override (local Protomaps dev — see `live_run_map.dart`
  /// currentTileUrl) so screenshots taken on the local dev stack
  /// show real tiles instead of MapTiler 403s. Falls back to the
  /// MapTiler `streets-v2-dark` style keyed by `MAPTILER_KEY` in
  /// production.
  ///
  /// Pinned to the dark basemap rather than following the device theme
  /// or the user's map-style preference: the card rasterises a fixed
  /// dark PNG whose white type and overlays are drawn for a dark map.
  String get _tileUrl => tileUrlFor('dark', Brightness.dark);

  /// The card's fixed logical size: the sheet scales it to the preview and
  /// rasterises it to [shareImageExportWidthPx] across, so the stats row is
  /// laid out at one width on every phone.
  static const Size canvas = Size(360, 450);

  @override
  Widget build(BuildContext context) {
    final unit = preferences.unit;
    final l10n = AppLocalizations.of(context);
    final activity =
        ActivityType.fromName(run.metadata?['activity_type'] as String?);
    final track = runShareCardTrack(run, privacyZones)
        .map((w) => LatLng(w.lineLat, w.lineLng))
        .toList();

    return Container(
      color: const Color(0xFF121117),
      child: Column(
        children: [
          Expanded(flex: 3, child: _buildMap(track)),
          Expanded(
            flex: 2,
            child: _buildStats(l10n, activity, unit),
          ),
        ],
      ),
    );
  }

  Widget _buildMap(List<LatLng> track) {
    if (track.length < 2) {
      return const Center(
        child: Icon(Icons.directions_run,
            size: 96, color: Color(0xFFC24E24)),
      );
    }

    // Compute spans so we can fall back to centre+zoom when every point is
    // identical (e.g. a treadmill run that still logged one stationary fix).
    double minLat = track.first.latitude, maxLat = track.first.latitude;
    double minLng = track.first.longitude, maxLng = track.first.longitude;
    for (final p in track) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final hasSpan =
        (maxLat - minLat) > 1e-6 || (maxLng - minLng) > 1e-6;

    final options = hasSpan
        ? MapOptions(
            backgroundColor: basemapVoidColour(darkBasemap: true),
            initialCameraFit: CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(track),
              padding: const EdgeInsets.all(40),
            ),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          )
        : MapOptions(
            backgroundColor: basemapVoidColour(darkBasemap: true),
            initialCenter: track.first,
            initialZoom: 16,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          );

    return FlutterMap(
      options: options,
      children: [
        basemapTileLayer(
          urlTemplate: _tileUrl,
          tileBuilder: tileReadiness?.observe,
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: track,
              strokeWidth: 14,
              color: const Color(0xFFF08A5D).withValues(alpha: 0.18),
            ),
          ],
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: track,
              strokeWidth: 6,
              gradientColors: const [
                Color(0xFFC24E24),
                Color(0xFFF08A5D),
                Color(0xFFF8B597),
              ],
              borderStrokeWidth: 2,
              borderColor: const Color(0xFF1A0E08),
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: track.first,
              width: 18,
              height: 18,
              child: _endpointDot(const Color(0xFF34D399)),
            ),
            Marker(
              point: track.last,
              width: 18,
              height: 18,
              child: _endpointDot(const Color(0xFFF87171)),
            ),
          ],
        ),
        const MapAttribution(darkBasemap: true),
      ],
    );
  }

  Widget _endpointDot(Color color) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: 3),
      ),
    );
  }

  Widget _buildStats(
    AppLocalizations l10n,
    ActivityType activity,
    DistanceUnit unit,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Grisnir signs the top-right corner of the stats panel, beside the
          // title, which ellipsises short of him: never on the map or a number.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${activityTypeLabel(l10n, activity)} · ${formatDateMed(run.startedAt, activeLocaleTag)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFA9A4B6),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              if (mark && mascot) ...[
                const SizedBox(width: 10),
                Image.asset(
                  kGrisnirBadgeAsset,
                  key: const ValueKey('share-card-grisnir'),
                  height: 48,
                  excludeFromSemantics: true,
                  filterQuality: FilterQuality.medium,
                ),
              ],
            ],
          ),
          // Each stat takes a third and scales down inside it: a long pace in
          // a long locale used to push the row 47 px past the card.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (i, stat) in runShareStats(l10n, run, unit).indexed) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: i == 0
                        ? Alignment.bottomLeft
                        : i == 2
                            ? Alignment.bottomRight
                            : Alignment.bottomCenter,
                    child: _stat(
                      label: stat.label,
                      value: stat.value,
                      unitLabel: stat.unit,
                    ),
                  ),
                ),
              ],
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: mark
                    ? const Align(
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: ThrekirShareBrand(
                              color: Colors.white, markSize: 16),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const Text(
                '© MapTiler · OpenStreetMap',
                style: TextStyle(
                  color: Color(0xFF8A8496),
                  fontSize: 8,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat({
    required String label,
    required String value,
    String? unitLabel,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Color(0xFFA9A4B6),
            fontSize: 9,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.0,
              ),
            ),
            if (unitLabel != null) ...[
              const SizedBox(width: 3),
              Text(
                unitLabel,
                style: const TextStyle(
                  color: Color(0xFFA9A4B6),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

}

/// The GPX, TCX and FIT exports carry the run's line ([trackLine]), as every
/// server export does: off-track fixes are distance input, not path.
String _runToGpx(Run r, String title) {
  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  final buf = StringBuffer();
  buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  buf.writeln(
      '<gpx version="1.1" creator="Run" xmlns="http://www.topografix.com/GPX/1/1">');
  buf.writeln('  <metadata>');
  buf.writeln('    <name>${esc(title)}</name>');
  buf.writeln('    <time>${r.startedAt.toUtc().toIso8601String()}</time>');
  buf.writeln('  </metadata>');
  buf.writeln('  <trk>');
  buf.writeln('    <name>${esc(title)}</name>');
  buf.writeln('    <trkseg>');
  for (final w in trackLine(r.track)) {
    buf.write('      <trkpt lat="${w.lat}" lon="${w.lng}">');
    if (w.elevationMetres != null) {
      buf.write('<ele>${w.elevationMetres}</ele>');
    }
    if (w.timestamp != null) {
      buf.write('<time>${w.timestamp!.toUtc().toIso8601String()}</time>');
    }
    buf.writeln('</trkpt>');
  }
  buf.writeln('    </trkseg>');
  buf.writeln('  </trk>');
  buf.writeln('</gpx>');
  return buf.toString();
}

String _runToTcx(Run r, String title) {
  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  final buf = StringBuffer();
  buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  buf.writeln(
      '<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">');
  buf.writeln('  <Activities>');
  buf.writeln('    <Activity Sport="Running">');
  buf.writeln(
      '      <Id>${r.startedAt.toUtc().toIso8601String()}</Id>');
  buf.writeln('      <Notes>${esc(title)}</Notes>');
  buf.writeln('      <Lap StartTime="${r.startedAt.toUtc().toIso8601String()}">');
  buf.writeln(
      '        <TotalTimeSeconds>${r.duration.inSeconds}</TotalTimeSeconds>');
  buf.writeln(
      '        <DistanceMeters>${r.distanceMetres.toStringAsFixed(1)}</DistanceMeters>');
  buf.writeln('        <Track>');
  for (final w in trackLine(r.track)) {
    buf.writeln('          <Trackpoint>');
    if (w.timestamp != null) {
      buf.writeln(
          '            <Time>${w.timestamp!.toUtc().toIso8601String()}</Time>');
    }
    buf.writeln('            <Position>');
    buf.writeln('              <LatitudeDegrees>${w.lat}</LatitudeDegrees>');
    buf.writeln('              <LongitudeDegrees>${w.lng}</LongitudeDegrees>');
    buf.writeln('            </Position>');
    if (w.elevationMetres != null) {
      buf.writeln(
          '            <AltitudeMeters>${w.elevationMetres}</AltitudeMeters>');
    }
    buf.writeln('          </Trackpoint>');
  }
  buf.writeln('        </Track>');
  buf.writeln('      </Lap>');
  buf.writeln('    </Activity>');
  buf.writeln('  </Activities>');
  buf.writeln('</TrainingCenterDatabase>');
  return buf.toString();
}

List<int> _runToFitBytes(Run r) {
  // FIT epoch: 1989-12-31 00:00:00 UTC
  final fitEpoch = DateTime.utc(1989, 12, 31);
  int fitTimestamp(DateTime dt) => dt.difference(fitEpoch).inSeconds;
  int semicircles(double degrees) => (degrees * (1 << 31) / 180).round();

  final out = <int>[];

  void writeU8(int v) => out.add(v & 0xFF);
  void writeU16LE(int v) {
    out.add(v & 0xFF);
    out.add((v >> 8) & 0xFF);
  }
  void writeU32LE(int v) {
    out.add(v & 0xFF);
    out.add((v >> 8) & 0xFF);
    out.add((v >> 16) & 0xFF);
    out.add((v >> 24) & 0xFF);
  }
  void writeSint32LE(int v) => writeU32LE(v < 0 ? v + 0x100000000 : v);

  // Definition message helper. Returns the local message type used.
  void writeDefinition({
    required int localType,
    required int globalMesgNum,
    required List<List<int>> fields,
  }) {
    writeU8(0x40 | (localType & 0x0F)); // definition header
    writeU8(0); // reserved
    writeU8(0); // little-endian
    writeU16LE(globalMesgNum);
    writeU8(fields.length);
    for (final f in fields) {
      writeU8(f[0]); // field num
      writeU8(f[1]); // size
      writeU8(f[2]); // base type
    }
  }

  // Data message helper.
  void writeDataHeader(int localType) {
    writeU8(localType & 0x0F);
  }

  // -- File header (14 bytes, written at the end with correct data size) --
  for (var i = 0; i < 14; i++) out.add(0); // placeholder

  // -- File ID message (mesg 0) --
  writeDefinition(localType: 0, globalMesgNum: 0, fields: [
    [0, 1, 0],   // type: enum (4=activity)
    [1, 2, 132], // manufacturer: uint16
    [3, 4, 134], // serial: uint32z
    [4, 4, 134], // time_created: uint32
  ]);
  writeDataHeader(0);
  writeU8(4); // type = activity
  writeU16LE(1); // manufacturer = 1 (Garmin, generic)
  writeU32LE(12345); // serial
  writeU32LE(fitTimestamp(r.startedAt));

  // -- Record messages (mesg 20) --
  writeDefinition(localType: 1, globalMesgNum: 20, fields: [
    [253, 4, 134], // timestamp: uint32
    [0, 4, 133],   // position_lat: sint32
    [1, 4, 133],   // position_lng: sint32
    [2, 2, 132],   // altitude: uint16 (scale 5, offset 500)
  ]);
  for (final w in trackLine(r.track)) {
    writeDataHeader(1);
    writeU32LE(fitTimestamp(w.timestamp ?? r.startedAt));
    writeSint32LE(semicircles(w.lat));
    writeSint32LE(semicircles(w.lng));
    final alt = w.elevationMetres ?? 0;
    writeU16LE(((alt + 500) * 5).round().clamp(0, 0xFFFF));
  }

  // -- Patch file header --
  final dataSize = out.length - 14;
  out[0] = 14; // header size
  out[1] = 20; // protocol version (2.0)
  out[2] = 0x08; // profile version low
  out[3] = 0x08; // profile version high
  out[4] = dataSize & 0xFF;
  out[5] = (dataSize >> 8) & 0xFF;
  out[6] = (dataSize >> 16) & 0xFF;
  out[7] = (dataSize >> 24) & 0xFF;
  // ".FIT" signature
  out[8] = 0x2E; // '.'
  out[9] = 0x46; // 'F'
  out[10] = 0x49; // 'I'
  out[11] = 0x54; // 'T'
  // Header CRC (2 bytes) — set to 0 (optional per spec)
  out[12] = 0;
  out[13] = 0;

  // -- Data CRC --
  var crc = 0;
  for (var i = 14; i < out.length; i++) {
    crc = fitCrc(crc, out[i]);
  }
  out.add(crc & 0xFF);
  out.add((crc >> 8) & 0xFF);

  return out;
}

@visibleForTesting
int fitCrc(int crc, int byte) {
  const table = [
    0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
    0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400,
  ];
  var tmp = table[crc & 0xF] ^ table[byte & 0xF];
  crc = (crc >> 4) & 0x0FFF;
  crc = crc ^ tmp ^ table[(byte >> 4) & 0xF];
  return crc;
}

/// "#2 in November", or "#2 in November · #9 in 2026" when the year place is
/// one the sticker prints (`shareCoursePlaces`); null when the time holds no
/// month place. Mirrors web `RunShareImageDialog.courseRankLine`.
String? _courseRankLine(AppLocalizations l10n, RunParkCourseTime course) {
  final places = shareCoursePlaces(course);
  final monthRank = places.monthRank;
  if (monthRank == null) return null;
  final month =
      formatMonthName(DateTime(course.season, course.month), activeLocaleTag);
  final seasonRank = places.seasonRank;
  return seasonRank == null
      ? l10n.shareCardCourseMonthRank('$monthRank', month)
      : l10n.shareCardCourseRanks(
          '$monthRank', month, '$seasonRank', '${course.season}');
}

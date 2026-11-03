import 'dart:async' show unawaited;
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart' show ImagePicker, ImageSource;
import 'package:latlong2/latlong.dart' hide Path;
import 'package:path_provider/path_provider.dart';
import 'package:ui_kit/ui_kit.dart' show ChoiceChipOption, ChoiceChipRow;

import 'live_run_map.dart'
    show basemapTileLayer, basemapVoidColour, tileUrlFor;
import 'map_attribution.dart';

import '../l10n/date_format.dart';
import '../map_tile_readiness.dart';
import '../activity_type_labels.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../preferences.dart';
import '../privacy.dart';
import '../run_stats.dart';
import '../share_sheet.dart';
import 'capture_png.dart';
import 'track_preview.dart' show projectTrack;
import '../widgets/top_banner.dart';

/// The part of [run]'s track the share card draws: the stored track with its
/// leading and trailing fixes inside any of the owner's [zones] trimmed, by the
/// rule `clip_track_for_user` applies before a non-owner is served the same
/// run (raw OR smoothed position in a zone, interior passes kept). Always
/// applied when the owner has zones, with no opt-out: the PNG leaves the
/// device and is posted where anyone can read it, so it must withhold exactly
/// what the public run page withholds. Drawn from [trackLine]: an off-track
/// fix is distance input the recorder stored for the server replay, and the
/// public run page never serves one either.
List<Waypoint> runShareCardTrack(Run run, List<PrivacyZone> zones) =>
    clipPointsToZones<Waypoint>(
      trackLine(run.track),
      zones,
      latOf: (w) => w.lat,
      lngOf: (w) => w.lng,
      smoothedLatOf: (w) => w.smoothedLat,
      smoothedLngOf: (w) => w.smoothedLng,
    );

/// Whether the share card for [run] draws a basemap at all, and therefore
/// whether a capture has any tiles to wait for. A clipped track that short
/// renders the activity glyph instead.
bool runShareCardHasMap(Run run, List<PrivacyZone> zones) =>
    runShareCardTrack(run, zones).length >= 2;

/// What the share image is drawn on: the branded map [card], the runner's own
/// [photo] under a scrim, or nothing at all ([sticker], a transparent PNG to
/// lay over a story or photo in another app).
enum RunShareStyle { card, photo, sticker }

/// Opens a modal sheet showing a portrait "share card" for [run] and lets the
/// user share it as a PNG in one of three [RunShareStyle]s, or export the raw
/// GPX / TCX / FIT, via the system share sheet.
///
/// [privacyZones] is required so no entry point can open the sheet without
/// deciding what the image withholds; pass the owner's zones. Every style
/// draws the same clipped line. The GPX / TCX / FIT exports stay the full
/// track: they are the owner's own copy of their data, not a published
/// rendering.
///
/// [pickPhotoOverride] replaces the gallery picker so a widget test can drive
/// the photo style without the image_picker platform channel.
Future<void> showRunShareSheet(
  BuildContext context, {
  required Run run,
  required Preferences preferences,
  required String title,
  required List<PrivacyZone> privacyZones,
  @visibleForTesting Future<XFile?> Function()? pickPhotoOverride,
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
      pickPhotoOverride: pickPhotoOverride,
    ),
  );
}

class _ShareRunSheet extends StatefulWidget {
  final Run run;
  final Preferences preferences;
  final String title;
  final List<PrivacyZone> privacyZones;
  final Future<XFile?> Function()? pickPhotoOverride;

  const _ShareRunSheet({
    required this.run,
    required this.preferences,
    required this.title,
    required this.privacyZones,
    this.pickPhotoOverride,
  });

  @override
  State<_ShareRunSheet> createState() => _ShareRunSheetState();
}

class _ShareRunSheetState extends State<_ShareRunSheet> {
  final GlobalKey _cardKey = GlobalKey();
  final MapTileReadiness _tiles = MapTileReadiness();
  bool _capturing = false;
  RunShareStyle _style = RunShareStyle.card;
  File? _photo;
  bool _picking = false;

  String _caption(AppLocalizations l10n) {
    final unit = widget.preferences.unit;
    final dist = UnitFormat.distance(widget.run.distanceMetres, unit);
    return l10n.shareCardCaption(
      widget.title,
      dist,
      _formatDuration(widget.run.duration),
    );
  }

  bool get _canShareImage =>
      !_capturing && (_style != RunShareStyle.photo || _photo != null);

  Future<XFile?> _pick() {
    final override = widget.pickPhotoOverride;
    if (override != null) return override();
    // The pick is re-rasterised into the share PNG, so the original's EXIF
    // (GPS included) never leaves the device. 2048 px covers the 3x capture.
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

  Future<void> _shareImage() async {
    if (!_canShareImage) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _capturing = true);
    try {
      // Wait for the tiles the card is actually showing, not for a guessed
      // interval: a fixed sleep rasterised a part-black map whenever a cold
      // fetch outran it, and made every cached share wait for nothing. Only
      // the card style draws a basemap.
      if (_style == RunShareStyle.card &&
          runShareCardHasMap(widget.run, widget.privacyZones)) {
        await _tiles.settled();
      }
      await WidgetsBinding.instance.endOfFrame;

      final bytes = await capturePngBytes(_cardKey);

      final tmp = await getTemporaryDirectory();
      final file =
          File('${tmp.path}/run-${widget.run.id}-${_style.name}.png');
      await file.writeAsBytes(bytes);

      if (!mounted) return;
      await shareFilesFrom(
        context,
        files: [XFile(file.path, mimeType: 'image/png')],
        text: _caption(l10n),
      );
    } catch (e) {
      debugPrint('Failed to capture run share card: $e');
      if (mounted) {
        showTopBanner(
            context, AppLocalizations.of(context).shareCardImageError);
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _shareFile(String format) async {
    final l10n = AppLocalizations.of(context);
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
    }
  }

  Widget _preview(AppLocalizations l10n, ThemeData theme) {
    switch (_style) {
      case RunShareStyle.card:
        return RunShareCard(
          run: widget.run,
          preferences: widget.preferences,
          title: widget.title,
          privacyZones: widget.privacyZones,
          tileReadiness: _tiles,
        );
      case RunShareStyle.photo:
        final photo = _photo;
        if (photo == null) {
          return ColoredBox(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Center(
              child: _picking
                  ? const CircularProgressIndicator()
                  : FilledButton.tonalIcon(
                      onPressed: _pickPhoto,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(l10n.shareCardPickPhoto),
                    ),
            ),
          );
        }
        return RunPhotoShareCard(
          run: widget.run,
          preferences: widget.preferences,
          title: widget.title,
          privacyZones: widget.privacyZones,
          photo: FileImage(photo),
        );
      case RunShareStyle.sticker:
        return RunStickerShareCard(
          run: widget.run,
          preferences: widget.preferences,
          privacyZones: widget.privacyZones,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final boundary = RepaintBoundary(
      key: _cardKey,
      child: _preview(l10n, theme),
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + mq.viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(16),
          // Scrolls rather than overflowing on a short phone or at a large
          // text scale: the preview, style row, hint and buttons outgrow
          // 640 dp together.
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.shareCardRunTitle, style: theme.textTheme.titleMedium),
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
                  ],
                  selected: _style,
                  onChanged: _capturing ? null : _selectStyle,
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 4 / 5,
                    // The sticker is transparent, so its preview sits on a
                    // checkerboard OUTSIDE the boundary: the PNG keeps its alpha.
                    child: CustomPaint(
                      painter: _style == RunShareStyle.sticker
                          ? const _CheckerboardPainter()
                          : null,
                      child: boundary,
                    ),
                  ),
                ),
                if (_style == RunShareStyle.photo && _photo != null)
                  TextButton.icon(
                    onPressed: _capturing || _picking ? null : _pickPhoto,
                    icon: const Icon(Icons.swap_horiz),
                    label: Text(l10n.shareCardChangePhoto),
                  ),
                if (_style == RunShareStyle.sticker)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      l10n.shareCardStickerHint,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: PopupMenuButton<String>(
                        onSelected: _capturing ? null : _shareFile,
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'gpx', child: Text('GPX')),
                          PopupMenuItem(value: 'tcx', child: Text('TCX')),
                          PopupMenuItem(value: 'fit', child: Text('FIT')),
                        ],
                        child: OutlinedButton.icon(
                          onPressed: _capturing ? null : () {},
                          icon: const Icon(Icons.route),
                          label: Text(l10n.shareCardExport),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _canShareImage ? _shareImage : null,
                        icon: _capturing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.image_outlined),
                        label: Text(l10n.shareCardImage),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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

  const RunShareCard({
    super.key,
    required this.run,
    required this.preferences,
    required this.title,
    required this.privacyZones,
    this.tileReadiness,
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
          Column(
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final stat in runShareStats(l10n, run, unit))
                _stat(
                  label: stat.label,
                  value: stat.value,
                  unitLabel: stat.unit,
                ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  l10n.shareCardBrandRun,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                    height: 1.0,
                  ),
                ),
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

/// The moving time every share style prints: [movingTimeOf] the stored track,
/// or the elapsed duration when there is no track to measure it from.
Duration runShareMovingTime(Run run) {
  if (run.track.length < 2) return run.duration;
  final computed = movingTimeOf(run.track);
  if (computed.inSeconds == 0) return run.duration;
  return computed;
}

/// Seconds per km over [movingTime], or null when the run is too short to
/// carry a pace.
double? runShareMovingPace(Run run, Duration movingTime) {
  if (run.distanceMetres < 10) return null;
  final seconds = movingTime.inSeconds;
  if (seconds < 1) return null;
  return seconds / (run.distanceMetres / 1000);
}

/// One headline stat as the share styles print it.
typedef RunShareStat = ({String label, String value, String? unit});

/// Distance, moving time and pace (or speed, for a speed activity), in the
/// order every share style lays them out.
List<RunShareStat> runShareStats(
  AppLocalizations l10n,
  Run run,
  DistanceUnit unit,
) {
  final activity =
      ActivityType.fromName(run.metadata?['activity_type'] as String?);
  final moving = runShareMovingTime(run);
  final pace = runShareMovingPace(run, moving);
  return [
    (
      label: l10n.shareCardStatDistance,
      value: UnitFormat.distanceValue(run.distanceMetres, unit),
      unit: UnitFormat.distanceLabel(unit),
    ),
    (
      label: l10n.shareCardStatTime,
      value: _formatDuration(moving),
      unit: null,
    ),
    activity.usesSpeed
        ? (
            label: l10n.shareCardStatSpeed,
            value: UnitFormat.speed(pace, unit),
            unit: UnitFormat.speedLabel(unit),
          )
        : (
            label: l10n.shareCardStatPace,
            value: UnitFormat.pace(pace, unit),
            unit: UnitFormat.paceLabel(unit),
          ),
  ];
}

/// The clipped [runShareCardTrack] as a white outline with no basemap: the
/// line the photo and sticker styles draw. A dark halo keeps it legible on a
/// bright photo. Nothing is drawn under two points.
class RunRouteOutlinePainter extends CustomPainter {
  final List<Waypoint> points;

  const RunRouteOutlinePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || size.isEmpty) return;
    final stroke = size.shortestSide * 0.035;
    final projected =
        projectTrack(points, size.width, size.height, pad: stroke * 2);
    if (projected.length < 2) return;
    final path = Path()..moveTo(projected.first.dx, projected.first.dy);
    for (var i = 1; i < projected.length; i++) {
      path.lineTo(projected[i].dx, projected[i].dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(RunRouteOutlinePainter oldDelegate) =>
      !identical(oldDelegate.points, points);
}

const _overlayShadows = [
  Shadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 1)),
];

/// A stat as the overlay styles print it: white type over whatever lies
/// beneath, held legible by a soft shadow, scaled down rather than clipped
/// when a long value meets a narrow column.
class _OverlayStat extends StatelessWidget {
  final RunShareStat stat;
  final TextStyle? valueStyle;
  final CrossAxisAlignment alignment;

  const _OverlayStat(
    this.stat, {
    required this.valueStyle,
    this.alignment = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final unit = stat.unit;
    return Column(
      crossAxisAlignment: alignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            stat.label.toUpperCase(),
            maxLines: 1,
            style: text.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              shadows: _overlayShadows,
            ),
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                stat.value,
                style: valueStyle?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  shadows: _overlayShadows,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 3),
                Text(
                  unit,
                  style: text.labelMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    shadows: _overlayShadows,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

Widget _overlayBrand(BuildContext context, AppLocalizations l10n) => Text(
      l10n.shareCardBrandRun,
      maxLines: 1,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
            shadows: _overlayShadows,
          ),
    );

/// The run's headline stats and route outline laid over the runner's own
/// [photo], cropped to fill. A scrim darkens the lower half so white type
/// reads on any photo. No basemap: the photo is the ground, and the outline
/// is [runShareCardTrack] of [privacyZones] like every other style.
class RunPhotoShareCard extends StatelessWidget {
  final Run run;
  final Preferences preferences;
  final String title;
  final List<PrivacyZone> privacyZones;
  final ImageProvider photo;

  const RunPhotoShareCard({
    super.key,
    required this.run,
    required this.preferences,
    required this.title,
    required this.privacyZones,
    required this.photo,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final stats = runShareStats(l10n, run, preferences.unit);
    final track = runShareCardTrack(run, privacyZones);
    return Stack(
      fit: StackFit.expand,
      children: [
        Image(image: photo, fit: BoxFit.cover),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.35, 1],
              colors: [
                Colors.black.withValues(alpha: 0),
                Colors.black.withValues(alpha: 0.72),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              if (track.length >= 2)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: 0.38,
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: CustomPaint(
                        painter: RunRouteOutlinePainter(track),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  shadows: _overlayShadows,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final (i, stat) in stats.indexed) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(
                      child: _OverlayStat(stat, valueStyle: text.headlineSmall),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              _overlayBrand(context, l10n),
            ],
          ),
        ),
      ],
    );
  }
}

/// The run's headline stats and route outline on a TRANSPARENT ground, to be
/// saved and laid over a story or photo in another app. White type with a
/// shadow, so it survives being placed on a light photo as well as a dark one.
class RunStickerShareCard extends StatelessWidget {
  final Run run;
  final Preferences preferences;
  final List<PrivacyZone> privacyZones;

  const RunStickerShareCard({
    super.key,
    required this.run,
    required this.preferences,
    required this.privacyZones,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final stats = runShareStats(l10n, run, preferences.unit);
    final track = runShareCardTrack(run, privacyZones);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        children: [
          for (final stat in stats)
            Expanded(
              flex: 2,
              child: Center(
                child: _OverlayStat(
                  stat,
                  valueStyle: text.displaySmall,
                  alignment: CrossAxisAlignment.center,
                ),
              ),
            ),
          if (track.length >= 2)
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: CustomPaint(painter: RunRouteOutlinePainter(track)),
                ),
              ),
            ),
          _overlayBrand(context, l10n),
        ],
      ),
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

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}


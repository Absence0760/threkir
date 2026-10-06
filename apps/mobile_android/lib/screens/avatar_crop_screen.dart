import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../avatar_crop.dart';
import '../avatar_crop_image.dart';
import '../l10n/gen/app_localizations.dart';

/// Push the crop step for a picked profile photo. Resolves to the cropped,
/// rotated, re-encoded JPEG, or null when the user backs out.
Future<Uint8List?> showAvatarCropScreen(
  BuildContext context,
  Uint8List bytes,
) => Navigator.of(context).push<Uint8List>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => AvatarCropScreen(bytes: bytes),
  ),
);

typedef _Prepared = ({img.Image image, Uint8List rgba});

_Prepared? _prepare(Uint8List bytes) {
  final image = decodeOrientedAvatar(bytes);
  if (image == null) return null;
  return (image: image, rgba: rgbaPixels(image));
}

Uint8List _encode(({img.Image image, CropState crop}) job) =>
    encodeAvatarCrop(job.image, job.crop);

enum _Status { loading, ready, failed }

class AvatarCropScreen extends StatefulWidget {
  const AvatarCropScreen({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  State<AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<AvatarCropScreen> {
  // Crop geometry runs in a fixed coordinate square, as on web; gesture deltas
  // are mapped into it through the stage's laid-out side.
  static const double _view = 300;

  _Status _status = _Status.loading;
  img.Image? _source;
  ui.Image? _preview;
  CropState? _crop;
  bool _encoding = false;
  double _gestureStartZoom = 1;
  Offset? _lastFocal;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final prepared = await compute(_prepare, widget.bytes);
      if (prepared == null) {
        if (mounted) setState(() => _status = _Status.failed);
        return;
      }
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        prepared.rgba,
        prepared.image.width,
        prepared.image.height,
        ui.PixelFormat.rgba8888,
        done.complete,
      );
      final preview = await done.future;
      if (!mounted) {
        preview.dispose();
        return;
      }
      setState(() {
        _source = prepared.image;
        _preview = preview;
        _crop = initialCropState(
          prepared.image.width,
          prepared.image.height,
          _view,
        );
        _status = _Status.ready;
      });
    } catch (e) {
      debugPrint('avatar crop decode failed: $e');
      if (mounted) setState(() => _status = _Status.failed);
    }
  }

  void _turn(int direction) {
    final crop = _crop;
    if (crop == null) return;
    setState(() => _crop = rotate(crop, direction));
  }

  Future<void> _confirm() async {
    final source = _source;
    final crop = _crop;
    if (source == null || crop == null || _encoding) return;
    setState(() => _encoding = true);
    try {
      final jpeg = await compute(_encode, (image: source, crop: crop));
      if (!mounted) return;
      Navigator.of(context).pop(jpeg);
    } catch (e) {
      debugPrint('avatar crop encode failed: $e');
      if (mounted) {
        setState(() {
          _encoding = false;
          _status = _Status.failed;
        });
      }
    }
  }

  Widget _stage(double side) {
    final crop = _crop;
    final preview = _preview;
    return GestureDetector(
      key: const Key('avatar-crop-stage'),
      onScaleStart: (d) {
        _gestureStartZoom = _crop?.zoom ?? 1;
        _lastFocal = d.localFocalPoint;
      },
      onScaleUpdate: (d) {
        final current = _crop;
        final last = _lastFocal;
        if (current == null || last == null) return;
        final k = _view / side;
        final delta = d.localFocalPoint - last;
        _lastFocal = d.localFocalPoint;
        var next = panBy(current, delta.dx * k, delta.dy * k);
        if (d.pointerCount > 1)
          next = rezoom(next, _gestureStartZoom * d.scale);
        setState(() => _crop = next);
      },
      child: SizedBox.square(
        dimension: side,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: crop == null || preview == null
                ? Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: AppLocalizations.of(
                        context,
                      ).avatarCropLoading,
                    ),
                  )
                : CustomPaint(
                    painter: _CropPainter(preview, crop),
                    foregroundPainter: _CircleMaskPainter(),
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final crop = _crop;
    final ready = _status == _Status.ready && crop != null;
    return Scaffold(
      appBar: AppBar(
        leading: CloseButton(
          onPressed: _encoding ? null : () => Navigator.of(context).pop(),
        ),
        title: Text(l10n.avatarCropTitle),
      ),
      body: SafeArea(
        child: _status == _Status.failed
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l10n.avatarCropLoadFailed,
                    key: const Key('avatar-crop-error'),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final side = math.max(
                          1.0,
                          math.min(box.maxWidth, box.maxHeight) - 32,
                        );
                        return Center(child: _stage(side));
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      l10n.avatarCropHint,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        IconButton(
                          key: const Key('avatar-crop-rotate-left'),
                          tooltip: l10n.avatarCropRotateLeft,
                          icon: const Icon(Icons.rotate_left),
                          onPressed: ready ? () => _turn(-1) : null,
                        ),
                        Expanded(
                          child: Slider(
                            key: const Key('avatar-crop-zoom'),
                            label: l10n.avatarCropZoom,
                            semanticFormatterCallback: (v) =>
                                '${l10n.avatarCropZoom} ${v.toStringAsFixed(1)}x',
                            min: avatarMinZoom,
                            max: avatarMaxZoom,
                            value: crop?.zoom ?? avatarMinZoom,
                            onChanged: crop != null && ready
                                ? (v) => setState(() => _crop = rezoom(crop, v))
                                : null,
                          ),
                        ),
                        IconButton(
                          key: const Key('avatar-crop-rotate-right'),
                          tooltip: l10n.avatarCropRotateRight,
                          icon: const Icon(Icons.rotate_right),
                          onPressed: ready ? () => _turn(1) : null,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const Key('avatar-crop-confirm'),
                        onPressed: ready && !_encoding ? _confirm : null,
                        child: Text(l10n.avatarCropConfirm),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Paints the crop exactly as `encodeAvatarCrop` cuts it, so the preview is
/// the upload: rotate the source about its centre, then show the crop rect.
class _CropPainter extends CustomPainter {
  _CropPainter(this.image, this.crop);

  final ui.Image image;
  final CropState crop;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = cropRect(crop);
    final rotated = rotatedSize(image.width, image.height, crop.quarterTurns);
    canvas.save();
    canvas.scale(size.width / rect.size);
    canvas.translate(-rect.x.toDouble(), -rect.y.toDouble());
    canvas.translate(rotated.width / 2, rotated.height / 2);
    canvas.rotate(normalizeQuarterTurns(crop.quarterTurns) * math.pi / 2);
    canvas.drawImage(
      image,
      Offset(-image.width / 2, -image.height / 2),
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.image != image || old.crop != crop;
}

/// Avatars render as circles, so the kept region is shown as one; the square
/// corners outside it are dimmed but still part of the upload.
class _CircleMaskPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(Offset.zero & size);
    canvas.drawPath(path, Paint()..color = const Color(0x80000000));
  }

  @override
  bool shouldRepaint(_CircleMaskPainter old) => false;
}

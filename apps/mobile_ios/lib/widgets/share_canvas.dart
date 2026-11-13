import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'capture_png.dart';
import 'run_share_overlays.dart' show shareImageExportWidthPx;

/// A share image's fixed canvas.
///
/// The card is laid out at [canvasSize] logical pixels with the OS text
/// scale pinned off, shown scaled to fit whatever room the preview has, and
/// captured at the canvas size by [captureShareCanvas]. The image is the
/// same on every phone and at every text size: the reader's text setting is
/// theirs, not part of the picture.
///
/// The period summary, the finisher certificate and the route card used to
/// capture the preview itself, at the preview's width and the OS text
/// scale, so on a 360 dp phone a month's "12h 34m" exported as "12h…" and
/// the certificate's bottom lines were cropped out of the PNG at 1.0x
/// (issue #1374 TO-3). `share_canvas_guard_test.dart` fails a capture whose
/// boundary is not built here or with its text scaling pinned off.
class ShareCanvas extends StatelessWidget {
  const ShareCanvas({
    super.key,
    required this.canvasSize,
    required this.captureKey,
    required this.child,
  });

  /// The canvas, in logical pixels. Its aspect is the preview's.
  final Size canvasSize;

  /// The key [captureShareCanvas] captures.
  final GlobalKey captureKey;
  final Widget child;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: canvasSize.aspectRatio,
        child: FittedBox(
          fit: BoxFit.contain,
          child: MediaQuery.withNoTextScaling(
            child: RepaintBoundary(
              key: captureKey,
              child: SizedBox.fromSize(size: canvasSize, child: child),
            ),
          ),
        ),
      );
}

/// The PNG of the [ShareCanvas] under [key], [widthPx] pixels wide whatever
/// size the preview was drawn at.
Future<Uint8List> captureShareCanvas(
  GlobalKey key, {
  required Size canvasSize,
  double widthPx = shareImageExportWidthPx,
}) =>
    capturePngBytes(key, pixelRatio: widthPx / canvasSize.width);

/// Re-encodes a picked photo for a direct message on the device (issue
/// #1216). The upload is drawn from decoded pixels onto a fresh image, so the
/// camera's EXIF / XMP / ICC blocks, GPS position included, never leave the
/// phone; the EXIF orientation is baked into the pixels first so a portrait
/// shot stays upright. The server re-encodes again before anyone reads it.
/// Web twin: `apps/web/src/lib/social/dm_image_encode.ts`.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import 'dm_image.dart';
import 'exif_strip.dart';

enum DmImageEncodeFailure { unreadable, tooLarge }

class DmImageEncodeError implements Exception {
  const DmImageEncodeError(this.kind);

  final DmImageEncodeFailure kind;

  @override
  String toString() => 'DmImageEncodeError(${kind.name})';
}

/// The JPEG qualities tried in turn until the photo fits
/// [kDmImageMaxBytes], the same steps web takes.
const List<int> kDmImageQualitySteps = [kDmImageQuality, 70, 55];

/// [bytes] (a JPEG, PNG or WebP) as a metadata-free JPEG no larger than
/// [kDmImageMaxEdge] on its long edge and [maxBytes] in size. Throws
/// [DmImageEncodeError] for a file that does not decode, or one still too
/// large at the lowest quality.
Uint8List encodeDmImage(Uint8List bytes, {int maxBytes = kDmImageMaxBytes}) {
  img.Image? decoded;
  try {
    decoded = switch (detectImageMime(bytes)) {
      'image/jpeg' => img.decodeJpg(bytes),
      'image/png' => img.decodePng(bytes),
      'image/webp' => img.decodeWebP(bytes),
      _ => null,
    };
  } catch (_) {
    decoded = null;
  }
  if (decoded == null || decoded.width < 1 || decoded.height < 1) {
    throw const DmImageEncodeError(DmImageEncodeFailure.unreadable);
  }
  final oriented = img.bakeOrientation(decoded);
  final fit = dmImageFit(oriented.width, oriented.height);
  if (fit.width == 0 || fit.height == 0) {
    throw const DmImageEncodeError(DmImageEncodeFailure.unreadable);
  }
  final scaled = fit.width == oriented.width && fit.height == oriented.height
      ? oriented
      : img.copyResize(
          oriented,
          width: fit.width,
          height: fit.height,
          interpolation: img.Interpolation.average,
        );
  final pixels = img.Image(width: fit.width, height: fit.height)
    ..clear(img.ColorRgb8(255, 255, 255));
  img.compositeImage(pixels, scaled);
  for (final quality in kDmImageQualitySteps) {
    final jpeg = img.encodeJpg(pixels, quality: quality);
    if (jpeg.length <= maxBytes) return jpeg;
  }
  throw const DmImageEncodeError(DmImageEncodeFailure.tooLarge);
}

/// [encodeDmImage] off the UI isolate: decoding and re-encoding a 12 MP
/// photo takes long enough to drop frames.
Future<Uint8List> encodeDmImageInBackground(Uint8List bytes) =>
    compute(encodeDmImage, bytes);

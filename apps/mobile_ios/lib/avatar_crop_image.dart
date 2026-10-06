import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'avatar_crop.dart';
import 'exif_strip.dart';

/// Longest side the crop step works at. image_picker already caps the pick at
/// 1024 px; this bounds memory for a source that arrives larger anyway.
const int avatarWorkingMaxPx = 2048;
const int _jpegQuality = 90;

/// Decode [bytes] with its EXIF orientation baked into the pixels, so a phone
/// photo stored sideways with an Orientation tag arrives upright. The result
/// carries no EXIF at all: the upload is re-encoded from these pixels, and
/// nothing from the original's metadata (GPS included) may ride along. Returns
/// null for anything but JPEG, PNG or WebP; a corrupt body in one of those
/// throws, which the caller reports.
img.Image? decodeOrientedAvatar(Uint8List bytes) {
  final decoded = switch (detectImageMime(bytes)) {
    'image/jpeg' => img.decodeJpg(bytes),
    'image/png' => img.decodePng(bytes),
    'image/webp' => img.decodeWebP(bytes),
    _ => null,
  };
  if (decoded == null || decoded.width < 1 || decoded.height < 1) return null;
  var oriented = img.bakeOrientation(decoded);
  final longest = math.max(oriented.width, oriented.height);
  if (longest > avatarWorkingMaxPx) {
    oriented = oriented.width >= oriented.height
        ? img.copyResize(
            oriented,
            width: avatarWorkingMaxPx,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            oriented,
            height: avatarWorkingMaxPx,
            interpolation: img.Interpolation.average,
          );
  }
  oriented.exif = img.ExifData();
  return oriented;
}

/// Rotate, crop and downscale [oriented] per [state], flatten any alpha onto
/// white, and encode a JPEG. Mirrors web's `drawAvatarCrop`: rotate first,
/// crop in rotated space second.
Uint8List encodeAvatarCrop(img.Image oriented, CropState state) {
  final rect = cropRect(state);
  final turned = normalizeQuarterTurns(state.quarterTurns) == 0
      ? oriented
      : img.copyRotate(
          oriented,
          angle: normalizeQuarterTurns(state.quarterTurns) * 90,
        );
  var square = img.copyCrop(
    turned,
    x: rect.x,
    y: rect.y,
    width: rect.size,
    height: rect.size,
  );
  final px = outputSize(rect.size);
  if (px != rect.size) {
    square = img.copyResize(
      square,
      width: px,
      height: px,
      interpolation: img.Interpolation.average,
    );
  }
  final out = img.Image(width: px, height: px)
    ..clear(img.ColorRgb8(255, 255, 255));
  img.compositeImage(out, square);
  return img.encodeJpg(out, quality: _jpegQuality);
}

/// RGBA8 pixels of [image] for `ui.decodeImageFromPixels`, so the on-screen
/// preview paints the exact pixels the upload is cut from.
Uint8List rgbaPixels(img.Image image) =>
    image.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba);

import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

import 'package:flutter/foundation.dart' show immutable;

/// Where the title-and-stats block sits on a photo share image, and how big it
/// is. Twin of apps/web/src/lib/share/share_placement.ts: the same frame,
/// scale bounds, clamp and fail-closed decode.
///
/// A placement is the block's centre as fractions of the canvas width ([x])
/// and height ([y]), plus its size as a multiple of the size it is laid out at
/// ([scale]), so it means the same thing on the fixed 360 px logical canvas,
/// in the sheet's preview at any size, and in the 1080 px export.
@immutable
class SharePlacement {
  final double x;
  final double y;
  final double scale;

  const SharePlacement({required this.x, required this.y, required this.scale});

  /// Centred, and as low as the frame lets it sit: [y] 1 clamps the block
  /// onto the frame's bottom edge, which is where the stats sat before they
  /// could move.
  static const initial = SharePlacement(x: 0.5, y: 1, scale: 1);

  /// The block is laid out at the frame's full width (320 of the canvas's 360
  /// logical px), so it cannot grow past the size it is laid out at without
  /// leaving the frame.
  static const double maxScale = 1;

  /// The smallest size, in logical px, the block's smallest text may shrink
  /// to: 18 px on the 1080 px export. The default strip layout already draws
  /// its 12 px labels at 12 × 320 / 560 = 6.86 px, so this lets a block shrink
  /// to about an eighth under the smallest text the share images ship by
  /// default.
  static const double minTextPx = 6;

  /// The block's 12 px labels at the smallest text floor: 6 / 12.
  static const double minScale = 0.5;

  /// `this` moved by [dx] × [dy] logical px on a [canvas]. Unclamped: place it
  /// again to keep it in the frame.
  SharePlacement moved(double dx, double dy, Size canvas) => SharePlacement(
        x: x + dx / canvas.width,
        y: y + dy / canvas.height,
        scale: scale,
      );

  /// `this` resized by [factor] about its centre. Unclamped.
  SharePlacement resized(double factor) =>
      SharePlacement(x: x, y: y, scale: scale * factor);

  Map<String, double> toJson() => {'x': x, 'y': y, 'scale': scale};

  /// A stored placement, or [initial] when any of its three values is missing,
  /// not a number, or outside the range a placement can hold. Fails closed as
  /// a whole: a centre with no trustworthy scale is not a placement.
  factory SharePlacement.fromJson(Object? json) {
    if (json is! Map) return initial;
    double? inRange(Object? v, double lo, double hi) {
      if (v is! num) return null;
      final d = v.toDouble();
      return d.isFinite && d >= lo && d <= hi ? d : null;
    }

    final x = inRange(json['x'], 0, 1);
    final y = inRange(json['y'], 0, 1);
    final scale = inRange(json['scale'], minScale, maxScale);
    if (x == null || y == null || scale == null) return initial;
    return SharePlacement(x: x, y: y, scale: scale);
  }

  @override
  bool operator ==(Object other) =>
      other is SharePlacement &&
      other.x == x &&
      other.y == y &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(x, y, scale);

  @override
  String toString() => 'SharePlacement($x, $y, ×$scale)';
}

/// The inset every edge of the frame keeps from the canvas edge.
const double sharePlacementMargin = 20;

/// The bottom eighth a story viewer's reply bar covers, kept clear on a story.
const double storyReplyBarFraction = 0.13;

/// The bottom inset on a 4:5 post, which has no reply bar.
const double postBottomMargin = 22;

/// The part of a [canvas] the block must stay inside: the margin on every
/// side, and on a story the reply-bar strip as well.
Rect sharePlacementFrame(Size canvas, {required bool story}) {
  final bottom =
      story ? canvas.height * storyReplyBarFraction : postBottomMargin;
  return Rect.fromLTWH(
    sharePlacementMargin,
    sharePlacementMargin,
    canvas.width - sharePlacementMargin * 2,
    canvas.height - sharePlacementMargin - bottom,
  );
}

/// The smallest scale that keeps text drawn at [smallestTextPx] (at scale 1)
/// no smaller than [SharePlacement.minTextPx]. A block whose smallest text is
/// already at the floor cannot shrink at all.
double minSharePlacementScale(double smallestTextPx) {
  if (!(smallestTextPx > 0)) return SharePlacement.maxScale;
  return math.min(
    SharePlacement.maxScale,
    math.max(
        SharePlacement.minScale, SharePlacement.minTextPx / smallestTextPx),
  );
}

/// Where a block landed: its rectangle, the [scale] it is drawn at, and the
/// clamped [placement] it actually took — what a drag starts from and what is
/// stored.
@immutable
class PlacedShareBlock {
  final Rect rect;
  final double scale;
  final SharePlacement placement;
  const PlacedShareBlock(this.rect, this.scale, this.placement);
}

double _clamp(double v, double lo, double hi) => math.min(hi, math.max(lo, v));

/// Where a block [block] (at scale 1) lands on a [canvas]: scaled within
/// [minScale, maxScale], never larger than the [frame], and moved the least
/// distance that keeps it wholly inside the frame.
PlacedShareBlock placeShareBlock(
  SharePlacement placement,
  Size block,
  Size canvas,
  Rect frame,
  double minScale,
) {
  final fit = block.width > 0 && block.height > 0
      ? math.min(frame.width / block.width, frame.height / block.height)
      : 1.0;
  final hi = math.min(SharePlacement.maxScale, fit);
  final lo = math.min(minScale, hi);
  final scale = _clamp(
      placement.scale.isFinite ? placement.scale : SharePlacement.initial.scale,
      lo,
      hi);
  final width = block.width * scale;
  final height = block.height * scale;
  final x = placement.x.isFinite ? placement.x : SharePlacement.initial.x;
  final y = placement.y.isFinite ? placement.y : SharePlacement.initial.y;
  final cx = _clamp(x * canvas.width, frame.left + width / 2,
      frame.left + frame.width - width / 2);
  final cy = _clamp(y * canvas.height, frame.top + height / 2,
      frame.top + frame.height - height / 2);
  return PlacedShareBlock(
    Rect.fromLTWH(cx - width / 2, cy - height / 2, width, height),
    scale,
    SharePlacement(x: cx / canvas.width, y: cy / canvas.height, scale: scale),
  );
}

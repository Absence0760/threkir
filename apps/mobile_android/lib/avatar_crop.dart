import 'dart:math' as math;

/// Pure geometry for the avatar crop step: a square viewport over an image
/// that can be rotated in quarter turns, zoomed, and panned.
///
/// Every quantity is in one of two spaces. VIEWPORT space is the on-screen
/// square, `viewport` px on a side, with the pan measured as the offset of the
/// image centre from the viewport centre. ROTATED space is the source image's
/// pixels after the quarter turns are applied, origin at the rotated image's
/// top-left. The crop rect is returned in rotated space, so the renderer
/// rotates the source first and crops second on both platforms.
///
/// The image always covers the viewport: zoom 1 fits the short side exactly,
/// and the pan is clamped so no edge of the viewport ever shows past the image.
///
/// TS↔Dart parity pair with `apps/web/src/lib/util/avatar_crop.ts`.

const int avatarOutputMaxPx = 512;
const double avatarMinZoom = 1;
const double avatarMaxZoom = 4;

class CropSize {
  const CropSize(this.width, this.height);
  final double width;
  final double height;

  @override
  bool operator ==(Object other) =>
      other is CropSize && other.width == width && other.height == height;
  @override
  int get hashCode => Object.hash(width, height);
  @override
  String toString() => 'CropSize($width, $height)';
}

class CropPan {
  const CropPan(this.x, this.y);
  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is CropPan && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
  @override
  String toString() => 'CropPan($x, $y)';
}

class CropRect {
  const CropRect(this.x, this.y, this.size);
  final int x;
  final int y;
  final int size;

  @override
  bool operator ==(Object other) =>
      other is CropRect && other.x == x && other.y == y && other.size == size;
  @override
  int get hashCode => Object.hash(x, y, size);
  @override
  String toString() => 'CropRect($x, $y, $size)';
}

class CropState {
  const CropState({
    required this.sourceWidth,
    required this.sourceHeight,
    required this.quarterTurns,
    required this.viewport,
    required this.zoom,
    required this.pan,
  });

  /// Source dimensions with EXIF orientation already applied.
  final int sourceWidth;
  final int sourceHeight;
  final int quarterTurns;
  final double viewport;
  final double zoom;
  final CropPan pan;

  CropState copyWith({int? quarterTurns, double? zoom, CropPan? pan}) =>
      CropState(
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        quarterTurns: quarterTurns ?? this.quarterTurns,
        viewport: viewport,
        zoom: zoom ?? this.zoom,
        pan: pan ?? this.pan,
      );

  @override
  bool operator ==(Object other) =>
      other is CropState &&
      other.sourceWidth == sourceWidth &&
      other.sourceHeight == sourceHeight &&
      other.quarterTurns == quarterTurns &&
      other.viewport == viewport &&
      other.zoom == zoom &&
      other.pan == pan;
  @override
  int get hashCode =>
      Object.hash(sourceWidth, sourceHeight, quarterTurns, viewport, zoom, pan);
}

int normalizeQuarterTurns(int quarterTurns) => ((quarterTurns % 4) + 4) % 4;

CropSize rotatedSize(num width, num height, int quarterTurns) =>
    normalizeQuarterTurns(quarterTurns).isEven
    ? CropSize(width.toDouble(), height.toDouble())
    : CropSize(height.toDouble(), width.toDouble());

double clampZoom(double zoom) {
  if (!zoom.isFinite) return avatarMinZoom;
  return math.min(avatarMaxZoom, math.max(avatarMinZoom, zoom));
}

/// Viewport px per rotated-image px at the given zoom.
double displayScale(CropSize rotated, double viewport, double zoom) =>
    viewport / math.min(rotated.width, rotated.height) * clampZoom(zoom);

CropPan clampPan(CropPan pan, CropSize rotated, double viewport, double zoom) {
  final s = displayScale(rotated, viewport, zoom);
  final maxX = math.max(0.0, (rotated.width * s - viewport) / 2);
  final maxY = math.max(0.0, (rotated.height * s - viewport) / 2);
  // `+ 0.0` folds a -0.0 (from negating a zero pan on rotate) into 0.0.
  return CropPan(
    math.min(maxX, math.max(-maxX, pan.x)) + 0.0,
    math.min(maxY, math.max(-maxY, pan.y)) + 0.0,
  );
}

/// Change the zoom about the viewport centre: the point under the centre stays
/// under the centre, so the pan scales with the zoom ratio before clamping.
CropState rezoom(CropState state, double nextZoom) {
  final zoom = clampZoom(nextZoom);
  final ratio = zoom / clampZoom(state.zoom);
  final rotated = rotatedSize(
    state.sourceWidth,
    state.sourceHeight,
    state.quarterTurns,
  );
  return state.copyWith(
    zoom: zoom,
    pan: clampPan(
      CropPan(state.pan.x * ratio, state.pan.y * ratio),
      rotated,
      state.viewport,
      zoom,
    ),
  );
}

/// Turn the image a quarter about the viewport centre. [direction] is +1 for
/// clockwise and -1 for counter-clockwise, in screen coordinates (y down). The
/// pan rotates with the image so the same region stays in view.
CropState rotate(CropState state, int direction) {
  assert(direction == 1 || direction == -1);
  final quarterTurns = normalizeQuarterTurns(state.quarterTurns + direction);
  final pan = direction == 1
      ? CropPan(-state.pan.y, state.pan.x)
      : CropPan(state.pan.y, -state.pan.x);
  final rotated = rotatedSize(
    state.sourceWidth,
    state.sourceHeight,
    quarterTurns,
  );
  return state.copyWith(
    quarterTurns: quarterTurns,
    pan: clampPan(pan, rotated, state.viewport, state.zoom),
  );
}

CropState panBy(CropState state, double dx, double dy) {
  final rotated = rotatedSize(
    state.sourceWidth,
    state.sourceHeight,
    state.quarterTurns,
  );
  return state.copyWith(
    pan: clampPan(
      CropPan(state.pan.x + dx, state.pan.y + dy),
      rotated,
      state.viewport,
      state.zoom,
    ),
  );
}

/// JS `Math.round`: halves round towards +infinity, so both platforms snap a
/// crop edge that lands exactly on .5 to the same pixel.
int _jsRound(double v) => (v + 0.5).floor();

/// The square of rotated-space pixels the viewport shows, snapped to whole
/// pixels and kept inside the image.
CropRect cropRect(CropState state) {
  final rotated = rotatedSize(
    state.sourceWidth,
    state.sourceHeight,
    state.quarterTurns,
  );
  final pan = clampPan(state.pan, rotated, state.viewport, state.zoom);
  final s = displayScale(rotated, state.viewport, state.zoom);
  final shortSide = math.min(rotated.width, rotated.height).toInt();
  final size = math.max(1, math.min(shortSide, _jsRound(state.viewport / s)));
  final left = rotated.width / 2 - (state.viewport / 2 + pan.x) / s;
  final top = rotated.height / 2 - (state.viewport / 2 + pan.y) / s;
  return CropRect(
    math.min(rotated.width.toInt() - size, math.max(0, _jsRound(left))),
    math.min(rotated.height.toInt() - size, math.max(0, _jsRound(top))),
    size,
  );
}

/// Edge length of the encoded avatar: never upscaled, never above the cap.
int outputSize(num cropSize, [int max = avatarOutputMaxPx]) =>
    math.max(1, math.min(max, _jsRound(cropSize.toDouble())));

CropState initialCropState(
  int sourceWidth,
  int sourceHeight,
  double viewport,
) => CropState(
  sourceWidth: sourceWidth,
  sourceHeight: sourceHeight,
  quarterTurns: 0,
  viewport: viewport,
  zoom: 1,
  pan: const CropPan(0, 0),
);

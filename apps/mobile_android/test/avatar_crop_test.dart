import 'package:flutter_test/flutter_test.dart';

import '../lib/avatar_crop.dart';

void main() {
  test('normalizeQuarterTurns wraps into 0..3 in both directions', () {
    expect([-5, -1, 0, 1, 4, 7].map(normalizeQuarterTurns).toList(), [
      3,
      3,
      0,
      1,
      0,
      3,
    ]);
  });

  test('rotatedSize swaps the sides on an odd quarter turn only', () {
    expect(rotatedSize(400, 200, 0), const CropSize(400, 200));
    expect(rotatedSize(400, 200, 1), const CropSize(200, 400));
    expect(rotatedSize(400, 200, 2), const CropSize(400, 200));
    expect(rotatedSize(400, 200, -1), const CropSize(200, 400));
  });

  test('clampZoom bounds the zoom and treats a non-number as 1', () {
    expect(clampZoom(0.2), 1);
    expect(clampZoom(2.5), 2.5);
    expect(clampZoom(99), avatarMaxZoom);
    expect(clampZoom(double.nan), 1);
  });

  test('displayScale fits the short side to the viewport at zoom 1', () {
    expect(displayScale(const CropSize(400, 200), 100, 1), 0.5);
    expect(displayScale(const CropSize(400, 200), 100, 2), 1);
  });

  test('clampPan keeps the viewport covered', () {
    // 400x200 shown at 0.5 is 200x100 in a 100 viewport: 50 px of slack each
    // side horizontally, none vertically.
    const r = CropSize(400, 200);
    expect(clampPan(const CropPan(80, 30), r, 100, 1), const CropPan(50, 0));
    expect(clampPan(const CropPan(-80, -30), r, 100, 1), const CropPan(-50, 0));
    expect(clampPan(const CropPan(10, 0), r, 100, 1), const CropPan(10, 0));
  });

  test('the initial crop is the centred square of the short side', () {
    expect(
      cropRect(initialCropState(400, 200, 100)),
      const CropRect(100, 0, 200),
    );
    expect(
      cropRect(initialCropState(200, 400, 100)),
      const CropRect(0, 100, 200),
    );
  });

  test('panning right reveals the left of the image', () {
    final s = panBy(initialCropState(400, 200, 100), 50, 0);
    expect(cropRect(s), const CropRect(0, 0, 200));
    final t = panBy(initialCropState(400, 200, 100), -999, 0);
    expect(cropRect(t), const CropRect(200, 0, 200));
  });

  test('zoom shrinks the crop about the centre', () {
    final s = rezoom(initialCropState(400, 200, 100), 2);
    expect(cropRect(s), const CropRect(150, 50, 100));
  });

  test('rezoom scales the pan so the centred point stays put, then clamps', () {
    final panned = panBy(initialCropState(400, 200, 100), 20, 0);
    final z = rezoom(panned, 2);
    expect(z.pan, const CropPan(40, 0));
    final back = rezoom(
      rezoom(panBy(rezoom(initialCropState(400, 200, 100), 4), 0, 150), 4),
      1,
    );
    expect(back.pan, const CropPan(0, 0));
  });

  test(
    'a quarter turn swaps the crop space and keeps the pan with the image',
    () {
      final s = rotate(initialCropState(400, 200, 100), 1);
      expect(s.quarterTurns, 1);
      expect(cropRect(s), const CropRect(0, 100, 200));

      // Panned to show the left end, then turned clockwise: the left end is now
      // the top, so the crop sits at the top of the rotated image.
      final left = rotate(panBy(initialCropState(400, 200, 100), 50, 0), 1);
      expect(left.pan, const CropPan(0, 50));
      expect(cropRect(left), const CropRect(0, 0, 200));

      final ccw = rotate(panBy(initialCropState(400, 200, 100), 50, 0), -1);
      expect(ccw.quarterTurns, 3);
      expect(ccw.pan, const CropPan(0, -50));
      expect(cropRect(ccw), const CropRect(0, 200, 200));
    },
  );

  test('four turns in either direction return to the start', () {
    var s = panBy(rezoom(initialCropState(300, 500, 120), 2), 30, -40);
    final start = s;
    for (var i = 0; i < 4; i++) {
      s = rotate(s, 1);
    }
    expect(s, start);
    for (var i = 0; i < 4; i++) {
      s = rotate(s, -1);
    }
    expect(s, start);
  });

  test('cropRect stays inside the image for an off-range pan or zoom', () {
    final s = initialCropState(
      333,
      777,
      97,
    ).copyWith(zoom: 9, pan: const CropPan(1e6, -1e6), quarterTurns: 3);
    final r = cropRect(s);
    final rot = rotatedSize(333, 777, 3);
    expect(r.x >= 0 && r.y >= 0, isTrue);
    expect(r.x + r.size <= rot.width && r.y + r.size <= rot.height, isTrue);
    expect(r.size, (333 / avatarMaxZoom).round());
  });

  test('a tiny image never produces a zero-sized crop', () {
    expect(
      cropRect(initialCropState(1, 1, 300).copyWith(zoom: 4)),
      const CropRect(0, 0, 1),
    );
  });

  test('outputSize caps at the avatar size and never upscales', () {
    expect(outputSize(3024), avatarOutputMaxPx);
    expect(outputSize(200), 200);
    expect(outputSize(199.6), 200);
    expect(outputSize(0), 1);
  });
}

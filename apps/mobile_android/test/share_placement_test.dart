// Mirrors apps/web/src/lib/share/share_placement.test.ts case for case.

import 'dart:convert';
import 'dart:ui' show Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import '../lib/share_placement.dart';

const _storyCanvas = Size(360, 640);
const _postCanvas = Size(360, 450);
final _story = sharePlacementFrame(_storyCanvas, story: true);
final _post = sharePlacementFrame(_postCanvas, story: false);

void _near(double a, double b) =>
    expect((a - b).abs(), lessThan(1e-9), reason: '$a != $b');

void main() {
  group('sharePlacementFrame', () {
    test('keeps a story clear of the bottom 13% the reply bar covers', () {
      expect(_story.left, 20);
      expect(_story.top, 20);
      expect(_story.width, 320);
      _near(_story.bottom, 640 * 0.87);
    });

    test('keeps a post 22 px off its bottom edge', () {
      expect(_post.width, 320);
      expect(_post.bottom, 450 - 22);
    });
  });

  group('minSharePlacementScale', () {
    test('lets 12 px labels shrink to the 6 px floor, and no further than half',
        () {
      expect(minSharePlacementScale(12), 0.5);
      expect(minSharePlacementScale(48), SharePlacement.minScale);
    });

    test('a strip already near the floor barely shrinks; one at it cannot', () {
      _near(minSharePlacementScale(12 * (320 / 560)), 6 / (12 * (320 / 560)));
      expect(minSharePlacementScale(5), SharePlacement.maxScale);
      expect(minSharePlacementScale(0), SharePlacement.maxScale);
    });
  });

  group('placeShareBlock', () {
    test('the default sits centred on the bottom edge of the frame', () {
      final placed = placeShareBlock(SharePlacement.initial,
          const Size(320, 200), _storyCanvas, _story, 0.5);
      expect(placed.rect.left, 20);
      _near(placed.rect.bottom, 640 * 0.87);
      expect(placed.scale, 1);
      _near(placed.placement.y, (640 * 0.87 - 100) / 640);
    });

    test('a centre inside the frame is kept as it is', () {
      final placed = placeShareBlock(
          const SharePlacement(x: 0.5, y: 0.4, scale: 0.5),
          const Size(320, 200),
          _storyCanvas,
          _story,
          0.5);
      expect(placed.rect.left, 180 - 80);
      expect(placed.rect.top, 256 - 50);
      expect(placed.placement, const SharePlacement(x: 0.5, y: 0.4, scale: 0.5));
    });

    test('a block dragged off any edge is moved back wholly inside the frame',
        () {
      for (final (x, y) in [(-1.0, 0.5), (2.0, 0.5), (0.5, -1.0), (0.5, 2.0)]) {
        final r = placeShareBlock(SharePlacement(x: x, y: y, scale: 0.5),
                const Size(320, 200), _storyCanvas, _story, 0.5)
            .rect;
        expect(r.left, greaterThanOrEqualTo(_story.left - 1e-9));
        expect(r.top, greaterThanOrEqualTo(_story.top - 1e-9));
        expect(r.right, lessThanOrEqualTo(_story.right + 1e-9));
        expect(r.bottom, lessThanOrEqualTo(_story.bottom + 1e-9),
            reason: 'bottom at ${r.bottom}');
      }
    });

    test('clamps the scale to the minimum and to what fits', () {
      expect(
          placeShareBlock(const SharePlacement(x: 0.5, y: 0.5, scale: 0.1),
                  const Size(320, 200), _storyCanvas, _story, 0.7)
              .scale,
          0.7);
      expect(
          placeShareBlock(const SharePlacement(x: 0.5, y: 0.5, scale: 3),
                  const Size(320, 200), _storyCanvas, _story, 0.5)
              .scale,
          1);
      // A block taller than the frame is shrunk to fit it, under the minimum.
      _near(
          placeShareBlock(const SharePlacement(x: 0.5, y: 0.5, scale: 1),
                  const Size(320, 816), _storyCanvas, _story, 0.7)
              .scale,
          _story.height / 816);
    });

    test('a non-finite value takes its default', () {
      final placed = placeShareBlock(
          const SharePlacement(
              x: double.nan, y: double.infinity, scale: double.nan),
          const Size(160, 100),
          _storyCanvas,
          _story,
          0.5);
      expect(placed.scale, 1);
      _near(placed.rect.center.dx, 180);
      _near(placed.rect.bottom, 640 * 0.87);
    });

    test(
        'move and resize are fractions of the canvas, so they survive '
        'rasterising', () {
      final moved = const SharePlacement(x: 0.5, y: 0.5, scale: 1)
          .moved(36, -64, _storyCanvas);
      _near(moved.x, 0.6);
      _near(moved.y, 0.4);
      expect(moved.resized(0.5).scale, 0.5);
      // The same fractions on the 1080 px export land three times as far.
      final logical = placeShareBlock(
          moved, const Size(160, 100), _storyCanvas, _story, 0.5);
      final exported = placeShareBlock(
        moved,
        const Size(480, 300),
        const Size(1080, 1920),
        Rect.fromLTWH(_story.left * 3, _story.top * 3, _story.width * 3,
            _story.height * 3),
        0.5,
      );
      _near(exported.rect.left, logical.rect.left * 3);
      _near(exported.rect.top, logical.rect.top * 3);
    });
  });

  group('SharePlacement.fromJson', () {
    test('round-trips a stored placement', () {
      const p = SharePlacement(x: 0.25, y: 0.75, scale: 0.6);
      expect(SharePlacement.fromJson(jsonDecode(jsonEncode(p.toJson()))), p);
    });

    test('an unknown or out-of-range value fails closed to the default', () {
      for (final bad in <Object?>[
        null,
        'centre',
        [0.5, 0.5, 1],
        {'x': 0.5, 'y': 0.5},
        {'x': '0.5', 'y': 0.5, 'scale': 1},
        {'x': 1.5, 'y': 0.5, 'scale': 1},
        {'x': 0.5, 'y': -0.1, 'scale': 1},
        {'x': 0.5, 'y': 0.5, 'scale': 0.4},
        {'x': 0.5, 'y': 0.5, 'scale': 1.2},
      ]) {
        expect(SharePlacement.fromJson(bad), SharePlacement.initial,
            reason: '$bad');
      }
    });
  });
}

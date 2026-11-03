import 'package:flutter_test/flutter_test.dart';

import '../lib/route_art.dart';

/// Twin of web's `routes/route_art.test.ts` — same cases, same expected
/// values.
void main() {
  /// A hand-drawn square of ~1 km sides at London's latitude, stopped one
  /// step short of its start so the loop-closing rule has work to do.
  List<List<double>> square() {
    final out = <List<double>>[];
    const lng0 = -0.1;
    const lat0 = 51.5;
    const dLng = 0.0144;
    const dLat = 0.009;
    for (var i = 0; i <= 40; i++) {
      out.add([lng0 + (dLng * i) / 40, lat0]);
    }
    for (var i = 1; i <= 40; i++) {
      out.add([lng0 + dLng, lat0 + (dLat * i) / 40]);
    }
    for (var i = 1; i <= 40; i++) {
      out.add([lng0 + dLng * (1 - i / 40), lat0 + dLat]);
    }
    for (var i = 1; i <= 39; i++) {
      out.add([lng0, lat0 + dLat * (1 - i / 40)]);
    }
    return out;
  }

  List<List<double>> prepared() {
    final p = prepareStroke(square());
    expect(p.ok, isTrue);
    return p.points;
  }

  test('prepareStroke closes a nearly-closed square and keeps its corners',
      () {
    final p = prepareStroke(square());
    expect(p.ok, isTrue);
    expect(p.closed, isTrue);
    expect(p.points.length, 69);
    expect(p.spacingM, 60);
    expect(p.lengthM.round(), 3970);
    expect(p.points.first, [-0.1, 51.5]);
    expect(p.points.last, [-0.1, 51.5]);
    for (final corner in const [
      [-0.0856, 51.5],
      [-0.0856, 51.509],
      [-0.1, 51.509],
    ]) {
      expect(
        p.points.any((q) =>
            (q[0] - corner[0]).abs() < 1e-9 && (q[1] - corner[1]).abs() < 1e-9),
        isTrue,
        reason: 'corner $corner',
      );
    }
  });

  test('prepareStroke leaves an open stroke open', () {
    final line = [
      for (var i = 0; i <= 20; i++) [(0.01 * i) / 20, 0.0],
    ];
    final p = prepareStroke(line);
    expect(p.ok, isTrue);
    expect(p.closed, isFalse);
    expect(p.points.last, [0.01, 0.0]);
    expect(p.points.length, 20);
  });

  test('prepareStroke drops non-finite, out-of-range and jitter points', () {
    final line = <List<double>>[
      [0, 0],
      [double.nan, 0],
      [0.000001, 0],
      [200, 0],
      [0, 95],
      [0.005, 0],
    ];
    final p = prepareStroke(line);
    expect(p.ok, isTrue);
    expect(p.points.first, [0.0, 0.0]);
    expect(p.points.last, [0.005, 0.0]);
    expect(p.points.every((q) => q[0].isFinite && q[1].abs() <= 90), isTrue);
  });

  test('prepareStroke rejects a stroke too short or too long to route', () {
    expect(prepareStroke(const []).rejection, StrokeRejection.tooShort);
    expect(
      prepareStroke(const [
        [0, 0],
        [0.001, 0],
      ]).rejection,
      StrokeRejection.tooShort,
    );
    expect(
      prepareStroke(const [
        [0, 0],
        [1, 0],
      ]).rejection,
      StrokeRejection.tooLong,
    );
  });

  test('prepareStroke widens the spacing to stay within the point budget', () {
    final line = [
      for (var i = 0; i <= 500; i++) [i * 0.0009, 10 + (i % 2) * 0.00001],
    ];
    final p = prepareStroke(line);
    expect(p.ok, isTrue);
    expect(p.points.length <= kRouteArtMaxPoints, isTrue);
    expect(p.points.length, 271);
    expect(p.spacingM, 183.10546875);
  });

  test('densifyLine splits a segment evenly and keeps both ends', () {
    final out = densifyLine(const [
      [0, 0],
      [0.001, 0],
    ], 50);
    expect(out.length, 4);
    expect(out[0], [0.0, 0.0]);
    expect(out[3], [0.001, 0.0]);
    expect((out[1][0] - 0.001 / 3).abs() < 1e-15, isTrue);
  });

  test('densifyLine interpolates across the antimeridian the short way', () {
    final out = densifyLine(const [
      [179.999, 0],
      [-179.999, 0],
    ], 100);
    expect(out.length, 4);
    for (final p in out) {
      expect(p[0].abs() > 179.99, isTrue, reason: 'lng ${p[0]}');
    }
  });

  test('planRouteBatches shares each seam point and caps every call', () {
    expect(planRouteBatches(296), const [
      RouteBatch(0, 59),
      RouteBatch(59, 118),
      RouteBatch(118, 177),
      RouteBatch(177, 236),
      RouteBatch(236, 295),
    ]);
    expect(planRouteBatches(60), const [RouteBatch(0, 59)]);
    expect(planRouteBatches(61), const [RouteBatch(0, 59), RouteBatch(59, 60)]);
    expect(planRouteBatches(1), isEmpty);
    expect(planRouteBatches(5, 1), isEmpty);
  });

  test('routeArtBatchPath names every point and gives each a radius', () {
    expect(
      routeArtBatchPath(const [
        [-0.1, 51.5],
        [-0.0991, 51.5007],
      ], 'foot', 150),
      '/route/v1/foot/-0.1,51.5;-0.0991,51.5007'
      '?overview=full&geometries=geojson&radiuses=150;150',
    );
  });

  test('stitchPolylines drops a duplicated seam point only', () {
    final out = stitchPolylines(const [
      [
        [0, 0],
        [0.001, 0],
      ],
      [
        [0.001, 0],
        [0.002, 0],
      ],
      [
        [0.003, 0],
        [0.004, 0],
      ],
    ]);
    expect(out, const [
      [0, 0],
      [0.001, 0],
      [0.002, 0],
      [0.003, 0],
      [0.004, 0],
    ]);
  });

  test('sampleAlong spaces samples by distance and includes both ends', () {
    final out = sampleAlong(const [
      [0, 0],
      [0.001, 0],
      [0.001, 0.001],
    ], 5);
    expect(out.length, 5);
    expect(out[0], [0.0, 0.0]);
    expect(out[2], [0.001, 0.0]);
    expect((out[4][1] - 0.001).abs() < 1e-15, isTrue);
    expect(sampleAlong(const [], 5), isEmpty);
    expect(sampleAlong(const [
      [1, 2],
    ], 2), const [
      [1, 2],
      [1, 2],
    ]);
  });

  test('fidelityToleranceM scales with the drawing and clamps', () {
    expect((fidelityToleranceM(prepared()) * 1000).round() / 1000, 70.62);
    expect(
      fidelityToleranceM(const [
        [0, 0],
        [0.0001, 0],
      ]),
      25,
    );
    expect(
      fidelityToleranceM(const [
        [0, 0],
        [0.5, 0.5],
      ]),
      120,
    );
  });

  test('drawingFidelity scores a route on the drawing as a perfect match', () {
    final pts = prepared();
    final f = drawingFidelity(pts, pts)!;
    expect(f.score, 100);
    expect(f.verdict, FidelityVerdict.close);
    expect(f.meanOffsetM, 0);
    expect(f.lengthRatio, 1);
  });

  test('drawingFidelity tolerates a route one street over', () {
    final pts = prepared();
    final shifted = [
      for (final p in pts) [p[0], p[1] + 0.0003],
    ];
    final f = drawingFidelity(pts, shifted)!;
    expect(f.score, 100);
    expect(f.maxOffsetM.round(), 33);
    expect(f.meanOffsetM.round(), 17);
  });

  test('drawingFidelity refuses a route that skips half the drawing', () {
    final pts = prepared();
    final f = drawingFidelity(pts, pts.sublist(0, pts.length ~/ 2))!;
    expect(f.coverage, 53 / 101);
    expect(f.precision, 1);
    expect(f.score, 52);
    expect(f.verdict, FidelityVerdict.poor);
  });

  test('drawingFidelity refuses a route that detours far off the drawing', () {
    final pts = prepared();
    final detour = [
      ...pts,
      [-0.1, 51.48],
      [-0.1, 51.5],
    ];
    final f = drawingFidelity(pts, detour)!;
    expect(f.coverage, 1);
    expect(f.precision < 0.6, isTrue, reason: 'precision ${f.precision}');
    expect(f.verdict, FidelityVerdict.poor);
  });

  test('drawingFidelity returns null when either line is degenerate', () {
    expect(
      drawingFidelity(const [
        [0, 0],
      ], prepared()),
      isNull,
    );
    expect(drawingFidelity(prepared(), const []), isNull);
    expect(
      drawingFidelity(prepared(), const [
        [0, 0],
        [0, 0],
      ]),
      isNull,
    );
  });

  test('fidelityVerdict bands the score', () {
    expect(fidelityVerdict(100), FidelityVerdict.close);
    expect(fidelityVerdict(85), FidelityVerdict.close);
    expect(fidelityVerdict(84), FidelityVerdict.rough);
    expect(fidelityVerdict(60), FidelityVerdict.rough);
    expect(fidelityVerdict(59), FidelityVerdict.poor);
  });

  test('artAnchorIndices keeps both ends and caps the count', () {
    final pts = prepared();
    expect(artAnchorIndices(pts), const [0, 9, 18, 26, 35, 43, 52, 60, 68]);
    expect(artAnchorIndices(pts, 50, 4), const [0, 23, 46, 68]);
    expect(artAnchorIndices(const []), isEmpty);
    expect(artAnchorIndices(const [
      [0, 0],
    ]), const [0]);
    expect(
      artAnchorIndices(const [
        [0, 0],
        [0.001, 0],
      ]),
      const [0, 1],
    );
  });

  test('sliceAtAnchors cuts the line into pieces that share their ends', () {
    final pts = prepared();
    final anchors = artAnchorIndices(pts);
    final slices = sliceAtAnchors(pts, anchors);
    expect(slices.length, anchors.length - 1);
    expect(
      slices.fold<double>(0, (s, part) => s + polylineLengthM(part)).round(),
      polylineLengthM(pts).round(),
    );
    for (var j = 1; j < slices.length; j++) {
      expect(slices[j].first, slices[j - 1].last);
    }
  });
}

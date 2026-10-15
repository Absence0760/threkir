import 'package:flutter_test/flutter_test.dart';

import '../lib/elevation_profile.dart';
import '../lib/screens/run_detail_screen.dart';

/// The run-detail elevation chart's gutter labels, swept over the data
/// ranges a real track can produce: none at all, sub-metre GPS jitter, a
/// few metres of flat road, and mountain days.
void main() {
  const plotHeight = 140.0;
  const minGapPx = 16.0;

  List<double> labelsFor(double min, double max) => elevationGutterLabels(
        dataMin: min,
        dataMax: max,
        domain: elevationDomain(min, max),
        plotHeight: plotHeight,
        minGapPx: minGapPx,
      );

  test('a 100-102 m run gets one label, not two painted over each other', () {
    expect(labelsFor(100, 102), [101]);
  });

  test('a 100.4-100.6 m run, whose rounded ends differ, gets one label', () {
    expect(labelsFor(100.4, 100.6), [101]);
  });

  test('a hilly run labels its low and high', () {
    expect(labelsFor(200, 700), [200, 700]);
  });

  test('labels never collide, repeat or go non-finite at any span', () {
    const bases = [-430.0, -0.4, 0.0, 100.4, 1609.0, 8848.0];
    const spans = [
      0.0, 1e-6, 0.4, 0.6, 1.0, 2.0, 3.0, 4.0, 4.5, 5.0, 6.0, 10.0, 30.0,
      100.0, 1000.0, 1e5,
    ];
    for (final base in bases) {
      for (final span in spans) {
        final min = base, max = base + span;
        final domain = elevationDomain(min, max);
        final labels = labelsFor(min, max);
        final reason = 'min=$min max=$max labels=$labels';
        expect(labels, isNotEmpty, reason: reason);
        expect(labels.length, lessThanOrEqualTo(2), reason: reason);
        expect(labels.every((v) => v.isFinite), isTrue, reason: reason);
        expect(labels.map((v) => v.round()).toSet().length, labels.length,
            reason: reason);
        final range = domain.hi - domain.lo;
        for (final v in labels) {
          expect(v, inInclusiveRange(domain.lo, domain.hi), reason: reason);
        }
        if (labels.length == 2) {
          final gapPx = (labels[1] - labels[0]).abs() / range * plotHeight;
          expect(gapPx, greaterThanOrEqualTo(minGapPx), reason: reason);
        }
      }
    }
  });
}

import 'package:flutter_test/flutter_test.dart';

import '../lib/recap_card_layout.dart';

void main() {
  test('the square card keeps the coordinates it has always had', () {
    final l = recapCardLayout(RecapCardAspect.square);
    expect(
      [
        l.width,
        l.height,
        l.pad,
        l.brandY,
        l.kickerY,
        l.heroY,
        l.subheadY,
        l.gridTop,
        l.colW,
        l.rowH,
        l.footerY,
      ],
      [1080, 1080, 72, 100, 182, 352, 422, 512, 468, 150, null],
    );
  });

  test('the story is 1080x1920 with its content below the top UI band', () {
    final l = recapCardLayout(RecapCardAspect.story);
    expect(
      [
        l.width,
        l.height,
        l.brandY,
        l.kickerY,
        l.heroY,
        l.subheadY,
        l.gridTop,
        l.rowH,
        l.footerY,
      ],
      [1080, 1920, 388, 470, 640, 710, 960, 200, 1620],
    );
  });

  test(
    'every aspect fits its last stat value above its footer and inside the canvas',
    () {
      for (final aspect in RecapCardAspect.values) {
        final l = recapCardLayout(aspect);
        final last = recapCellOrigin(l, 5);
        expect(
          last.valueY < (l.footerY ?? l.height) - 40,
          isTrue,
          reason: '$aspect',
        );
        expect(last.valueY <= l.height - l.pad, isTrue, reason: '$aspect');
      }
    },
  );

  test('cells fill two columns, then the next row', () {
    final l = recapCardLayout(RecapCardAspect.square);
    expect(recapCellOrigin(l, 0), (x: 72.0, labelY: 512.0, valueY: 570.0));
    expect(recapCellOrigin(l, 1), (x: 540.0, labelY: 512.0, valueY: 570.0));
    expect(recapCellOrigin(l, 2), (x: 72.0, labelY: 662.0, valueY: 720.0));
    expect(recapCellOrigin(l, 5), (x: 540.0, labelY: 812.0, valueY: 870.0));
  });
}

import 'package:flutter_test/flutter_test.dart';

import '../lib/entry_field_fit.dart';

/// The session screen's floor + gap. Held as literals so the derivation is
/// read at the numbers the screen actually passes.
const _floor = 72.0;
const _gap = 12.0;

int _at(int count, double width, double scale) => fieldsPerRow(
      count: count,
      maxWidth: width,
      minFieldWidth: _floor * scale,
      gap: _gap,
    );

void main() {
  group('fieldsPerRow', () {
    test('keeps the 1.0x geometry on every phone width', () {
      // 320 / 360 / 412 dp phones, minus the entry view's 16dp side padding.
      for (final width in [288.0, 328.0, 380.0]) {
        expect(_at(3, width, 1.0), 3,
            reason: 'the three common fields must not reflow at 1.0x on a '
                '${width + 32}dp phone');
      }
    });

    test('reflows as the OS text size grows', () {
      expect(_at(3, 328, 1.0), 3);
      expect(_at(3, 328, 2.0), 2);
      expect(_at(3, 328, 3.0), 1);
    });

    test('balances rows instead of stranding one field', () {
      // Five fields that fit four across split 3+2, never 4+1.
      expect(
        fieldsPerRow(count: 5, maxWidth: 400, minFieldWidth: _floor, gap: _gap),
        3,
      );
    });

    test('never answers less than one, however narrow the row', () {
      expect(_at(3, 10, 3.0), 1);
      expect(_at(1, 10, 3.0), 1);
    });
  });
}

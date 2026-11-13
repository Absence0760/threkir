import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Share-image guard (issue #1374 TO-3).
///
/// A share image captured at the preview's size and the OS text scale ships
/// a different picture on every phone and text setting: three did, and
/// exported truncated values and a cropped certificate. Every file that
/// captures one does it through `ShareCanvas` / `captureShareCanvas`, or
/// (the run and recap cards, the head-to-head card, whose canvases predate
/// it) lays its boundary out on a fixed canvas under
/// `MediaQuery.withNoTextScaling`.
void main() {
  test('every captured share image has a fixed canvas with text scaling off', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('capture_png.dart') || f.path.endsWith('share_canvas.dart')) {
        continue;
      }
      final src = f.readAsStringSync();
      if (!src.contains('capturePngBytes(') && !src.contains('captureShareCanvas(')) {
        continue;
      }
      final pinned = src.contains('ShareCanvas(') ||
          src.contains('MediaQuery.withNoTextScaling(');
      final direct = src.contains('capturePngBytes(');
      if (!pinned || (src.contains('ShareCanvas(') && direct)) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty,
        reason: 'capture a share image through ShareCanvas / captureShareCanvas:\n'
            '${offenders.join('\n')}');
  });
}

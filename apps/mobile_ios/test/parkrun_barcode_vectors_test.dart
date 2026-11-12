// ignore_for_file: avoid_relative_lib_imports
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/parkrun_barcode.dart';
import '../lib/widgets/parkrun_barcode_view.dart';

// The shared Code 128 vectors in fixtures/parkrun_barcode_vectors.json, also
// asserted by apps/web/src/lib/integrations/parkrun_barcode_scan.test.ts —
// which decodes every one of them with an independent ISO/IEC 15417 decoder.
// Matching them here means the Dart encoder draws the same bars as the web
// one, so the two cannot drift. The painter test then reads the barcode back
// out of the pixels the phone actually paints.

class _Case {
  _Case(Map<String, dynamic> json)
      : input = json['input'] as String,
        symbols = (json['symbols'] as List).cast<int>(),
        widths = json['widths'] as String,
        modules = json['modules'] as int;

  final String input;
  final List<int> symbols;
  final String widths;
  final int modules;
}

final Map<String, dynamic> _vectors = jsonDecode(
  File('../../fixtures/parkrun_barcode_vectors.json').readAsStringSync(),
) as Map<String, dynamic>;

final List<_Case> _cases = (_vectors['cases'] as List)
    .map((c) => _Case(c as Map<String, dynamic>))
    .toList();

String _rowFromWidths(String widths) {
  final out = StringBuffer();
  for (var i = 0; i < widths.length; i++) {
    out.write((i.isEven ? '1' : '0') * int.parse(widths[i]));
  }
  return out.toString();
}

/// The run lengths of one horizontal line of [image], in pixels, starting
/// with the white run before the first bar.
Future<List<int>> _scanLine(ui.Image image) async {
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final y = image.height ~/ 2;
  final runs = <int>[];
  bool? dark;
  for (var x = 0; x < image.width; x++) {
    final r = bytes.getUint8((y * image.width + x) * 4);
    final isDark = r < 128;
    if (isDark == dark) {
      runs[runs.length - 1]++;
    } else {
      runs.add(1);
      dark = isDark;
    }
  }
  return runs;
}

void main() {
  test('shared vectors: the fixture uses the same quiet zone', () {
    expect(_vectors['quiet_zone_modules'], kCode128QuietZoneModules);
    expect(_cases.length, greaterThanOrEqualTo(10));
  });

  test('shared vectors: the encoder matches every committed width sequence',
      () {
    for (final c in _cases) {
      expect(code128BSymbols(c.input), c.symbols, reason: c.input);
      expect(code128BModules(c.input), _rowFromWidths(c.widths),
          reason: c.input);
      expect(code128BModules(c.input).length, c.modules, reason: c.input);
    }
  });

  // A phone-width barcode (360 logical px) and a tablet-width one. The test
  // renders at 1 px per logical px, so 360 px is the tightest a real screen
  // gets: 13 digits need 198 modules with the quiet zones, one pixel each.
  for (final width in [360, 1080]) {
    testWidgets('the painted barcode scans at $width px', (tester) async {
      await tester.runAsync(() async {
        for (final c in _cases) {
          final recorder = ui.PictureRecorder();
          ParkrunBarcodePainter(code128BModules(c.input))
              .paint(Canvas(recorder), Size(width.toDouble(), 20));
          final image = await recorder.endRecording().toImage(width, 20);
          final runs = await _scanLine(image);
          image.dispose();

          // White, then bar/space elements, then white.
          expect(runs.length, c.widths.length + 2, reason: c.input);
          final elements = runs.sublist(1, runs.length - 1);
          // Every code has a 1-module element, so the narrowest run is the
          // module the scanner calibrates on; every element must be a whole
          // number of them and spell out the committed widths.
          final module = elements.reduce((a, b) => a < b ? a : b);
          expect(
            elements.map((e) {
              expect(e % module, 0, reason: '${c.input}: run $e of $module px');
              return e ~/ module;
            }).join(),
            c.widths,
            reason: c.input,
          );
          expect(runs.first, greaterThanOrEqualTo(kCode128QuietZoneModules * module),
              reason: '${c.input}: leading quiet zone');
          expect(runs.last, greaterThanOrEqualTo(kCode128QuietZoneModules * module),
              reason: '${c.input}: trailing quiet zone');
        }
      });
    });
  }
}

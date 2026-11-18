import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/store/store_capture_kit.dart';

// The store capture's bounds.json is only as good as the arithmetic that maps
// a widget's box to capture pixels, and the coach panel is only honest if a
// usage banner inside a crop fails the capture. Both run here, without a
// device, against a small screen laid out the way the capture lays out the
// run detail: 320 dp wide, drawn at 3x (assets/store/README.md).

const _fill = Color(0xFF36323F);

Widget _screen(GlobalKey boundary, {bool bannerInside = false}) =>
    MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: captureBoundary(
        boundary,
        Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  key: const Key('card'),
                  height: 100,
                  color: _fill,
                ),
              ),
              if (bannerInside)
                Container(key: const Key('banner'), height: 10, color: Colors.red),
              const SizedBox(key: Key('row'), height: 30),
              if (!bannerInside)
                Container(key: const Key('banner'), height: 10, color: Colors.red),
            ],
          ),
        ),
      ),
    );

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .implicitView!;
    view.devicePixelRatio = 3;
    view.physicalSize = const Size(kColumnDp * 3, 600 * 3);
  });
  tearDown(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.resetDevicePixelRatio();
    view.resetPhysicalSize();
  });

  testWidgets('sections land in capture pixels, with the dpr and the theme',
      (tester) async {
    final boundary = GlobalKey();
    await tester.pumpWidget(_screen(boundary));
    final shot = (await tester.runAsync(() => captureScreen(
          tester,
          name: 'run-splits',
          boundary: boundary,
          pixelRatio: 3,
          sections: {
            'pacing-card': [find.byKey(const Key('card'))],
            'card-and-row': [
              find.byKey(const Key('card')),
              find.byKey(const Key('row')),
            ],
          },
          colourAt: {'pacing-card': ('pacing-card', const Offset(40, 4))},
          forbidden: {'banner': find.byKey(const Key('banner'))},
        )))!;
    expect(shot.size, const Size(960, 1800));
    final bounds = shot.toBounds();
    expect(bounds['theme'], 'dark');
    expect(bounds['dpr'], 3.0);
    expect(bounds['size'], [960, 1800]);
    final sections = bounds['sections']! as Map<String, List<double>>;
    expect(sections['pacing-card'], [60.0, 120.0, 840.0, 300.0]);
    expect(sections['card-and-row'], [0.0, 120.0, 960.0, 390.0]);
    expect(bounds['colours'], {'pacing-card': '#36323F'});
    // The banner sits below every section, so it is recorded, not fatal.
    expect(bounds['forbidden'], {
      'banner': [0.0, 510.0, 960.0, 30.0],
    });
    final report = StoreCaptureSet()..captures.add(shot);
    final data = report.reportData({'schema': 1});
    final png = base64Decode(
        (data['store_files']! as Map<String, String>)['run-splits.png']!);
    expect(png.sublist(1, 4), utf8.encode('PNG'));
  });

  testWidgets('a forbidden widget inside a section fails the capture',
      (tester) async {
    final boundary = GlobalKey();
    await tester.pumpWidget(_screen(boundary, bannerInside: true));
    Object? error;
    await tester.runAsync(() async {
      try {
        await captureScreen(
          tester,
          name: 'coach',
          boundary: boundary,
          pixelRatio: 3,
          sections: {
            'coach-last-exchange': [
              find.byKey(const Key('card')),
              find.byKey(const Key('row')),
            ],
          },
          forbidden: {'coach-limit-banner': find.byKey(const Key('banner'))},
        );
      } on TestFailure catch (e) {
        error = e;
      }
    });
    expect(error.toString(), contains('coach-limit-banner is inside section'));
  });

  testWidgets('a section clipped by its viewport fails the capture',
      (tester) async {
    final boundary = GlobalKey();
    await tester.pumpWidget(_screen(boundary));
    await expectLater(
      captureScreen(
        tester,
        name: 'run-zones',
        boundary: boundary,
        pixelRatio: 3,
        sections: {
          'hr-zones': [find.byKey(const Key('card'))],
        },
        viewports: {'hr-zones': const Rect.fromLTWH(0, 60, 320, 500)},
      ),
      throwsA(isA<TestFailure>()),
    );
  });
}

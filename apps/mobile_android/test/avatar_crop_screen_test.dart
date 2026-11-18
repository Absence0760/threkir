import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/avatar_crop_screen.dart';
import 'editor_layout.dart';
import 'pump_until.dart';
import 'worst_case_layout.dart';

/// 40x20, red on the left half and blue on the right.
Uint8List _twoTonePng() {
  final image = img.Image(width: 40, height: 20);
  for (var y = 0; y < 20; y++) {
    for (var x = 0; x < 40; x++) {
      image.setPixelRgb(x, y, x < 20 ? 255 : 0, 0, x < 20 ? 0 : 255);
    }
  }
  return img.encodePng(image);
}

class _Outcome {
  bool done = false;
  Uint8List? bytes;
}

/// Hosts a button that pushes the crop step for [bytes] and records what it
/// resolves to.
Future<_Outcome> _open(WidgetTester tester, Uint8List bytes) async {
  final outcome = _Outcome();
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              outcome.bytes = await showAvatarCropScreen(context, bytes);
              outcome.done = true;
            },
            child: const Text('pick'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('pick'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return outcome;
}

FilledButton _confirmButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('avatar-crop-confirm')));

Future<void> _decoded(WidgetTester tester) => pumpUntil(
  tester,
  () => _confirmButton(tester).onPressed != null,
  describe: 'the picked photo to decode',
);

/// Whether the hue at ([x], [y]) is mostly red (true) or mostly blue (false).
bool _redAt(img.Image image, int x, int y) {
  final p = image.getPixel(x, y);
  return p.r > p.b;
}

void main() {
  testWidgets('rotate left then Use photo returns the turned square', (
    tester,
  ) async {
    final outcome = await _open(tester, _twoTonePng());
    expect(find.text('Adjust profile photo'), findsOneWidget);
    expect(
      _confirmButton(tester).onPressed,
      isNull,
      reason: 'confirm waits for the decode',
    );

    await pumpUntil(
      tester,
      () => _confirmButton(tester).onPressed != null,
      describe: 'the picked photo to decode',
    );
    expect(find.byKey(const Key('avatar-crop-stage')), findsOneWidget);

    await tester.tap(find.byTooltip('Rotate left'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('avatar-crop-confirm')));
    await pumpUntil(
      tester,
      () => outcome.done,
      describe: 'the crop step to return the encoded photo',
    );
    await tester.pumpAndSettle();

    final out = img.decodeJpg(outcome.bytes!)!;
    expect([out.width, out.height], [20, 20]);
    // A counter-clockwise turn puts the source's right (blue) half on top.
    final top = out.getPixel(10, 5);
    final bottom = out.getPixel(10, 15);
    expect(top.b > 180 && top.r < 80, isTrue, reason: 'top $top');
    expect(bottom.r > 180 && bottom.b < 80, isTrue, reason: 'bottom $bottom');
    expect(find.text('Adjust profile photo'), findsNothing);
  });

  testWidgets('the close button backs out with nothing', (tester) async {
    final outcome = await _open(tester, _twoTonePng());
    await pumpUntil(
      tester,
      () => _confirmButton(tester).onPressed != null,
      describe: 'the picked photo to decode',
    );

    await tester.tap(find.byType(CloseButtonIcon));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(outcome.done, isTrue);
    expect(outcome.bytes, isNull);
  });

  testWidgets('an undecodable photo says so and offers no confirm', (
    tester,
  ) async {
    await _open(tester, Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]));
    await pumpUntil(
      tester,
      () => find.byKey(const Key('avatar-crop-error')).evaluate().isNotEmpty,
      describe: 'the decode failure to surface',
    );
    expect(find.byKey(const Key('avatar-crop-confirm')), findsNothing);
  });

  testWidgets('close and system back cannot leave while the photo encodes', (
    tester,
  ) async {
    final outcome = await _open(tester, _twoTonePng());
    await _decoded(tester);

    await tester.tap(find.byKey(const Key('avatar-crop-confirm')));
    await tester.pump();
    expect(_confirmButton(tester).onPressed, isNull);
    expect(find.text('Preparing photo…'), findsOneWidget);
    final close = tester.widget<IconButton>(
      find.ancestor(
        of: find.byType(CloseButtonIcon),
        matching: find.byType(IconButton),
      ),
    );
    expect(close.onPressed, isNull, reason: 'close is drawn disabled');

    await tester.tap(find.byType(CloseButtonIcon), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(outcome.done, isFalse, reason: 'close left mid-encode');
    expect(find.text('Adjust profile photo'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(outcome.done, isFalse, reason: 'system back left mid-encode');
    expect(find.text('Adjust profile photo'), findsOneWidget);

    await pumpUntil(
      tester,
      () => outcome.done,
      describe: 'the encode to finish and return the photo',
    );
    expect(outcome.bytes, isNotNull);
  });

  testWidgets('system back before confirming backs out with nothing', (
    tester,
  ) async {
    final outcome = await _open(tester, _twoTonePng());
    await _decoded(tester);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(outcome.done, isTrue);
    expect(outcome.bytes, isNull);
  });

  testWidgets('the stage is bounded above the pinned confirm and still pans', (
    tester,
  ) async {
    final outcome = await _open(tester, _twoTonePng());
    await _decoded(tester);

    final stage = find.byKey(const Key('avatar-crop-stage'));
    final stageRect = tester.getRect(stage);
    final confirmRect = tester.getRect(
      find.byKey(const Key('avatar-crop-confirm')),
    );
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(stageRect.width, greaterThan(100));
    expect(stageRect.width, lessThanOrEqualTo(screen.width));
    expect(stageRect.bottom, lessThanOrEqualTo(confirmRect.top));

    // The square crop of the 40x20 photo starts centred on the red / blue
    // seam; a long drag pushes it to one end, so the upload is one colour.
    await tester.drag(stage, const Offset(-400, 0));
    await tester.pump();
    await tester.tap(find.byKey(const Key('avatar-crop-confirm')));
    await pumpUntil(
      tester,
      () => outcome.done,
      describe: 'the crop step to return the panned photo',
    );
    final out = img.decodeJpg(outcome.bytes!)!;
    expect(
      _redAt(out, 2, 10),
      _redAt(out, 17, 10),
      reason: 'the drag did not move the crop off the seam',
    );
  });

  testWidgets('Use photo clears a 48 dp navigation bar', (tester) async {
    final bytes = _twoTonePng();
    await expectEditorSaveReachable(
      tester,
      open: (context) async {
        await showAvatarCropScreen(context, bytes);
      },
      save: find.byKey(const Key('avatar-crop-confirm')),
      settle: () => _decoded(tester),
    );
  });

  worstCaseTestWidgets('Avatar crop', (tester, locale) async {
    final bytes = _twoTonePng();
    await tester.pumpWidget(
      worstCaseApp(
        locale: locale,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAvatarCropScreen(context, bytes),
              child: const Text('pick'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('pick'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _decoded(tester);
    expect(
      find.byKey(const Key('avatar-crop-confirm')).hitTestable(),
      findsOneWidget,
    );
  });
}

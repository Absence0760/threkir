import 'dart:io';
import 'dart:math' as math;

import 'package:core_models/core_models.dart' show Waypoint;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:run_recorder/run_recorder.dart' show RunSnapshot;
import 'package:ui_kit/ui_kit.dart' show AppTheme;

import '../lib/gate_crossing.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/line_calibration.dart';
import '../lib/screens/line_calibration_screen.dart';
import 'worst_case_layout.dart';

/// The debug-only calibration screen (#1304 § 6): unreachable in a release
/// build, and what it shares holds error figures, never a position.

const _lat0 = 47.123456;
const _lng0 = 8.654321;
const _mPerDegLat = 6371008.8 * math.pi / 180;
final _mPerDegLng = _mPerDegLat * math.cos(_lat0 * math.pi / 180);
final _t0 = DateTime(2026, 11, 10, 7, 0, 0);

GateFix _fix(double eastM, int ms) => GateFix(
      lat: _lat0,
      lng: _lng0 + eastM / _mPerDegLng,
      tMs: _t0.millisecondsSinceEpoch + ms.toDouble(),
      coveredM: eastM + 100,
    );

Future<void> _pump(WidgetTester tester, Widget child) async {
  // Tall enough that the whole form is built: a ListView builds lazily.
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  ));
}

/// What the run screen would have offered: a pass east at 4 m/s, over the
/// line at device 07:00:10.000, server 07:00:11.500.
void _offerPass(LineCalibrationCapture capture) {
  capture.clear();
  capture.start();
  for (var k = -5; k <= 5; k++) {
    final f = _fix(4.0 * (k * 1000 - 500) / 1000, 10000 + k * 1000 - 500);
    capture.offer(
      RunSnapshot(
        elapsed: Duration.zero,
        distanceMetres: f.coveredM,
        currentPosition: Waypoint(lat: f.lat, lng: f.lng),
        positionFixedAt: DateTime.fromMillisecondsSinceEpoch(f.tMs.round()),
      ),
      fresh: true,
      paused: false,
    );
  }
}

/// The device runs 1.5 s behind; one round trip of 40 ms.
Future<ServerClockSample?> _clock() async {
  final sent = DateTime.now();
  return (
    sentAt: sent,
    receivedAt: sent.add(const Duration(milliseconds: 40)),
    serverAt: sent.add(const Duration(milliseconds: 1520)),
  );
}

/// Scrolls the screen's list, which builds lazily, until [finder] is built,
/// then centres it. A focused field is let go first: it scrolls its caret
/// into view over a few frames, which would move [finder] after this.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.scrollUntilVisible(finder, 100,
      scrollable: find.byType(Scrollable).first);
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pump();
}

Future<void> _toTop(WidgetTester tester) async {
  tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .jumpTo(0);
  await tester.pump();
}

/// Fills the line and the instants, measures the clock and scores, from the
/// top of the screen.
Future<void> _scorePass(WidgetTester tester, AppLocalizations l10n) async {
  Future<void> type(String label, String text) async {
    final field = find.widgetWithText(TextField, label);
    await _reveal(tester, field);
    await tester.enterText(field, text);
  }

  await type(l10n.lineCalibrationLatLabel, '$_lat0');
  await type(l10n.lineCalibrationLngLabel, '$_lng0');
  await type(l10n.lineCalibrationBearingLabel, '90');
  const measure = ValueKey('line-calibration-measure');
  await _reveal(tester, find.byKey(measure));
  await tester.tap(find.byKey(measure));
  await tester.pump();
  const instants = ValueKey('line-calibration-instants');
  await _reveal(tester, find.byKey(instants));
  await tester.enterText(find.byKey(instants), '07:00:11.200');
  const score = ValueKey('line-calibration-score');
  await _reveal(tester, find.byKey(score));
  await tester.tap(find.byKey(score));
  await tester.pump();
}

void main() {
  // The test font draws every glyph a full em wide, nearly twice Manrope's
  // average, so whether a label fits is measured in the app's own font.
  setUpAll(() async {
    for (final family in ['Manrope', 'packages/ui_kit/Manrope']) {
      await (FontLoader(family)
            ..addFont(rootBundle.load('packages/ui_kit/fonts/Manrope-Regular.ttf')))
          .load();
    }
  });

  group('a release build', () {
    testWidgets('has no Settings entry', (tester) async {
      await _pump(
        tester,
        Scaffold(
          body: LineCalibrationEntry(onOpen: () {}, available: false),
        ),
      );
      expect(find.byKey(const ValueKey('line-calibration-entry')), findsNothing);
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('renders nothing of the screen', (tester) async {
      await _pump(tester, const LineCalibrationScreen(available: false));
      expect(find.byType(Scaffold), findsNothing);
      expect(find.byKey(const ValueKey('line-calibration-start')), findsNothing);
    });

    test('is the configuration the tools key off', () {
      expect(kLineCalibrationAvailable, kDebugMode);
      expect(const LineCalibrationEntry(onOpen: _noop).available, kDebugMode);
      expect(const LineCalibrationScreen().available, kDebugMode);
    });

    test('reaches the tools from nowhere outside a kDebugMode branch', () {
      // A release build compiles kDebugMode to false, so a reference inside
      // `if (kDebugMode)` is dropped. Any other one would ship the tools.
      final own = {
        'lib/line_calibration.dart',
        'lib/screens/line_calibration_screen.dart',
      };
      final refs = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (own.contains(f.path)) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final l = lines[i];
          if (!l.contains('LineCalibration')) continue;
          if (l.trimLeft().startsWith('import ')) continue;
          refs.add('${f.path}:${i + 1}');
          final window = lines.sublist(math.max(0, i - 3), i + 1).join('\n');
          expect(window, contains('if (kDebugMode)'),
              reason: '${f.path}:${i + 1} reaches the calibration tools '
                  'outside a kDebugMode branch');
        }
      }
      expect(refs, isNotEmpty,
          reason: 'the Settings entry and the run screen capture exist');
    });
  });

  testWidgets('a session scores a capture and shares figures only',
      (tester) async {
    final capture = LineCalibrationCapture();
    String? shared;
    await _pump(
      tester,
      LineCalibrationScreen(
        available: true,
        capture: capture,
        sampleServerClock: _clock,
        shareCsv: (csv) async => shared = csv,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('line-calibration-start')));
    await tester.pump();
    expect(capture.active, isTrue);

    _offerPass(capture);
    await tester.tap(find.byKey(const ValueKey('line-calibration-stop')));
    await tester.pump();
    expect(find.text('Idle: 11 fixes held'), findsOneWidget);

    await _scorePass(tester, lookupAppLocalizations(const Locale('en')));
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('line-calibration-offset')))
            .controller!
            .text,
        '1500');
    expect(find.byKey(const ValueKey('line-calibration-problem')), findsNothing);
    expect(
        find.textContaining(
            '1 of 1 matched, 0 missed, 0 false, 0 near; median 300 ms'),
        findsOneWidget);
    expect(find.textContaining('offset ±20 ms'), findsOneWidget);
    expect(find.text('At 90° to the line / Run / Phone in hand'), findsOneWidget,
        reason: 'a result names its cell in words, not wire values');

    await tester.ensureVisible(find.byKey(const ValueKey('line-calibration-share')));
    await tester.tap(find.byKey(const ValueKey('line-calibration-share')));
    await tester.pump();
    expect(shared, isNotNull);
    expect(shared, contains('summary,90,run,phone_hand,'));
    expect(shared!.trim().split('\n').last, endsWith(',300,300,300,40'),
        reason: 'the offset round trip rides the summary');
    for (final leak in ['47.12', '8.65', '07:00', '2026']) {
      expect(shared, isNot(contains(leak)), reason: '$leak left the device');
    }
  });

  testWidgets('a capture cannot be scored without its line', (tester) async {
    await _pump(
      tester,
      LineCalibrationScreen(available: true, capture: LineCalibrationCapture()),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('line-calibration-score')));
    await tester.tap(find.byKey(const ValueKey('line-calibration-score')));
    await tester.pump();
    expect(find.byKey(const ValueKey('line-calibration-problem')), findsOneWidget);
    expect(find.byKey(const ValueKey('line-calibration-share')), findsNothing);
  });

  testWidgets('the pickers name each choice in words, never its wire value',
      (tester) async {
    await _pump(
      tester,
      LineCalibrationScreen(available: true, capture: LineCalibrationCapture()),
    );
    for (final wire in ['90', 'run', 'phone_hand']) {
      expect(find.text(wire), findsNothing, reason: wire);
    }
    expect(find.text('At 90° to the line'), findsOneWidget);
    expect(find.text('Run'), findsOneWidget);
    expect(find.text('Phone in hand'), findsOneWidget);
  });

  // Issue #1374: on a 320 dp phone at normal text size two fields shared a
  // row and cut their labels ("Line centre longitu…"), and the fields
  // touched, so each floating label sat on the field above.
  for (final locale in kWorstCaseLocales) {
    testWidgets(
        'every field label is whole and clear of the field above at 320 dp '
        '[${locale.toLanguageTag()}]', (tester) async {
      tester.view.physicalSize = kWorstCasePhone;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final l10n = l10nFor(locale);
      final capture = LineCalibrationCapture();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LineCalibrationScreen(
            available: true, capture: capture, sampleServerClock: _clock),
      ));
      await tester.pump();
      _offerPass(capture);
      await _scorePass(tester, l10n);
      final labels = [
        l10n.lineCalibrationLatLabel,
        l10n.lineCalibrationLngLabel,
        l10n.lineCalibrationBearingLabel,
        l10n.lineCalibrationHalfWidthLabel,
        l10n.lineCalibrationOffsetLabel,
        l10n.lineCalibrationApproachLabel,
        l10n.lineCalibrationPaceLabel,
        l10n.lineCalibrationCarryLabel,
        l10n.lineCalibrationInstantsLabel,
      ];
      await _toTop(tester);
      Finder decorator(String label) => find
          .ancestor(of: find.text(label), matching: find.byType(InputDecorator))
          .first;
      String? previous;
      for (final label in labels) {
        final text = find.text(label);
        await _reveal(tester, text);
        final para = tester.renderObject<RenderParagraph>(text);
        expect(para.didExceedMaxLines, isFalse, reason: '"$label" is cut');
        if (previous != null &&
            find.text(previous).evaluate().isNotEmpty &&
            // A field that is not stacked straight above (the buttons
            // between the line and the offset) cannot be overlapped.
            tester.getRect(decorator(previous)).bottom <=
                tester.getRect(decorator(label)).top) {
          expect(tester.getRect(text).top,
              greaterThanOrEqualTo(tester.getRect(decorator(previous)).bottom),
              reason: '"$label" overlaps the field above');
        }
        previous = label;
      }
    });
  }

  worstCaseTestWidgets('Line calibration', (tester, locale) async {
    final capture = LineCalibrationCapture();
    await tester.pumpWidget(worstCaseApp(
      locale: locale,
      home: LineCalibrationScreen(
          available: true, capture: capture, sampleServerClock: _clock),
    ));
    await tester.pump();
    _offerPass(capture);
    await _scorePass(tester, l10nFor(locale));
    expect(find.byKey(const ValueKey('line-calibration-problem')), findsNothing);
    await walkScrollable(tester, primaryScrollable(), 'Line calibration');
    // A failed score lays out its problem line too.
    await _toTop(tester);
    const instants = ValueKey('line-calibration-instants');
    await _reveal(tester, find.byKey(instants));
    await tester.enterText(find.byKey(instants), 'not a time');
    const score = ValueKey('line-calibration-score');
    await _reveal(tester, find.byKey(score));
    await tester.tap(find.byKey(score));
    await tester.pump();
    expect(find.byKey(const ValueKey('line-calibration-problem')), findsOneWidget);
    await walkScrollable(tester, primaryScrollable(), 'Line calibration, problem');
  });
}

void _noop() {}

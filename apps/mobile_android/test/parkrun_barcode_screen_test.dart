// ignore_for_file: avoid_relative_lib_imports
import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/parkrun_barcode_cache.dart';
import '../lib/screen_brightness_bridge.dart';
import '../lib/screens/parkrun_barcode_screen.dart';
import '../lib/widgets/parkrun_barcode_view.dart';
import 'pump_until.dart';

class _FakeApi extends ApiClient {
  _FakeApi({this.number, this.offline = false, this.saveFails = false});

  String? number;
  final bool offline;
  final bool saveFails;
  final saved = <String?>[];

  @override
  String? get userId => 'u1';

  @override
  Future<UserProfileRow?> fetchMyProfile() async {
    if (offline) throw Exception('no network');
    return UserProfileRow(id: 'u1', parkrunNumber: number, shadowHidden: false);
  }

  @override
  Future<void> setParkrunAthleteNumber(String? athleteNumber) async {
    if (saveFails) throw Exception('refused');
    saved.add(athleteNumber);
    number = athleteNumber;
  }
}

class _FakeBrightness extends ScreenBrightnessBridge {
  final calls = <String>[];

  @override
  Future<void> setMax() async => calls.add('setMax');

  @override
  Future<void> restore() async => calls.add('restore');
}

String _cacheEntry(String userId, String number) =>
    jsonEncode({'user_id': userId, 'number': number});

void main() {
  Future<_FakeBrightness> pump(
    WidgetTester tester,
    _FakeApi api, {
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final brightness = _FakeBrightness();
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ParkrunBarcodeScreen(api: api, brightness: brightness),
    ));
    return brightness;
  }

  testWidgets('offline, the device copy still shows the barcode',
      (tester) async {
    await pump(tester, _FakeApi(offline: true), prefs: {
      ParkrunBarcodeCache.storageKey: _cacheEntry('u1', 'A123456'),
    });
    await pumpUntil(
      tester,
      () => find.byKey(const ValueKey('parkrun-barcode-offline')).evaluate().isNotEmpty,
      describe: 'the offline note',
    );
    expect(find.byType(ParkrunBarcodeView), findsOneWidget);
    expect(find.bySemanticsLabel('parkrun barcode for athlete number A123456'),
        findsOneWidget);
  });

  testWidgets("another account's copy is never shown", (tester) async {
    await pump(tester, _FakeApi(offline: true), prefs: {
      ParkrunBarcodeCache.storageKey: _cacheEntry('someone-else', 'A999'),
    });
    await pumpUntil(
      tester,
      () => find.text('Try again').evaluate().isNotEmpty,
      describe: 'the load-failed state',
    );
    expect(find.byType(ParkrunBarcodeView), findsNothing);
  });

  testWidgets('the server number replaces the copy and is cached',
      (tester) async {
    await pump(tester, _FakeApi(number: 'A7654321'), prefs: {
      ParkrunBarcodeCache.storageKey: _cacheEntry('u1', 'A123456'),
    });
    await pumpUntil(
      tester,
      () => find.text('A7654321').evaluate().isNotEmpty,
      describe: 'the server number',
    );
    expect(find.byKey(const ValueKey('parkrun-barcode-offline')), findsNothing);
    final cached = await tester.runAsync(() => const ParkrunBarcodeCache().read('u1'));
    expect(cached, 'A7654321');
  });

  testWidgets('with no number saved, one can be added from the screen',
      (tester) async {
    final api = _FakeApi();
    await pump(tester, api);
    await pumpUntil(
      tester,
      () => find.byKey(const ValueKey('parkrun-barcode-add')).evaluate().isNotEmpty,
      describe: 'the add button',
    );
    expect(find.byType(ParkrunBarcodeView), findsNothing);

    await tester.tap(find.byKey(const ValueKey('parkrun-barcode-add')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final field = find.byKey(const ValueKey('parkrun-barcode-field'));

    await tester.enterText(field, '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    expect(find.text('Enter A followed by digits, for example A123456.'),
        findsOneWidget);
    expect(api.saved, isEmpty);

    await tester.enterText(field, ' a42 ');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await pumpUntil(
      tester,
      () => find.byType(ParkrunBarcodeView).evaluate().isNotEmpty,
      describe: 'the barcode after saving',
    );
    expect(api.saved, ['A42']);
    final cached = await tester.runAsync(() => const ParkrunBarcodeCache().read('u1'));
    expect(cached, 'A42');
  });

  testWidgets('a failed save says so and keeps the code already shown',
      (tester) async {
    final api = _FakeApi(number: 'A1', saveFails: true);
    await pump(tester, api);
    await pumpUntil(
      tester,
      () => find.byType(ParkrunBarcodeView).evaluate().isNotEmpty,
      describe: 'the barcode',
    );

    await tester.tap(find.widgetWithText(TextButton, 'Change athlete number'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
        find.byKey(const ValueKey('parkrun-barcode-field')), 'A2');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await pumpUntil(
      tester,
      () => find
          .text("Couldn't save your athlete number: Exception: refused")
          .evaluate()
          .isNotEmpty,
      describe: 'the save-failed banner',
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('A1'), findsOneWidget);
    expect(api.saved, isEmpty);
    await tester.pump(const Duration(seconds: 4)); // drain banner timer
  });

  testWidgets('a stored value outside parkrun format is not drawn',
      (tester) async {
    await pump(tester, _FakeApi(number: '1234 5678'));
    await pumpUntil(
      tester,
      () => find.text('Change athlete number').evaluate().isNotEmpty,
      describe: 'the invalid state',
    );
    expect(find.byType(ParkrunBarcodeView), findsNothing);
  });

  testWidgets('brightness goes to full while shown and back on leaving',
      (tester) async {
    final brightness = await pump(tester, _FakeApi(number: 'A1'));
    await tester.pump();
    expect(brightness.calls, ['setMax']);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(brightness.calls, ['setMax', 'restore']);
  });

  group('ParkrunBarcodeLoad', () {
    test('the server value decides ready, none or invalid', () {
      expect(ParkrunBarcodeLoad.fromServer('a 1').number, 'A1');
      expect(ParkrunBarcodeLoad.fromServer(null).kind, ParkrunBarcodeLoadKind.none);
      expect(ParkrunBarcodeLoad.fromServer('  ').kind, ParkrunBarcodeLoadKind.none);
      expect(ParkrunBarcodeLoad.fromServer('B1').kind, ParkrunBarcodeLoadKind.invalid);
    });

    test('a failed refresh keeps a code already showing', () {
      const cached = ParkrunBarcodeLoad.cached('A1');
      expect(identical(cached.afterFetchFailed(), cached), isTrue);
      expect(const ParkrunBarcodeLoad.loading().afterFetchFailed().kind,
          ParkrunBarcodeLoadKind.unavailable);
    });
  });
}

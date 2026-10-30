// Settings → Preferences "How much detail" (#905, #1187): the universal
// `disclosure_level` key, with a fourth Automatic choice that deletes the key
// and hands the level back to the derivation. Web twin: `/settings/display`'s
// `disclosure-level-select`.

import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/disclosure.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';
import '../lib/settings_sync.dart';

class _FakeSettingsService extends SettingsService {
  _FakeSettingsService(this._values)
      : super(deviceId: 'test-device', platform: 'android');

  final Map<String, dynamic> _values;

  @override
  T? effective<T>(String key, {T? fallback}) =>
      _values.containsKey(key) ? _values[key] as T? : fallback;
}

class _FakeSettingsSync extends SettingsSyncService {
  _FakeSettingsSync(Preferences prefs, this._service)
      : super(preferences: prefs);

  final SettingsService? _service;

  final List<Map<String, dynamic>> pushed = [];

  /// Only the writes this tile owns; the screen also stamps `locale` on mount.
  List<Map<String, dynamic>> get levelWrites => [
        for (final w in pushed)
          if (w.containsKey(disclosureLevelKey)) w,
      ];

  @override
  bool get synced => true;

  @override
  SettingsService? get service => _service;

  @override
  Future<void> updateUniversal(Map<String, dynamic> values) async {
    pushed.add(values);
  }
}

const _tileKey = Key('prefsDisclosureLevel');

Future<_FakeSettingsSync> _pumpPreferences(
  WidgetTester tester,
  Map<String, dynamic> bag, {
  LocalRunStore? runStore,
}) async {
  final prefs = Preferences();
  await tester.runAsync(prefs.init);
  final sync = _FakeSettingsSync(prefs, _FakeSettingsService(bag));
  tester.view.physicalSize = const Size(400, 8000) * 2;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsPreferencesScreen(
        preferences: prefs,
        settingsSync: sync,
        runStore: runStore,
      ),
    ),
  );
  await tester.pumpAndSettle();
  final tile = find.byKey(_tileKey);
  await tester.scrollUntilVisible(tile, 300,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  return sync;
}

Finder _inTile(String text) =>
    find.descendant(of: find.byKey(_tileKey), matching: find.text(text));

Finder _hintNaming(String level) => find.descendant(
      of: find.byKey(_tileKey),
      matching: find.textContaining('and picks $level today'),
    );

Future<void> _pick(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(_tileKey));
  await tester.pumpAndSettle();
  expect(find.byType(SimpleDialog), findsOneWidget);
  await tester.tap(find.descendant(
    of: find.byType(SimpleDialog),
    matching: find.text(label),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('with nothing stored the tile reads Automatic and names the '
      'level it derives', (tester) async {
    await _pumpPreferences(tester, <String, dynamic>{});
    expect(_inTile('Automatic'), findsOneWidget);
    expect(_hintNaming('Just the basics'), findsOneWidget);
  });

  testWidgets('the hint derives from the stored onboarding goal',
      (tester) async {
    await _pumpPreferences(
        tester, <String, dynamic>{SettingsKeys.primaryGoal: 'marathon'});
    expect(_hintNaming('Everything'), findsOneWidget);
  });

  testWidgets('the hint derives from the run history on the device',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('prefs_disclosure_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final runStore = LocalRunStore();
    await tester.runAsync(() async {
      await runStore.init(overrideDirectory: dir);
      final now = DateTime.now().toUtc();
      for (var i = 0; i < disclosureStandardRuns; i++) {
        await runStore.save(Run(
          id: 'r$i',
          startedAt: now.subtract(Duration(days: i)),
          duration: const Duration(minutes: 25),
          distanceMetres: 5000,
          source: RunSource.app,
        ));
      }
    });
    await _pumpPreferences(tester, <String, dynamic>{}, runStore: runStore);
    expect(_hintNaming('The usual'), findsOneWidget);
  });

  testWidgets('the tile reads a stored level', (tester) async {
    await _pumpPreferences(
        tester, <String, dynamic>{disclosureLevelKey: 'full'});
    expect(_inTile('Everything'), findsOneWidget);
    expect(_inTile('Automatic'), findsNothing);
  });

  testWidgets('an unrecognised stored level reads as Automatic',
      (tester) async {
    await _pumpPreferences(
        tester, <String, dynamic>{disclosureLevelKey: 'everything'});
    expect(_inTile('Automatic'), findsOneWidget);
  });

  testWidgets('picking a level writes it to the universal bag',
      (tester) async {
    final sync = await _pumpPreferences(tester, <String, dynamic>{});
    await _pick(tester, 'Just the basics');
    expect(sync.levelWrites, [
      {disclosureLevelKey: 'simple'},
    ]);
  });

  testWidgets('picking Automatic deletes the key rather than storing a level',
      (tester) async {
    final sync = await _pumpPreferences(
        tester, <String, dynamic>{disclosureLevelKey: 'full'});
    await _pick(tester, 'Automatic');
    expect(sync.levelWrites, hasLength(1));
    final write = sync.levelWrites.single;
    expect(write.containsKey(disclosureLevelKey), isTrue);
    expect(write[disclosureLevelKey], isNull,
        reason: 'a null value removes the key from the bag');
  });

  testWidgets('re-picking the current choice, or dismissing, writes nothing',
      (tester) async {
    final sync = await _pumpPreferences(
        tester, <String, dynamic>{disclosureLevelKey: 'standard'});
    await _pick(tester, 'The usual');
    await tester.tap(find.byKey(_tileKey));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsNothing);
    expect(sync.levelWrites, isEmpty);
  });
}

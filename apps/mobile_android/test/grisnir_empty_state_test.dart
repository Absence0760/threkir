// Grisnir waits in the "nothing yet" states that name him and onboarding
// (#1364), is hidden when the runner turns show_mascot off, and can never
// appear in an error state: ErrorState has no art slot, and only the named
// surfaces draw him.

import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart';

import '../lib/mascot.dart';
import '../lib/preferences.dart';
import '../lib/settings_sync.dart';
import '../lib/widgets/grisnir_moments.dart';

class _Sync extends SettingsSyncService {
  _Sync(Preferences prefs, this._service) : super(preferences: prefs);
  final SettingsService? _service;
  @override
  bool get synced => true;
  @override
  SettingsService? get service => _service;
}

class _Service extends SettingsService {
  _Service(this.values) : super(deviceId: 'test-device', platform: 'android');
  final Map<String, dynamic> values;
  @override
  T? effective<T>(String key, {T? fallback}) =>
      values.containsKey(key) ? values[key] as T? : fallback;
}

Future<void> _showMascot(bool? value) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  registerActiveSettingsSync(_Sync(prefs, _Service({'show_mascot': ?value})));
}

Widget _host() => MaterialApp(
      home: Scaffold(
        body: EmptyState(
          icon: Icons.directions_run,
          illustration: grisnirWaitingOrNull(),
          title: 'No runs yet',
        ),
      ),
    );

void main() {
  tearDown(() => registerActiveSettingsSync(null));

  testWidgets('an opted-in empty state draws him in place of the icon',
      (tester) async {
    await _showMascot(true);
    await tester.pumpWidget(_host());
    final art = tester.widget<Image>(find.byKey(const Key('empty-state-grisnir')));
    expect((art.image as AssetImage).assetName, kGrisnirWaitAsset);
    expect(art.excludeFromSemantics, isTrue);
    expect(find.byIcon(Icons.directions_run), findsNothing);
  });

  testWidgets('show_mascot off falls back to the icon', (tester) async {
    await _showMascot(false);
    await tester.pumpWidget(_host());
    expect(find.byKey(const Key('empty-state-grisnir')), findsNothing);
    expect(find.byIcon(Icons.directions_run), findsOneWidget);
  });

  test('ErrorState takes no art, so an error can never carry him', () {
    for (final path in [
      'lib/widgets/error_state.dart',
      '../../packages/ui_kit/lib/src/widgets/error_state.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(src, isNot(contains('Widget?')), reason: path);
      expect(src, isNot(contains('illustration')), reason: path);
      expect(src, isNot(contains('Grisnir')), reason: path);
    }
  });

  test('only the named "nothing yet" surfaces and onboarding draw him', () {
    final users = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('widgets/grisnir_moments.dart')) continue;
      final src = f.readAsStringSync();
      if (src.contains('grisnirWaitingOrNull(') ||
          src.contains('GrisnirWaiting(')) {
        users.add(f.path.replaceAll('\\', '/'));
      }
    }
    users.sort();
    expect(users, [
      'lib/screens/feed_screen.dart',
      'lib/screens/onboarding_screen.dart',
      'lib/screens/routes_screen.dart',
      'lib/screens/runs_screen.dart',
    ]);
  });
}

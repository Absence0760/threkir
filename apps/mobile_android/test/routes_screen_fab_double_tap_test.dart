// The Build FAB and the Import action are one-shot entry points with a transition long
// enough to tap twice. Neither carried an in-flight guard, so a double-tap on
// Build stacked two route builders — build and save in the top one, it pops,
// and you land on a second empty builder as though the save was discarded.

import 'dart:async';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/routes_screen.dart';
import 'pump_until.dart';

class _FakeApi extends ApiClient {}

/// Holds the system picker open until the test releases it, so the in-flight
/// window can be inspected the way a real picker's would be.
class _HeldFilePicker {
  static const _channel =
      MethodChannel('miguelruivo.flutter.plugins.filepicker');

  final completer = Completer<List<Object?>?>();
  int calls = 0;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) {
      calls++;
      return completer.future;
    });
  }

  void remove() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }
}

Future<Preferences> _makePrefs() async {
  SharedPreferences.setMockInitialValues({});
  final p = Preferences();
  await p.init();
  return p;
}

Future<void> _pump(WidgetTester tester, Preferences prefs) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RoutesScreen(
        apiClient: _FakeApi(),
        routeStore: LocalRouteStore(),
        preferences: prefs,
      ),
    ),
  );
}

// Build is the one FAB, labelled; Import is an AppBar action, named by its
// tooltip.
Finder _fab(String label) => label == 'Import'
    ? find.ancestor(
        of: find.byTooltip(label),
        matching: find.byType(IconButton),
      )
    : find.ancestor(
        of: find.text(label),
        matching: find.byType(FloatingActionButton),
      );

VoidCallback? _onPressed(WidgetTester tester, String label) =>
    label == 'Import'
        ? tester.widget<IconButton>(_fab(label)).onPressed
        : tester.widget<FloatingActionButton>(_fab(label)).onPressed;

void main() {
  late _HeldFilePicker picker;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    picker = _HeldFilePicker()..install();
  });

  tearDown(() => picker.remove());

  testWidgets('a double-tap on Import opens exactly one picker',
      (tester) async {
    final prefs = await _makePrefs();
    await _pump(tester, prefs);
    await tester.pump();

    await tester.tap(_fab('Import'));
    await tester.pump();
    await tester.tap(_fab('Import'), warnIfMissed: false);
    await tester.pump();

    expect(picker.calls, 1);

    picker.completer.complete(null);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  });

  testWidgets('Build and Import are disabled while one of them has a surface open',
      (tester) async {
    final prefs = await _makePrefs();
    await _pump(tester, prefs);
    await tester.pump();

    expect(_onPressed(tester, 'Build'), isNotNull);
    expect(_onPressed(tester, 'Import'), isNotNull);

    await tester.tap(_fab('Import'));
    await tester.pump();

    expect(_onPressed(tester, 'Build'), isNull,
        reason: 'the builder must not stack on top of an open picker');
    expect(_onPressed(tester, 'Import'), isNull);

    picker.completer.complete(null);
    await pumpUntil(tester, () => _onPressed(tester, 'Import') != null,
        describe: 'the released picker to re-arm Build and Import');
    await tester.pumpAndSettle();

    expect(_onPressed(tester, 'Build'), isNotNull);
    expect(_onPressed(tester, 'Import'), isNotNull);
  });

  group('import failures say what happened', () {
    const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');

    void answerPicker(Future<Object?> Function() answer) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) => answer());
    }

    testWidgets('a picker the OS refuses shows a banner and re-arms Import',
        (tester) async {
      answerPicker(() async =>
          throw PlatformException(code: 'already_active', message: 'busy'));
      final prefs = await _makePrefs();
      await _pump(tester, prefs);
      await tester.pump();

      await tester.tap(_fab('Import'));
      await pumpUntil(tester, () => _onPressed(tester, 'Import') != null,
          describe: 'Import to re-arm after the refused picker');
      await tester.pump();
      expect(find.textContaining('Import failed'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('a file with no two-point line says so', (tester) async {
      final dir = Directory.systemTemp.createTempSync('routes_import_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/one_point.gpx')
        ..writeAsStringSync('<?xml version="1.0"?>'
            '<gpx version="1.1" creator="t"><trk><trkseg>'
            '<trkpt lat="51.5" lon="-0.12"></trkpt>'
            '</trkseg></trk></gpx>');
      answerPicker(() async => [
            {
              'name': 'one_point.gpx',
              'path': file.path,
              'size': file.lengthSync(),
            },
          ]);
      final prefs = await _makePrefs();
      await _pump(tester, prefs);
      await tester.pump();

      await tester.tap(_fab('Import'));
      await pumpUntil(
          tester,
          () => find
              .text('Import failed: that file holds no route with at least '
                  'two points.')
              .evaluate()
              .isNotEmpty,
          describe: 'the no-route banner');
      expect(find.textContaining('cloud-only'), findsNothing,
          reason: 'the file came from local storage; blaming the picker '
              'sends the runner to fix the wrong thing');
      await tester.pump(const Duration(seconds: 10));
    });
  });
}

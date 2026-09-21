import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/ble_heart_rate.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/settings_integrations_screen.dart';

/// Fake strap: reports a paired name and records whether forget() ran, so the
/// tile's confirm-before-unpair flow can be driven without a real BLE adapter.
class _FakeHeartRate extends BleHeartRate {
  _FakeHeartRate({String? name, this.scanRefusal}) : _name = name;
  String? _name;
  int forgetCalls = 0;

  /// When set, [scan] refuses with this reason instead of producing
  /// candidates — the shape a real adapter takes when the radio is off or
  /// the grant was denied, neither of which a test machine can reproduce.
  final BleReadiness? scanRefusal;

  @override
  Stream<List<BleDeviceCandidate>> scan({
    Duration timeout = const Duration(seconds: 8),
  }) {
    final reason = scanRefusal;
    if (reason == null) return const Stream.empty();
    return Stream<List<BleDeviceCandidate>>.error(BleUnavailable(reason));
  }

  @override
  Future<String?> pairedName() async => _name;

  @override
  Future<void> forget() async {
    forgetCalls++;
    _name = null;
  }
}

Widget _host(BleHeartRate hr) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: HeartRateMonitorTile(heartRate: hr)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('forget confirms first; Cancel keeps the strap paired',
      (tester) async {
    final hr = _FakeHeartRate(name: 'Polar H10');
    await tester.pumpWidget(_host(hr));
    await tester.pumpAndSettle();

    expect(find.text('Paired: Polar H10'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    // Confirm dialog — unpair is NOT immediate.
    expect(
      find.text(
          "Forget this heart rate monitor? You'll need to pair it again to use it during a run."),
      findsOneWidget,
    );

    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(TextButton, 'Cancel'),
    ));
    await tester.pumpAndSettle();

    expect(hr.forgetCalls, 0);
    expect(find.text('Paired: Polar H10'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('confirming forget unpairs the strap', (tester) async {
    final hr = _FakeHeartRate(name: 'Polar H10');
    await tester.pumpWidget(_host(hr));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Forget'),
    ));
    await tester.pumpAndSettle();

    expect(hr.forgetCalls, 1);
    expect(find.text('No strap paired — tap to scan'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('a denied Bluetooth grant is named, with the only remedy that works',
      (tester) async {
    final hr = _FakeHeartRate(scanRefusal: BleReadiness.unauthorized);
    await tester.pumpWidget(_host(hr));
    await tester.pumpAndSettle();

    await tester.tap(find.text('No strap paired — tap to scan'));
    await tester.pumpAndSettle();

    // NOT "No straps found. Make sure it's nearby and awake." — the strap is
    // not the problem, and no amount of rescanning clears a revoked grant.
    expect(find.text("No straps found. Make sure it's nearby and awake."),
        findsNothing);
    expect(
      find.text(
          "Threkir isn't allowed to use Bluetooth. Allow it in Settings to use a heart-rate strap."),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Open settings'), findsOneWidget);

    // The remedy is an L4 auxiliary effect: with no platform channel bound
    // it must swallow its own failure rather than take the sheet down.
    await tester.tap(find.widgetWithText(FilledButton, 'Open settings'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a powered-off radio says so, and offers no dead-end button',
      (tester) async {
    final hr = _FakeHeartRate(scanRefusal: BleReadiness.poweredOff);
    await tester.pumpWidget(_host(hr));
    await tester.pumpAndSettle();

    await tester.tap(find.text('No strap paired — tap to scan'));
    await tester.pumpAndSettle();

    expect(
      find.text('Bluetooth is off — turn it on to use your heart-rate strap.'),
      findsOneWidget,
    );
    // Only a denied grant is fixable on the app's settings page; the radio
    // toggle is not somewhere the app can deep-link to.
    expect(find.widgetWithText(FilledButton, 'Open settings'), findsNothing);
  });

  testWidgets('a served scan that finds nothing still says "no straps found"',
      (tester) async {
    final hr = _FakeHeartRate();
    await tester.pumpWidget(_host(hr));
    await tester.pumpAndSettle();

    await tester.tap(find.text('No strap paired — tap to scan'));
    await tester.pumpAndSettle();

    expect(find.text("No straps found. Make sure it's nearby and awake."),
        findsOneWidget);
  });
}

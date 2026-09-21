import 'dart:async';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/ble_heart_rate.dart';
import '../lib/l10n/gen/app_localizations_en.dart';
import '../lib/ble_readiness_labels.dart';

/// The whole point of this file: no simulator and no CI runner has a
/// Bluetooth radio, so the readiness decision — which is what stands between
/// an iOS runner and a pairing sheet that lies to them — has to be provable
/// without one. Everything here drives the decision through a plain
/// `StreamController` via the `adapterStatusOverride` seam.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('bleReadinessFrom', () {
    test('maps every BleStatus the plugin can report', () {
      expect(bleReadinessFrom(BleStatus.ready), BleReadiness.ready);
      expect(bleReadinessFrom(BleStatus.unknown), BleReadiness.initialising);
      expect(bleReadinessFrom(BleStatus.poweredOff), BleReadiness.poweredOff);
      expect(
          bleReadinessFrom(BleStatus.unauthorized), BleReadiness.unauthorized);
      expect(bleReadinessFrom(BleStatus.unsupported), BleReadiness.unsupported);
      expect(bleReadinessFrom(BleStatus.locationServicesDisabled),
          BleReadiness.locationServicesDisabled);
    });

    test('covers the plugin enum exhaustively', () {
      // A plugin bump that adds a status must fail here rather than fall
      // through a `default:` into a wrong verdict.
      for (final s in BleStatus.values) {
        expect(() => bleReadinessFrom(s), returnsNormally, reason: '$s');
      }
      expect(BleStatus.values.length, BleReadiness.values.length);
    });
  });

  group('bleAdapterSettleTimeoutFor', () {
    test('iOS gets a budget a person can answer a modal alert inside', () {
      // The wait on iOS is not a system callback: CoreBluetooth withholds
      // `centralManagerDidUpdateState` until the authorization alert is
      // answered, so a budget sized for a radio expires while the runner is
      // still reading it and the sheet claims Bluetooth "didn't respond".
      final ios = bleAdapterSettleTimeoutFor(isIOS: true);
      expect(ios.inSeconds, greaterThanOrEqualTo(15));
      expect(bleAdapterSettleTimeoutFor(isIOS: false).inSeconds,
          lessThan(ios.inSeconds));
    });

    test('neither budget is unbounded', () {
      for (final isIOS in [true, false]) {
        final d = bleAdapterSettleTimeoutFor(isIOS: isIOS);
        expect(d, greaterThan(Duration.zero), reason: 'isIOS=$isIOS');
        expect(d, lessThanOrEqualTo(const Duration(minutes: 1)),
            reason: 'isIOS=$isIOS');
      }
    });
  });

  group('bleReadinessIsRetryable', () {
    test('a rescan is offered only where a rescan could work', () {
      expect(bleReadinessIsRetryable(BleReadiness.unauthorized), isFalse);
      expect(bleReadinessIsRetryable(BleReadiness.unsupported), isFalse);
      expect(bleReadinessIsRetryable(BleReadiness.poweredOff), isTrue);
      expect(bleReadinessIsRetryable(BleReadiness.initialising), isTrue);
      expect(
          bleReadinessIsRetryable(BleReadiness.locationServicesDisabled), isTrue);
    });

    test('no reason is both retryable and a Settings trip', () {
      // Two controls for one problem is a worse answer than one, and the
      // sheet renders them as an either/or.
      for (final r in BleReadiness.values) {
        expect(bleReadinessIsRetryable(r) && bleReadinessNeedsAppSettings(r),
            isFalse,
            reason: '$r');
      }
    });

    test('every non-ready reason offers exactly one control, or names why not',
        () {
      for (final r in BleReadiness.values) {
        if (r == BleReadiness.ready) continue;
        final controls = [
          bleReadinessIsRetryable(r),
          bleReadinessNeedsAppSettings(r),
        ].where((x) => x).length;
        expect(controls, r == BleReadiness.unsupported ? 0 : 1, reason: '$r');
      }
    });
  });

  group('bleReadinessNeedsAppSettings', () {
    test('only a denied grant sends the runner to the Settings app', () {
      for (final r in BleReadiness.values) {
        expect(bleReadinessNeedsAppSettings(r), r == BleReadiness.unauthorized,
            reason: '$r');
      }
    });
  });

  group('resolveBleReadiness', () {
    test('waits past the transient unknown CoreBluetooth starts in', () async {
      final c = StreamController<BleStatus>();
      final future = resolveBleReadiness(c.stream);
      c.add(BleStatus.unknown);
      c.add(BleStatus.unknown);
      c.add(BleStatus.ready);
      expect(await future, BleReadiness.ready);
      await c.close();
    });

    test('reports the first settled status, not the last', () async {
      final c = StreamController<BleStatus>();
      final future = resolveBleReadiness(c.stream);
      c.add(BleStatus.unknown);
      c.add(BleStatus.unauthorized);
      c.add(BleStatus.ready);
      expect(await future, BleReadiness.unauthorized);
      await c.close();
    });

    test('an adapter that only ever says unknown times out as initialising',
        () async {
      final c = StreamController<BleStatus>();
      final future = resolveBleReadiness(
        c.stream,
        timeout: const Duration(milliseconds: 20),
      );
      c.add(BleStatus.unknown);
      expect(await future, BleReadiness.initialising);
      await c.close();
    });

    test('a stream that closes without reporting is initialising, not ready',
        () async {
      // firstWhere throws StateError on an empty stream. Failing open to
      // `ready` here would send a scan at a radio that never answered.
      final c = StreamController<BleStatus>();
      final future = resolveBleReadiness(c.stream);
      await c.close();
      expect(await future, BleReadiness.initialising);
    });

    test('poweredOff and unsupported pass straight through', () async {
      expect(await resolveBleReadiness(Stream.value(BleStatus.poweredOff)),
          BleReadiness.poweredOff);
      expect(await resolveBleReadiness(Stream.value(BleStatus.unsupported)),
          BleReadiness.unsupported);
    });
  });

  group('BleHeartRate.scan through the adapter seam', () {
    test('a denied grant reaches the caller as a named reason', () async {
      final ble = BleHeartRate();
      ble.adapterStatusOverride = () => Stream.value(BleStatus.unauthorized);
      await expectLater(
        ble.scan(),
        emitsError(isA<BleUnavailable>().having(
            (e) => e.reason, 'reason', BleReadiness.unauthorized)),
      );
      expect(ble.lastUnavailable, BleReadiness.unauthorized);
      await ble.dispose();
    });

    test('a powered-off radio does not degrade into an empty result list',
        () async {
      // The bug this pins: the sheet's only other outcome is "No straps
      // found. Make sure it's nearby and awake." — advice for a problem the
      // runner does not have.
      final ble = BleHeartRate();
      ble.adapterStatusOverride = () => Stream.value(BleStatus.poweredOff);
      await expectLater(
        ble.scan(),
        emitsInOrder([
          emitsError(isA<BleUnavailable>()
              .having((e) => e.reason, 'reason', BleReadiness.poweredOff)),
          emitsDone,
        ]),
      );
      await ble.dispose();
    });

    test('an adapter that never answers is reported, not waited on forever',
        () async {
      final ble = BleHeartRate();
      ble.adapterStatusOverride = () => Stream.value(BleStatus.unknown);
      await expectLater(
        ble.scan(),
        emitsError(isA<BleUnavailable>()
            .having((e) => e.reason, 'reason', BleReadiness.initialising)),
      );
      await ble.dispose();
    });

    test('connectCached refuses before touching the radio, and says why',
        () async {
      SharedPreferences.setMockInitialValues(
          {'ble_hr_device_id': 'AA:BB:CC:DD:EE:FF'});
      final ble = BleHeartRate();
      ble.adapterStatusOverride = () => Stream.value(BleStatus.unauthorized);
      expect(await ble.connectCached(), isFalse);
      expect(ble.lastUnavailable, BleReadiness.unauthorized);
      expect(ble.status, BleHrStatus.connectFailed);
      await ble.dispose();
    });

    test('no paired strap short-circuits before the adapter is consulted',
        () async {
      SharedPreferences.setMockInitialValues({});
      final ble = BleHeartRate();
      var consulted = false;
      ble.adapterStatusOverride = () {
        consulted = true;
        return Stream.value(BleStatus.ready);
      };
      expect(await ble.connectCached(), isFalse);
      expect(consulted, isFalse);
      expect(ble.lastUnavailable, isNull);
      await ble.dispose();
    });
  });

  group('bleReadinessMessage', () {
    final l10n = AppLocalizationsEn();

    test('every non-ready reason has a sentence', () {
      for (final r in BleReadiness.values) {
        final msg = bleReadinessMessage(l10n, r);
        if (r == BleReadiness.ready) {
          expect(msg, isNull);
        } else {
          expect(msg, isNotNull, reason: '$r');
          expect(msg!.trim(), isNotEmpty, reason: '$r');
        }
      }
    });

    test('each reason gets its own sentence', () {
      final seen = <String>{};
      for (final r in BleReadiness.values) {
        final msg = bleReadinessMessage(l10n, r);
        if (msg == null) continue;
        expect(seen.add(msg), isTrue, reason: '$r reuses another reason copy');
      }
    });
  });

  group('bleConnectFailureDisclosure', () {
    final l10n = AppLocalizationsEn();

    test('a ready adapter with no strap keeps the put-it-on advice', () {
      final d = bleConnectFailureDisclosure(l10n, null);
      expect(d.message, l10n.runHrStrapNotFound);
      expect(d.actionLabel, l10n.runReconnect);
      expect(d.opensAppSettings, isFalse);
    });

    test('a revoked grant offers Settings, never a Reconnect that cannot work',
        () {
      final d = bleConnectFailureDisclosure(l10n, BleReadiness.unauthorized);
      expect(d.message, l10n.bleUnavailableDenied);
      expect(d.actionLabel, l10n.bleOpenSettings);
      expect(d.opensAppSettings, isTrue);
    });

    test('a powered-off radio is retryable, and is not sent to Settings', () {
      final d = bleConnectFailureDisclosure(l10n, BleReadiness.poweredOff);
      expect(d.message, l10n.bleUnavailableOff);
      expect(d.actionLabel, l10n.runReconnect);
      expect(d.opensAppSettings, isFalse);
    });

    test('a phone with no BLE radio gets no button at all', () {
      final d = bleConnectFailureDisclosure(l10n, BleReadiness.unsupported);
      expect(d.message, l10n.bleUnavailableUnsupported);
      expect(d.actionLabel, isNull);
      expect(d.opensAppSettings, isFalse);
    });

    test('every reason produces a message, and never the wrong advice', () {
      for (final r in BleReadiness.values) {
        final d = bleConnectFailureDisclosure(l10n, r);
        expect(d.message.trim(), isNotEmpty, reason: '$r');
        if (r != BleReadiness.ready) {
          // Only a ready adapter may tell the runner the strap is missing.
          expect(d.message, isNot(l10n.runHrStrapNotFound), reason: '$r');
        }
        expect(d.opensAppSettings, bleReadinessNeedsAppSettings(r),
            reason: '$r');
      }
    });
  });
}

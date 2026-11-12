import 'package:flutter/foundation.dart';

import 'ble_heart_rate.dart';
import 'l10n/gen/app_localizations.dart';

/// What a [BleReadiness] says to the runner, and whether the OS Settings app
/// is the remedy.
///
/// Both the strap-pairing sheet and the run screen's mid-run disclosure key
/// off the same verdict, so the sentence lives once. Split out of
/// `ble_heart_rate.dart` to keep the transport clear of the widget layer, the
/// same way `race_provider_labels.dart` is split from `race_service.dart`.
///
/// [BleReadiness.ready] has no copy — a ready adapter is disclosed by the
/// scan results, not by a sentence — so this returns null for it and the
/// caller renders nothing.
String? bleReadinessMessage(AppLocalizations l10n, BleReadiness readiness) =>
    switch (readiness) {
      BleReadiness.ready => null,
      BleReadiness.initialising => l10n.bleUnavailableUnknown,
      BleReadiness.poweredOff => l10n.bleUnavailableOff,
      BleReadiness.unauthorized => l10n.bleUnavailableDenied,
      BleReadiness.unsupported => l10n.bleUnavailableUnsupported,
      BleReadiness.locationServicesDisabled => l10n.bleUnavailableLocationOff,
    };

/// What a [BleHrStatus.connectFailed] should say and offer.
///
/// Three different problems arrive at that one status — the strap is off or
/// out of range, the radio is off, or the Bluetooth grant was revoked — and
/// the existing "put it on, then reconnect" is wrong for two of them. On iOS
/// a revoked grant cannot be re-prompted at all, so offering "Reconnect"
/// there is a control that can never succeed.
///
/// Pure so the choice is testable: the run screen only has to render it.
@immutable
class BleFailureDisclosure {
  final String message;

  /// Null when nothing the runner could press would help — a phone with no
  /// Bluetooth LE radio is not going to grow one.
  final String? actionLabel;

  /// True when [actionLabel] should open the app's OS settings page rather
  /// than retry the connect.
  final bool opensAppSettings;

  const BleFailureDisclosure({
    required this.message,
    required this.actionLabel,
    required this.opensAppSettings,
  });
}

BleFailureDisclosure bleConnectFailureDisclosure(
  AppLocalizations l10n,
  BleReadiness? reason,
) {
  final adapterMessage =
      reason == null ? null : bleReadinessMessage(l10n, reason);
  if (adapterMessage == null) {
    // The adapter was ready and the strap simply wasn't there.
    return BleFailureDisclosure(
      message: l10n.runHrStrapNotFound,
      actionLabel: l10n.runReconnect,
      opensAppSettings: false,
    );
  }
  if (reason == BleReadiness.unsupported) {
    return BleFailureDisclosure(
      message: adapterMessage,
      actionLabel: null,
      opensAppSettings: false,
    );
  }
  final needsSettings = bleReadinessNeedsAppSettings(reason!);
  return BleFailureDisclosure(
    message: adapterMessage,
    actionLabel: needsSettings ? l10n.bleOpenSettings : l10n.runReconnect,
    opensAppSettings: needsSettings,
  );
}

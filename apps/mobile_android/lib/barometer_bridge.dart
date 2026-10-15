import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// The phone barometer's altitude over `run_app/barometer`, metres on the
/// sensor's own datum: Android's pressure sensor through
/// `BarometerBridge.kt`, iOS `CMAltimeter` relative altitude through
/// `BarometerBridge` in `AppDelegate.swift`. Only the shape is meaningful;
/// `RunRecorder.setBarometricAltitude` levels it against GPS altitude.
///
/// A phone with no barometer, or a denied Motion & Fitness permission on iOS,
/// arrives as a stream error. The caller treats that as "no barometer" and
/// the run's climb falls back to GPS altitude.
const _channel = EventChannel('run_app/barometer');

/// Empty off Android and iOS, where no bridge answers the channel.
Stream<double> barometricAltitudes() => Platform.isAndroid || Platform.isIOS
    ? _channel
          .receiveBroadcastStream()
          .map(barometricAltitudeFromEvent)
          .where((v) => v != null)
          .cast<double>()
    : const Stream.empty();

/// One event from the bridge as metres, or null when it carries no finite
/// altitude.
double? barometricAltitudeFromEvent(Object? event) {
  if (event is! Map) return null;
  final v = event['altitudeM'];
  if (v is! num) return null;
  final m = v.toDouble();
  return m.isFinite ? m : null;
}

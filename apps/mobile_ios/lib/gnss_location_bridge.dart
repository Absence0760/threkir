import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:run_recorder/run_recorder.dart' show GnssStatusSample;

/// The satellite receiver's own fixes on Android (`GnssLocationBridge.kt`
/// over `run_app/gnss_location`), handed to `RunRecorder(gnssPositions:)`.
/// Null on iOS, where CoreLocation is the only stream.
Stream<Position> Function(Duration interval)? gnssPositionsForPlatform() =>
    Platform.isAndroid ? gnssPositions : null;

const _channel = EventChannel('run_app/gnss_location');

/// Opens the receiver at [interval]. A missing permission or a phone without
/// an enabled `GPS_PROVIDER` arrives as a stream error, which the recorder
/// treats as "no receiver" and records on the fused stream instead.
Stream<Position> gnssPositions(Duration interval) => _channel
    .receiveBroadcastStream(interval.inMilliseconds)
    .map((e) => positionFromGnssEvent(Map<Object?, Object?>.from(e as Map)));

/// One event from the bridge as a [Position]. A reading the receiver didn't
/// report is NaN (speed, heading) or 0 (accuracies), which is how the
/// recorder's fix-quality check already reads "not measured".
Position positionFromGnssEvent(Map<Object?, Object?> e) {
  double? num_(String k) => (e[k] as num?)?.toDouble();
  return Position(
    latitude: num_('lat')!,
    longitude: num_('lng')!,
    timestamp: DateTime.fromMillisecondsSinceEpoch(
      (e['timeMs'] as num).toInt(),
      isUtc: true,
    ),
    accuracy: num_('accuracy') ?? 0,
    altitude: num_('altitude') ?? 0,
    altitudeAccuracy: num_('altitudeAccuracy') ?? 0,
    heading: num_('bearing') ?? double.nan,
    headingAccuracy: num_('bearingAccuracy') ?? 0,
    speed: num_('speed') ?? double.nan,
    speedAccuracy: num_('speedAccuracy') ?? 0,
    isMocked: e['mocked'] == true,
  );
}

/// The receiver's satellite status on Android (`GnssLocationBridge.kt` over
/// `run_app/gnss_status`), handed to `RunRecorder(gnssStatus:)`. Null on iOS,
/// which exposes no satellite status.
Stream<GnssStatusSample> Function()? gnssStatusForPlatform() =>
    Platform.isAndroid ? gnssStatusSamples : null;

const _statusChannel = EventChannel('run_app/gnss_status');

Stream<GnssStatusSample> gnssStatusSamples() => _statusChannel
    .receiveBroadcastStream()
    .map((e) => gnssStatusSampleFromEvent(Map<Object?, Object?>.from(e as Map)));

/// One status event: the C/N0 and carrier frequency of each satellite the
/// receiver used in its fix, in matching order.
GnssStatusSample gnssStatusSampleFromEvent(Map<Object?, Object?> e) {
  List<double> list(String k) => [
        for (final v in (e[k] as List?) ?? const []) (v as num).toDouble(),
      ];
  return GnssStatusSample.fromUsedSatellites(list('cn0DbHz'), list('carrierHz'));
}

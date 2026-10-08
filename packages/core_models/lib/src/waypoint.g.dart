// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'waypoint.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Waypoint _$WaypointFromJson(Map<String, dynamic> json) => Waypoint(
  lat: (json['lat'] as num).toDouble(),
  lng: (json['lng'] as num).toDouble(),
  elevationMetres: (json['elevationMetres'] as num?)?.toDouble(),
  timestamp: json['timestamp'] == null
      ? null
      : DateTime.parse(json['timestamp'] as String),
  bpm: (json['bpm'] as num?)?.toInt(),
  accuracyMetres: (json['accuracyMetres'] as num?)?.toDouble(),
  speedMps: (json['speedMps'] as num?)?.toDouble(),
  speedAccuracyMps: (json['speedAccuracyMps'] as num?)?.toDouble(),
  bearingDeg: (json['bearingDeg'] as num?)?.toDouble(),
);

Map<String, dynamic> _$WaypointToJson(Waypoint instance) => <String, dynamic>{
  'lat': instance.lat,
  'lng': instance.lng,
  'elevationMetres': instance.elevationMetres,
  'timestamp': instance.timestamp?.toIso8601String(),
  'bpm': instance.bpm,
  'accuracyMetres': ?instance.accuracyMetres,
  'speedMps': ?instance.speedMps,
  'speedAccuracyMps': ?instance.speedAccuracyMps,
  'bearingDeg': ?instance.bearingDeg,
};

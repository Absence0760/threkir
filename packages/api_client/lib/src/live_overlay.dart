import 'package:core_models/core_models.dart';

/// The caller's streamer overlay (decisions § 2265): the token an OBS browser
/// source reads through, and what the server lets that token see.
class LiveOverlay {
  final String token;
  final int delaySeconds;
  final bool showMap;
  final bool showHeartRate;
  final DateTime? createdAt;

  /// Whether the owner's health-data consent is on. Heart rate is health
  /// data: the server serves it to the overlay only while this holds, and a
  /// client offers the switch only then (or to turn it off).
  final bool heartRateConsent;

  const LiveOverlay({
    required this.token,
    required this.delaySeconds,
    required this.showMap,
    required this.showHeartRate,
    this.createdAt,
    this.heartRateConsent = false,
  });

  /// One `get_live_overlay()` row. A missing setting reads as the server's
  /// own default, so a partial row never shows more than was chosen.
  factory LiveOverlay.fromRow(Map<String, dynamic> row) {
    final delay = row['delay_s'];
    final created = row['created_at'];
    return LiveOverlay(
      token: row['token'] as String,
      delaySeconds: delay is num ? delay.toInt() : 60,
      showMap: row['show_map'] == true,
      showHeartRate: row['show_heart_rate'] == true,
      createdAt: parseIsoStrictValue(created),
      heartRateConsent: row['heart_rate_consent'] == true,
    );
  }

  LiveOverlay copyWith({
    String? token,
    int? delaySeconds,
    bool? showMap,
    bool? showHeartRate,
  }) =>
      LiveOverlay(
        token: token ?? this.token,
        delaySeconds: delaySeconds ?? this.delaySeconds,
        showMap: showMap ?? this.showMap,
        showHeartRate: showHeartRate ?? this.showHeartRate,
        createdAt: createdAt,
        heartRateConsent: heartRateConsent,
      );
}

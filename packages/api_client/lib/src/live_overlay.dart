import 'package:core_models/core_models.dart';

/// The caller's streamer overlay (decisions § 2265): the token an OBS browser
/// source reads through, and what the server lets that token see.
class LiveOverlay {
  final String token;
  final int delaySeconds;
  final bool showMap;
  final bool showHeartRate;
  final DateTime? createdAt;

  const LiveOverlay({
    required this.token,
    required this.delaySeconds,
    required this.showMap,
    required this.showHeartRate,
    this.createdAt,
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
    );
  }

  LiveOverlay copyWith({String? token, int? delaySeconds}) => LiveOverlay(
        token: token ?? this.token,
        delaySeconds: delaySeconds ?? this.delaySeconds,
        showMap: showMap,
        showHeartRate: showHeartRate,
        createdAt: createdAt,
      );
}

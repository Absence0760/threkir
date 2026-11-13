// The streamer overlay (migration 20271104000001, decisions § 2265): an OBS
// browser source at `/live/overlay#<token>` that reads a server-delayed feed
// of the owner's current live run. The token rides in the URL FRAGMENT, so it
// never reaches a server log or a Referer.

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' show DistanceUnit;

/// The delays the sheet offers, in seconds. The server accepts 0-900.
const streamerOverlayDelayPresets = <int>[0, 30, 60, 120, 300, 600];

/// The overlay's URL. `units` is a display hint the web page reads from the
/// query, and `map=1` asks it to draw the trace; everything the token may
/// see is decided by the server, which sends no positions unless the trace
/// is switched on (so the link changes when it is).
String streamerOverlayUrl(String webBase, String token,
    {DistanceUnit? unit, bool showMap = false}) {
  final base = webBase.replaceAll(RegExp(r'/+$'), '');
  final params = [
    if (unit != null) 'units=${unit.name}',
    if (showMap) 'map=1',
  ];
  final query = params.isEmpty ? '' : '?${params.join('&')}';
  return '$base/live/overlay$query#${Uri.encodeComponent(token)}';
}

/// Whether a create / configure failure is the server's closed gate
/// (`live_overlay_disabled`), which reads differently from a network error.
bool isLiveOverlayDisabledError(Object error) =>
    error.toString().contains('live_overlay_disabled');

/// What the sheet needs from the backend; a fake stands in for it in tests.
abstract class StreamerOverlayController {
  Future<LiveOverlay?> load();
  Future<String> create();
  Future<void> revoke();

  /// Saves the settings given and returns those now on the server, or null
  /// when the overlay no longer exists.
  Future<LiveOverlay?> save({
    int? delaySeconds,
    bool? showMap,
    bool? showHeartRate,
  });
}

class ApiStreamerOverlayController implements StreamerOverlayController {
  final ApiClient api;
  const ApiStreamerOverlayController(this.api);

  @override
  Future<LiveOverlay?> load() => api.fetchLiveOverlay();

  @override
  Future<String> create() => api.createLiveOverlayToken();

  @override
  Future<void> revoke() => api.revokeLiveOverlayToken();

  /// `update_live_overlay_settings` writes all three settings, so the ones
  /// not being changed are read back from the server first: the copy the
  /// sheet loaded may predate a change made on the web. Mirrors web's
  /// `saveLiveOverlaySettings`.
  @override
  Future<LiveOverlay?> save({
    int? delaySeconds,
    bool? showMap,
    bool? showHeartRate,
  }) async {
    final latest = await api.fetchLiveOverlay();
    if (latest == null) return null;
    final next = latest.copyWith(
      delaySeconds: delaySeconds,
      showMap: showMap,
      showHeartRate: showHeartRate,
    );
    await api.updateLiveOverlaySettings(
      delaySeconds: next.delaySeconds,
      showMap: next.showMap,
      showHeartRate: next.showHeartRate,
    );
    return next;
  }
}

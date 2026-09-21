import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, visibleForTesting;
import 'package:flutter/services.dart';

/// Pushes the two preferences the Apple Watch app READS and has no way to
/// set: the distance unit its read-outs and spoken splits use
/// (`preferred_unit`), and whether those spoken cues are audible at all
/// (`audio_cues`).
///
/// The watch keeps no Supabase surface of its own (`apps/watch_ios/CLAUDE.md`),
/// so a setting reaches the wrist from the phone or not at all. It had been
/// reading `preferred_unit` out of `UserDefaults` since it shipped with
/// nothing on the phone ever writing it, and the spoken cues arrived with the
/// same gap — which made them unsilenceable from any surface the runner
/// owns.
///
/// The native half is `WatchIngestBridge.swift` in `apps/mobile_ios/ios/Runner`
/// (the same class that ingests finished watch runs and arms routes —
/// `WCSession.delegate` is a single slot). It writes the payload into the
/// session's APPLICATION CONTEXT: one latest-value slot, overwritten on every
/// change, re-offered to the watch on its next contact and readable by the
/// watch on a cold launch. A preference is state, not an event, so replaying
/// six intermediate values out of a durable queue would be wrong and dropping
/// them against an unreachable watch — which is what a `sendMessage` does —
/// is what left the wrist stale.
///
/// iOS-only, so [push] falls closed on any other target platform (decisions
/// §39 — one Dart codebase, platform dispatch inside it). The dispatch reads
/// `defaultTargetPlatform` rather than `Platform.isIOS` so host-run widget
/// tests can drive the iOS branch, matching `apple_watch_route_bridge.dart`.
class AppleWatchPrefsBridge {
  @visibleForTesting
  static const String channelName = 'run_app/watch_prefs';

  static const _channel = MethodChannel(channelName);

  /// Distance-unit values the watch's decoder accepts. Anything else is
  /// refused on both sides rather than coerced — the watch falls back to the
  /// unit it already holds, which is a stale answer, where a coerced one
  /// would be a wrong answer it then keeps forever (the application context
  /// is retained and re-offered on every contact).
  @visibleForTesting
  static const Set<String> acceptedUnits = {'km', 'mi'};

  /// Queue [preferredUnit] and [audioCues] as the watch's current settings.
  ///
  /// Never throws. This is an L4 auxiliary effect by the layering contract
  /// (`docs/features/run_recording.md` § Layering) — a preference that did
  /// not reach the wrist must not fail the preference write on the phone, let
  /// alone anything recording. Returns whether the push was accepted, and
  /// logs every refusal rather than swallowing it: a cue the runner switched
  /// off that keeps speaking is the failure this exists to prevent, so it has
  /// to leave a trace.
  ///
  /// `false` does NOT mean the watch is unaware — a push accepted here is
  /// delivered whenever the two devices next meet, which may be days later.
  /// It means this phone could not hand the value to WCSession at all.
  static Future<bool> push({
    required String preferredUnit,
    required bool audioCues,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return false;
    if (!acceptedUnits.contains(preferredUnit)) {
      debugPrint('Apple Watch prefs push: refusing unit "$preferredUnit"');
      return false;
    }
    try {
      await _channel.invokeMethod<void>('push', {
        'preferred_unit': preferredUnit,
        'audio_cues': audioCues,
      });
      return true;
    } on MissingPluginException {
      // No native half registered — a non-iOS build, or a test host.
      return false;
    } on PlatformException catch (e) {
      debugPrint('Apple Watch prefs push refused: ${e.code} ${e.message}');
      return false;
    }
  }
}

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, visibleForTesting;
import 'package:flutter/services.dart';

import 'hr_zones.dart';
import 'run_intensity.dart' show parseHrZones;

/// Pushes the preferences the Apple Watch app READS and has no way to set:
/// the distance unit its read-outs and spoken splits use (`preferred_unit`),
/// whether those spoken cues are audible at all (`audio_cues`), the activity
/// its pre-run picker opens on (`default_activity_type`), the visibility a
/// run recorded on it is saved with (`privacy_default`), and the heart-rate
/// zone ladder its live `Z3` badge reads (`hr_zone_cutoffs`).
///
/// The ladder is resolved HERE, from `hr_zones` > `max_hr_bpm` > Tanaka off
/// `date_of_birth`, rather than shipping the three inputs to the wrist. The
/// watch needs five numbers, not a date of birth: the bag's DOB is the Art 9
/// health-use mirror, and a copy of it on a second device buys nothing the
/// ladder does not already carry. It also keeps the derivation in one Dart
/// place instead of growing a fourth rail beside web, Dart and Wear OS
/// (decisions § 1245).
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

  /// The four activities the watch's pre-run picker cycles. The column admits
  /// a fifth, `stroller`, which neither wrist offers; a phone default of it is
  /// left off the push rather than refusing the push, so the wrist keeps the
  /// activity it already opens on.
  @visibleForTesting
  static const Set<String> acceptedActivityTypes = {'run', 'walk', 'hike', 'cycle'};

  @visibleForTesting
  static const Set<String> acceptedPrivacyDefaults = {'public', 'followers', 'private'};

  /// The per-bound range the watch's zone decoder accepts, Wear OS's
  /// `parseHrZones` gate.
  @visibleForTesting
  static const int zoneBoundMin = 40;
  @visibleForTesting
  static const int zoneBoundMax = 240;

  /// The zone upper bounds (Z1..Z5) the wrist should badge a live reading
  /// against, or an EMPTY list when none of the three signals is usable.
  ///
  /// Empty rather than the legacy 190 ladder web and the phone end on: a
  /// stranger's zones on the wrist, mid-run, are worse than no badge. That is
  /// the watch-tier rule Wear OS's `resolveZoneCutoffs` already follows
  /// (decisions § 1245), and empty is also how a runner who removed their
  /// zones clears them from a watch that still holds the old ones.
  static List<int> zoneCutoffsForWatch({
    Object? hrZones,
    Object? maxHrBpm,
    Object? dateOfBirth,
    required DateTime now,
  }) {
    final explicit = parseHrZones(hrZones);
    if (explicit != null && explicit.every(_inZoneRange)) return explicit;
    final maxHr = maxHrBpm is num ? maxHrBpm.round() : null;
    if (isUsableMaxHrBpm(maxHr)) return zoneCutoffsFromMaxHr(maxHr!);
    final age = _ageYears(dateOfBirth, now);
    if (age != null && age >= kTanakaAgeMin && age <= kTanakaAgeMax) {
      return zoneCutoffsFromMaxHr(tanakaMaxHr(age));
    }
    return const [];
  }

  static bool _inZoneRange(int v) => v >= zoneBoundMin && v <= zoneBoundMax;

  static int? _ageYears(Object? dob, DateTime now) {
    if (dob is! String) return null;
    final born = DateTime.tryParse(dob);
    if (born == null) return null;
    var age = now.year - born.year;
    if (now.month < born.month || (now.month == born.month && now.day < born.day)) {
      age--;
    }
    return age;
  }

  /// Whether [cutoffs] is a ladder the watch will apply: empty (clear), or
  /// five strictly-ascending bounds inside the decoder's range.
  @visibleForTesting
  static bool isWatchZoneLadder(List<int> cutoffs) {
    if (cutoffs.isEmpty) return true;
    if (cutoffs.length != 5 || !cutoffs.every(_inZoneRange)) return false;
    for (var i = 1; i < cutoffs.length; i++) {
      if (cutoffs[i] <= cutoffs[i - 1]) return false;
    }
    return true;
  }

  /// Queue the watch's current settings.
  ///
  /// [preferredUnit] and [audioCues] are required and a bad unit refuses the
  /// whole push, as before. The other three are optional and independent: a
  /// null, or a value the watch would drop, leaves that key off the push, and
  /// the watch reads an absent key as "keep what you have". [hrZoneCutoffs]
  /// is null until the settings bag has been read this launch, so a push made
  /// before then cannot clear zones the wrist still legitimately holds.
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
    String? defaultActivityType,
    String? privacyDefault,
    List<int>? hrZoneCutoffs,
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
        if (defaultActivityType != null &&
            acceptedActivityTypes.contains(defaultActivityType))
          'default_activity_type': defaultActivityType,
        if (privacyDefault != null && acceptedPrivacyDefaults.contains(privacyDefault))
          'privacy_default': privacyDefault,
        if (hrZoneCutoffs != null && isWatchZoneLadder(hrZoneCutoffs))
          'hr_zone_cutoffs': hrZoneCutoffs,
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

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/apple_watch_prefs_bridge.dart';
import '../lib/hr_zones.dart';

/// Records what the bridge sends over the `run_app/watch_prefs` channel and
/// can play the native side's refusals back at it.
class _MockChannel {
  static const _channel = MethodChannel(AppleWatchPrefsBridge.channelName);

  final List<MethodCall> calls = [];
  Object? throwOnPush;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, _handle);
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }

  Future<dynamic> _handle(MethodCall call) async {
    calls.add(call);
    if (call.method == 'push' && throwOnPush != null) throw throwOnPush!;
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockChannel channel;

  setUp(() {
    channel = _MockChannel()..install();
  });

  tearDown(() {
    channel.uninstall();
    debugDefaultTargetPlatformOverride = null;
  });

  test('sends both keys, spelled as the watch reads them', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(
      await AppleWatchPrefsBridge.push(preferredUnit: 'mi', audioCues: false),
      isTrue,
    );
    expect(channel.calls, hasLength(1));
    expect(channel.calls.single.method, 'push');
    // The wire names. `preferred_unit` is what `RunFormat.prefersMiles` reads
    // out of UserDefaults on the wrist and `audio_cues` is
    // `RunAnnouncer.preferenceKey`; a rename on either side is a preference
    // the runner sets that the watch never sees, with no error anywhere.
    expect(
      channel.calls.single.arguments,
      {'preferred_unit': 'mi', 'audio_cues': false},
    );
  });

  test('carries cues-on as faithfully as cues-off', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await AppleWatchPrefsBridge.push(preferredUnit: 'km', audioCues: true);
    expect(
      channel.calls.single.arguments,
      {'preferred_unit': 'km', 'audio_cues': true},
    );
  });

  test('is a no-op off iOS — there is no Apple Watch to push to', () async {
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(
        await AppleWatchPrefsBridge.push(preferredUnit: 'km', audioCues: true),
        isFalse,
      );
    }
    expect(channel.calls, isEmpty);
  });

  test('refuses a unit the watch decoder would drop, before sending it',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    for (final unit in ['', 'KM', 'miles', 'k m']) {
      expect(
        await AppleWatchPrefsBridge.push(preferredUnit: unit, audioCues: true),
        isFalse,
        reason: '"$unit" is not one the watch accepts',
      );
    }
    // Nothing reached the channel. The application context is RETAINED and
    // re-offered on every contact, so a value the watch refuses is refused
    // forever rather than once.
    expect(channel.calls, isEmpty);
  });

  test('accepts exactly the two units the watch decoder accepts', () {
    expect(AppleWatchPrefsBridge.acceptedUnits, {'km', 'mi'});
  });

  test('reports a native refusal rather than throwing it at the caller',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    channel.throwOnPush = PlatformException(code: 'watch_unavailable');
    expect(
      await AppleWatchPrefsBridge.push(preferredUnit: 'km', audioCues: false),
      isFalse,
    );
  });

  test('a missing native half is not an error', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    channel.throwOnPush = MissingPluginException();
    expect(
      await AppleWatchPrefsBridge.push(preferredUnit: 'km', audioCues: false),
      isFalse,
    );
  });

  test('carries the three settings the wrist applies, spelled as it reads them',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await AppleWatchPrefsBridge.push(
      preferredUnit: 'km',
      audioCues: true,
      defaultActivityType: 'hike',
      privacyDefault: 'public',
      hrZoneCutoffs: const [114, 133, 152, 171, 190],
    );
    expect(channel.calls.single.arguments, {
      'preferred_unit': 'km',
      'audio_cues': true,
      'default_activity_type': 'hike',
      'privacy_default': 'public',
      'hr_zone_cutoffs': [114, 133, 152, 171, 190],
    });
  });

  test('an empty ladder is sent — it is how zones are cleared', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await AppleWatchPrefsBridge.push(
      preferredUnit: 'km',
      audioCues: true,
      hrZoneCutoffs: const [],
    );
    expect(
      (channel.calls.single.arguments as Map)['hr_zone_cutoffs'],
      isEmpty,
    );
  });

  test('an optional value the wrist would drop is left off, not the push',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(
      await AppleWatchPrefsBridge.push(
        preferredUnit: 'mi',
        audioCues: false,
        // `stroller` is a column value no wrist picker offers.
        defaultActivityType: 'stroller',
        privacyDefault: 'everyone',
        hrZoneCutoffs: const [150, 140, 130, 120, 110],
      ),
      isTrue,
      reason: 'the unit and the cue switch still have to reach the wrist',
    );
    expect(
      channel.calls.single.arguments,
      {'preferred_unit': 'mi', 'audio_cues': false},
    );
  });

  test('a null optional says nothing, so the wrist keeps what it has',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await AppleWatchPrefsBridge.push(preferredUnit: 'km', audioCues: true);
    final args = channel.calls.single.arguments as Map;
    expect(args.containsKey('hr_zone_cutoffs'), isFalse);
    expect(args.containsKey('default_activity_type'), isFalse);
    expect(args.containsKey('privacy_default'), isFalse);
  });

  test('accepts the activity and privacy vocabularies the watch decodes', () {
    expect(AppleWatchPrefsBridge.acceptedActivityTypes, {'run', 'walk', 'hike', 'cycle'});
    expect(AppleWatchPrefsBridge.acceptedPrivacyDefaults, {'public', 'followers', 'private'});
  });

  group('zoneCutoffsForWatch', () {
    final now = DateTime(2026, 9, 23);

    test('explicit hr_zones win over every other signal', () {
      expect(
        AppleWatchPrefsBridge.zoneCutoffsForWatch(
          hrZones: {'z1': 110, 'z2': 130, 'z3': 150, 'z4': 165, 'z5': 185},
          maxHrBpm: 200,
          dateOfBirth: '1980-01-01',
          now: now,
        ),
        [110, 130, 150, 165, 185],
      );
    });

    test('malformed or out-of-range hr_zones fall through to max HR', () {
      for (final bad in [
        {'z1': 150, 'z2': 140, 'z3': 130, 'z4': 120, 'z5': 110},
        {'z1': 30, 'z2': 130, 'z3': 150, 'z4': 165, 'z5': 185},
        {'z1': 110, 'z2': 130, 'z3': 150, 'z4': 165, 'z5': 250},
        {'z1': 110, 'z2': 130},
        'not a map',
      ]) {
        expect(
          AppleWatchPrefsBridge.zoneCutoffsForWatch(hrZones: bad, maxHrBpm: 200, now: now),
          [120, 140, 160, 180, 200],
          reason: '$bad',
        );
      }
    });

    test('a usable max HR is the 60/70/80/90/100 % ladder', () {
      expect(
        AppleWatchPrefsBridge.zoneCutoffsForWatch(maxHrBpm: 185, now: now),
        zoneCutoffsFromMaxHr(185),
      );
      // The shared 80..240 range: a beta-blocked 95 is honoured (§ 1303).
      expect(
        AppleWatchPrefsBridge.zoneCutoffsForWatch(maxHrBpm: 95, now: now),
        zoneCutoffsFromMaxHr(95),
      );
    });

    test('an out-of-range max HR falls through to Tanaka from the DOB', () {
      // 46 on 2026-09-23 -> 208 - 0.7 * 46 = 175.8 -> 176.
      expect(
        AppleWatchPrefsBridge.zoneCutoffsForWatch(
          maxHrBpm: 300,
          dateOfBirth: '1980-01-01',
          now: now,
        ),
        zoneCutoffsFromMaxHr(176),
      );
    });

    test('age is whole years, counted to the birthday', () {
      // Born 1980-09-24: still 45 on the 23rd -> 208 - 31.5 = 176.5 -> 177.
      expect(
        AppleWatchPrefsBridge.zoneCutoffsForWatch(dateOfBirth: '1980-09-24', now: now),
        zoneCutoffsFromMaxHr(177),
      );
      expect(
        AppleWatchPrefsBridge.zoneCutoffsForWatch(dateOfBirth: '1980-09-23', now: now),
        zoneCutoffsFromMaxHr(176),
      );
    });

    test('no usable signal is EMPTY, never the legacy 190 ladder', () {
      expect(AppleWatchPrefsBridge.zoneCutoffsForWatch(now: now), isEmpty);
      expect(
        AppleWatchPrefsBridge.zoneCutoffsForWatch(
          maxHrBpm: 0,
          dateOfBirth: 'garbage',
          now: now,
        ),
        isEmpty,
      );
      // An age outside Tanaka's range is no signal either.
      expect(
        AppleWatchPrefsBridge.zoneCutoffsForWatch(dateOfBirth: '2024-01-01', now: now),
        isEmpty,
      );
    });

    test('every ladder it can produce is one the push will send', () {
      for (final maxHr in [80, 95, 150, 190, 240]) {
        expect(
          AppleWatchPrefsBridge.isWatchZoneLadder(
            AppleWatchPrefsBridge.zoneCutoffsForWatch(maxHrBpm: maxHr, now: now),
          ),
          isTrue,
          reason: 'max HR $maxHr',
        );
      }
    });
  });
}

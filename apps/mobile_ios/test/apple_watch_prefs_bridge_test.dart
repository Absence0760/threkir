import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/apple_watch_prefs_bridge.dart';

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
}

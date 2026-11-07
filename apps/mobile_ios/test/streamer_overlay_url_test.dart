import 'package:core_models/core_models.dart' show DistanceUnit;
import 'package:flutter_test/flutter_test.dart';

import '../lib/streamer_overlay.dart';

// The overlay's token must ride in the URL fragment so it never reaches a
// server log or a Referer (decisions § 2265).
void main() {
  test('the token is in the fragment, never the path or query', () {
    final url = streamerOverlayUrl('https://threkir.com', 'tok123');
    expect(url, 'https://threkir.com/live/overlay#tok123');
    final uri = Uri.parse(url);
    expect(uri.fragment, 'tok123');
    expect(uri.path, isNot(contains('tok123')));
    expect(uri.query, isNot(contains('tok123')));
  });

  test('the unit is a query hint, placed before the fragment', () {
    expect(streamerOverlayUrl('https://threkir.com', 't', unit: DistanceUnit.mi),
        'https://threkir.com/live/overlay?units=mi#t');
    expect(streamerOverlayUrl('https://threkir.com', 't', unit: DistanceUnit.km),
        'https://threkir.com/live/overlay?units=km#t');
  });

  test('trailing slashes on the base are dropped, never doubled', () {
    expect(streamerOverlayUrl('https://threkir.com/', 't'),
        'https://threkir.com/live/overlay#t');
    expect(streamerOverlayUrl('https://threkir.com///', 't'),
        'https://threkir.com/live/overlay#t');
  });

  test('a token with reserved characters is encoded, so it cannot end the fragment early',
      () {
    final url = streamerOverlayUrl('https://threkir.com', 'a b/c?d#e&f');
    expect(url, 'https://threkir.com/live/overlay#a%20b%2Fc%3Fd%23e%26f');
    expect(Uri.decodeComponent(Uri.parse(url).fragment), 'a b/c?d#e&f');
  });

  test('the delay presets are ascending, start live, and fit the server range',
      () {
    expect(streamerOverlayDelayPresets.first, 0);
    for (var i = 1; i < streamerOverlayDelayPresets.length; i++) {
      expect(streamerOverlayDelayPresets[i],
          greaterThan(streamerOverlayDelayPresets[i - 1]));
    }
    expect(streamerOverlayDelayPresets.every((s) => s >= 0 && s <= 900), isTrue,
        reason: 'the server accepts 0-900 s');
  });

  test('only the server\'s closed gate reads as disabled', () {
    expect(isLiveOverlayDisabledError(Exception('P0001: live_overlay_disabled')),
        isTrue);
    expect(isLiveOverlayDisabledError(Exception('SocketException: down')), isFalse);
    expect(isLiveOverlayDisabledError('live_overlay_disabled'), isTrue);
  });
}

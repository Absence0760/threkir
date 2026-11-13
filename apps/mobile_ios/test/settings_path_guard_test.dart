// No string gives directions into the app's own settings (issue #1374).
// Preferences became five pages and You became an account hub (decisions
// § 2494), so prose such as "Settings → Gear" or "Preferences → Training"
// named places a runner could no longer find. A string says what is wrong and
// a button beside it opens the page (`openSettings(SettingsDestination.x)`),
// so the way there cannot drift from the screens again. The web twin is
// apps/web/src/lib/i18n/settings_path_guard.test.ts.
//
// The exemptions below give directions into somewhere other than this app's
// settings. The map may only shrink: an entry whose key is gone or whose
// string no longer gives a path fails, so a fixed string cannot stay listed.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _exempt = {
  'importStravaHowToSteps':
      'steps inside the Strava app, whose own Settings this is',
  'onboardingLocationBodyIos':
      'the iOS Settings app, which is the only place location access changes',
  'proSubscribeSubtitleConfigured':
      'the store\'s subscription settings, where an auto-renewal is cancelled',
  'proSubscribeSubtitleConfiguredAnnual':
      'the store\'s subscription settings, where an auto-renewal is cancelled',
};

/// "Settings → Gear", "Preferences › Training", "You > Settings": a named
/// place followed by an arrow or chevron is a path.
final _path = RegExp(r'\b(Settings|Preferences|You)\s*(→|›|»|>)\s*\S');

Map<String, String> _english() {
  final raw = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
      as Map<String, dynamic>;
  return {
    for (final e in raw.entries)
      if (!e.key.startsWith('@') && e.value is String)
        e.key: e.value as String,
  };
}

void main() {
  final en = _english();

  test('the pattern catches a path and leaves ordinary prose alone', () {
    expect(_path.hasMatch('Add some in Settings → Gear.'), isTrue);
    expect(_path.hasMatch('create one later from You › Settings.'), isTrue);
    expect(_path.hasMatch('in Settings > Account'), isTrue);
    expect(_path.hasMatch('You can change it any time in Settings.'), isFalse);
    expect(_path.hasMatch('Week {n} target: {from} → {to}'), isFalse);
  });

  test('no English string recites a path into Settings', () {
    final offenders = [
      for (final e in en.entries)
        if (_path.hasMatch(e.value) && !_exempt.containsKey(e.key))
          '${e.key}: ${e.value}',
    ];
    expect(offenders, isEmpty,
        reason: 'Say what is wrong and put a button beside the string that '
            'calls openSettings(SettingsDestination.x); the string itself '
            'gives no directions.');
  });

  test('every exemption is a live string that still gives a path', () {
    final stale = [
      for (final k in _exempt.keys)
        if (!en.containsKey(k) || !_path.hasMatch(en[k]!)) k,
    ];
    expect(stale, isEmpty,
        reason: 'A fixed or deleted string comes off the list, so the list '
            'only shrinks.');
  });
}

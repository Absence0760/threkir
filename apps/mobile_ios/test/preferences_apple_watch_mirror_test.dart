// The phone -> Apple Watch preference mirror, asserted at the layer that
// matters: the two `Preferences` setters every writer of these values goes
// through — the settings page, the setup wizard, the sign-out reset, and
// `SettingsSyncService` applying a value the runner set on the web.
//
// Wiring the push at any one of those call sites would leave the wrist stale
// from the others, and a stale `audio_cues` is a watch that keeps talking
// after the runner switched the cues off — the whole defect this closes.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/preferences.dart';

class _Recorder {
  final List<({String unit, bool cues})> pushes = [];
  Object? throwOnPush;

  Future<bool> push({required String preferredUnit, required bool audioCues}) async {
    if (throwOnPush != null) throw throwOnPush!;
    pushes.add((unit: preferredUnit, cues: audioCues));
    return true;
  }
}

Future<(Preferences, _Recorder)> _prefs([Map<String, Object> seed = const {}]) async {
  SharedPreferences.setMockInitialValues(seed);
  final recorder = _Recorder();
  final prefs = Preferences()..appleWatchPrefsPush = recorder.push;
  await prefs.init();
  return (prefs, recorder);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('launch seeds the wrist with both values', () async {
    final (_, recorder) = await _prefs({'use_miles': true, 'audio_cues': false});
    // A watch paired or reinstalled since the last preference change has
    // never been offered a context at all, so it would otherwise record
    // under its own defaults forever.
    expect(recorder.pushes, [(unit: 'mi', cues: false)]);
  });

  test('turning the cues off pushes the OFF, carrying the unit with it',
      () async {
    final (prefs, recorder) = await _prefs();
    recorder.pushes.clear();
    await prefs.setAudioCues(false);
    expect(recorder.pushes, [(unit: 'km', cues: false)]);
    await prefs.setAudioCues(true);
    expect(recorder.pushes.last, (unit: 'km', cues: true));
  });

  test('flipping the unit pushes it, carrying the cue state with it', () async {
    final (prefs, recorder) = await _prefs({'audio_cues': false});
    recorder.pushes.clear();
    await prefs.setUseMiles(true);
    // Both keys ride one envelope, so the push must never report a default
    // for the value that did not change.
    expect(recorder.pushes, [(unit: 'mi', cues: false)]);
    await prefs.setUseMiles(false);
    expect(recorder.pushes.last, (unit: 'km', cues: false));
  });

  test('the push is L4 — a failure cannot fail the preference write',
      () async {
    final (prefs, recorder) = await _prefs();
    recorder.throwOnPush = StateError('no session');
    await prefs.setAudioCues(false);
    expect(prefs.audioCues, isFalse, reason: 'the phone still honours it');
    await prefs.setUseMiles(true);
    expect(prefs.useMiles, isTrue);
  });

  test('the local value is written before the wrist is told', () async {
    // Ordering matters: a push handler that reads back through `Preferences`
    // must not see the pre-change value.
    final (prefs, _) = await _prefs();
    String? seen;
    prefs.appleWatchPrefsPush = ({required preferredUnit, required audioCues}) async {
      seen = prefs.audioCues ? 'on' : 'off';
      return true;
    };
    await prefs.setAudioCues(false);
    expect(seen, 'off');
  });
}

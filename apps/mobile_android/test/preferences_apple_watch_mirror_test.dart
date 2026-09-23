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

typedef _Push = ({
  String unit,
  bool cues,
  String? activity,
  String? privacy,
  List<int>? zones,
});

class _Recorder {
  final List<_Push> full = [];
  Object? throwOnPush;

  /// The two original keys only, so the cases written against them read the
  /// way they always did.
  List<({String unit, bool cues})> get pushes =>
      [for (final p in full) (unit: p.unit, cues: p.cues)];

  Future<bool> push({
    required String preferredUnit,
    required bool audioCues,
    String? defaultActivityType,
    String? privacyDefault,
    List<int>? hrZoneCutoffs,
  }) async {
    if (throwOnPush != null) throw throwOnPush!;
    full.add((
      unit: preferredUnit,
      cues: audioCues,
      activity: defaultActivityType,
      privacy: privacyDefault,
      zones: hrZoneCutoffs,
    ));
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
    recorder.full.clear();
    await prefs.setAudioCues(false);
    expect(recorder.pushes, [(unit: 'km', cues: false)]);
    await prefs.setAudioCues(true);
    expect(recorder.pushes.last, (unit: 'km', cues: true));
  });

  test('flipping the unit pushes it, carrying the cue state with it', () async {
    final (prefs, recorder) = await _prefs({'audio_cues': false});
    recorder.full.clear();
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
    prefs.appleWatchPrefsPush = ({
      required preferredUnit,
      required audioCues,
      defaultActivityType,
      privacyDefault,
      hrZoneCutoffs,
    }) async {
      seen = prefs.audioCues ? 'on' : 'off';
      return true;
    };
    await prefs.setAudioCues(false);
    expect(seen, 'off');
  });

  test('the default activity rides every push, and changing it pushes it',
      () async {
    final (prefs, recorder) = await _prefs({'default_activity_type': 'walk'});
    expect(recorder.full.single.activity, 'walk');
    recorder.full.clear();
    await prefs.setDefaultActivityType('cycle');
    expect(recorder.full, hasLength(1));
    expect(recorder.full.single.activity, 'cycle');
  });

  test('the privacy default rides every push, and changing it pushes it',
      () async {
    final (prefs, recorder) = await _prefs();
    // Unset locally is the wizard's private, never a guess at public.
    expect(recorder.full.single.privacy, 'private');
    recorder.full.clear();
    await prefs.setPrivacyDefault('public');
    expect(recorder.full.single.privacy, 'public');
    // A corrupt value normalises to private on the phone first, so the wrist
    // is told private rather than handed the typo.
    await prefs.setPrivacyDefault('everyone');
    expect(recorder.full.last.privacy, 'private');
  });

  test('zones are withheld until the bag has been read, then pushed once',
      () async {
    final (prefs, recorder) = await _prefs();
    // A launch-time push before the settings bag loads must not tell the
    // wrist "no zones" — that would clear a ladder it legitimately holds.
    expect(recorder.full.single.zones, isNull);
    recorder.full.clear();
    await prefs.setAppleWatchHrZoneCutoffs(const [114, 133, 152, 171, 190]);
    expect(recorder.full.single.zones, [114, 133, 152, 171, 190]);
    // Re-deriving the same ladder (every bag write does) costs no push.
    await prefs.setAppleWatchHrZoneCutoffs(const [114, 133, 152, 171, 190]);
    expect(recorder.full, hasLength(1));
    // And every later push carries it, whichever setter made it.
    await prefs.setAudioCues(false);
    expect(recorder.full.last.zones, [114, 133, 152, 171, 190]);
  });

  test('sign-out clears the wrist\'s zones rather than leaving the last account\'s',
      () async {
    final (prefs, recorder) = await _prefs();
    await prefs.setAppleWatchHrZoneCutoffs(const [120, 140, 155, 170, 185]);
    await prefs.setDefaultActivityType('hike');
    await prefs.setPrivacyDefault('public');
    recorder.full.clear();
    await prefs.resetAccountScopedPrefs();
    final last = recorder.full.last;
    expect(last.zones, isEmpty);
    expect(last.activity, 'run');
    expect(last.privacy, 'private');
  });
}

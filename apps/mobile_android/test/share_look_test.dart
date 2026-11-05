import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/run_share_stats.dart';
import '../lib/share_look.dart';
import '../lib/share_placement.dart';

void main() {
  group('RunShareLook.toggleStat', () {
    test('adds a stat in display order, whatever order it was picked in', () {
      const look = RunShareLook(stats: [RunShareStatKind.time]);
      expect(look.toggleStat(RunShareStatKind.distance).stats,
          [RunShareStatKind.distance, RunShareStatKind.time]);
    });

    test('removes a picked stat', () {
      expect(const RunShareLook().toggleStat(RunShareStatKind.pace).stats,
          [RunShareStatKind.distance, RunShareStatKind.time]);
    });

    test('never empties the set', () {
      const look = RunShareLook(stats: [RunShareStatKind.distance]);
      expect(look.toggleStat(RunShareStatKind.distance), look);
    });

    test('never grows past maxStats', () {
      const full = RunShareLook(stats: [
        RunShareStatKind.distance,
        RunShareStatKind.pace,
        RunShareStatKind.time,
        RunShareStatKind.climb,
      ]);
      expect(full.stats, hasLength(RunShareLook.maxStats));
      expect(full.toggleStat(RunShareStatKind.heartRate), full);
    });
  });

  group('RunShareLook json', () {
    test('round-trips every field', () {
      const look = RunShareLook(
        layout: RunStickerLayout.hero,
        ink: RunShareInk.brand,
        aspect: RunPhotoAspect.post,
        stats: [RunShareStatKind.distance, RunShareStatKind.heartRate],
        mark: false,
      );
      expect(RunShareLook.fromJson(jsonDecode(jsonEncode(look.toJson()))),
          look);
    });

    test('an unknown value takes its default and keeps the rest', () {
      final look = RunShareLook.fromJson({
        'layout': 'carousel',
        'ink': 'dark',
        'aspect': 'post',
        'stats': ['distance', 'cadence'],
      });
      expect(look.layout, const RunShareLook().layout);
      expect(look.ink, RunShareInk.dark);
      expect(look.aspect, RunPhotoAspect.post);
      expect(look.stats, [RunShareStatKind.distance]);
    });

    test('a stored set past maxStats is cut to it', () {
      final look = RunShareLook.fromJson({
        'stats': [for (final k in RunShareStatKind.values) k.name],
      });
      expect(look.stats, hasLength(RunShareLook.maxStats));
    });

    test('anything that is not an object is the default look', () {
      for (final junk in [null, 7, 'stack', <Object>[]]) {
        expect(RunShareLook.fromJson(junk), const RunShareLook(), reason: '$junk');
      }
    });

    test('the mark is on by default and only a stored boolean turns it off',
        () {
      expect(const RunShareLook().mark, isTrue);
      expect(RunShareLook.fromJson({'layout': 'strip'}).mark, isTrue);
      expect(RunShareLook.fromJson({'mark': 'no'}).mark, isTrue);
      expect(RunShareLook.fromJson({'mark': false}).mark, isFalse);
    });

    test('each aspect keeps its own placement, and only the current one moves',
        () {
      final moved = const RunShareLook(aspect: RunPhotoAspect.post)
          .withPlacement(const SharePlacement(x: 0.3, y: 0.4, scale: 0.7));
      expect(moved.placements[RunPhotoAspect.post],
          const SharePlacement(x: 0.3, y: 0.4, scale: 0.7));
      expect(moved.placements[RunPhotoAspect.story], SharePlacement.initial);
      expect(RunShareLook.fromJson(jsonDecode(jsonEncode(moved.toJson()))),
          moved);
    });

    test('a bad stored placement fails closed for its aspect and keeps the '
        'other', () {
      final look = RunShareLook.fromJson({
        'placements': {
          'story': {'x': 9, 'y': 0.5, 'scale': 1},
          'post': {'x': 0.2, 'y': 0.8, 'scale': 0.6},
        },
      });
      expect(look.placements[RunPhotoAspect.story], SharePlacement.initial);
      expect(look.placements[RunPhotoAspect.post],
          const SharePlacement(x: 0.2, y: 0.8, scale: 0.6));
      expect(RunShareLook.fromJson({'placements': 'top'}).placements,
          const RunShareLook().placements);
    });

    test('an empty or absent stat list is the default set', () {
      expect(RunShareLook.fromJson({'stats': <String>[]}).stats,
          RunShareLook.defaultStats);
      expect(RunShareLook.fromJson({'layout': 'strip'}).stats,
          RunShareLook.defaultStats);
    });
  });

  group('load / save', () {
    test('a saved look is what the next load returns', () async {
      SharedPreferences.setMockInitialValues({});
      const look = RunShareLook(
        layout: RunStickerLayout.strip,
        ink: RunShareInk.dark,
      );
      await saveShareLook(look);
      expect(await loadShareLook(), look);
    });

    test('nothing saved loads the default', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await loadShareLook(), const RunShareLook());
    });

    test('a corrupt saved value loads the default instead of throwing',
        () async {
      SharedPreferences.setMockInitialValues({shareLookPrefsKey: '{not json'});
      expect(await loadShareLook(), const RunShareLook());
    });
  });
}

import 'dart:convert';

import 'package:flutter/foundation.dart'
    show debugPrint, immutable, listEquals, mapEquals;
import 'package:shared_preferences/shared_preferences.dart';

import 'run_share_stats.dart';
import 'share_placement.dart';

/// How a stats sticker is laid out.
///
/// * [stack] — each stat on its own line, the route under them.
/// * [route] — the route large, the stats in a line beneath it.
/// * [strip] — every stat in one line, for the edge of a story.
/// * [hero] — the first stat huge, the rest small beneath it.
enum RunStickerLayout { stack, route, strip, hero }

/// The colour the sticker's type and route are drawn in: [light] for a dark
/// photo, [dark] for a bright one, [brand] for the Threkir coral.
enum RunShareInk { light, dark, brand }

/// The canvas the photo style is cut to: a 4:5 feed [post] or a 9:16 [story].
enum RunPhotoAspect { post, story }

/// The look a runner chose for their share images, kept on this device so the
/// next run shares the same way without choosing again.
@immutable
class RunShareLook {
  final RunStickerLayout layout;
  final RunShareInk ink;
  final RunPhotoAspect aspect;
  final List<RunShareStatKind> stats;

  /// Whether the image carries the Threkir mark. On unless the runner turns
  /// it off; free on every tier.
  final bool mark;

  /// Where the photo style's title and stats sit, kept apart for each aspect:
  /// a block placed on a tall story does not belong on a post.
  final Map<RunPhotoAspect, SharePlacement> placements;

  const RunShareLook({
    this.layout = RunStickerLayout.stack,
    this.ink = RunShareInk.light,
    this.aspect = RunPhotoAspect.story,
    this.stats = defaultStats,
    this.mark = true,
    this.placements = defaultPlacements,
  });

  static const defaultPlacements = {
    RunPhotoAspect.post: SharePlacement.initial,
    RunPhotoAspect.story: SharePlacement.initial,
  };

  /// The current aspect's placement.
  SharePlacement get placement =>
      placements[aspect] ?? SharePlacement.initial;

  /// `this` with the current aspect's placement set to [placement].
  RunShareLook withPlacement(SharePlacement placement) => copyWith(
        placements: {...placements, aspect: placement},
      );

  static const defaultStats = [
    RunShareStatKind.distance,
    RunShareStatKind.pace,
    RunShareStatKind.time,
  ];

  /// The most stats one sticker prints: past four, the strip layout no longer
  /// reads at story scale.
  static const maxStats = 4;

  RunShareLook copyWith({
    RunStickerLayout? layout,
    RunShareInk? ink,
    RunPhotoAspect? aspect,
    List<RunShareStatKind>? stats,
    bool? mark,
    Map<RunPhotoAspect, SharePlacement>? placements,
  }) =>
      RunShareLook(
        layout: layout ?? this.layout,
        ink: ink ?? this.ink,
        aspect: aspect ?? this.aspect,
        stats: stats ?? this.stats,
        mark: mark ?? this.mark,
        placements: placements ?? this.placements,
      );

  /// [stats] with [kind] added or removed. Never empties the set, and never
  /// grows it past [maxStats].
  RunShareLook toggleStat(RunShareStatKind kind) {
    if (stats.contains(kind)) {
      if (stats.length == 1) return this;
      return copyWith(stats: [for (final k in stats) if (k != kind) k]);
    }
    if (stats.length >= maxStats) return this;
    return copyWith(stats: [
      for (final k in RunShareStatKind.values)
        if (k == kind || stats.contains(k)) k,
    ]);
  }

  Map<String, Object> toJson() => {
        'layout': layout.name,
        'ink': ink.name,
        'aspect': aspect.name,
        'stats': [for (final k in stats) k.name],
        'mark': mark,
        'placements': {
          for (final a in RunPhotoAspect.values)
            a.name: (placements[a] ?? SharePlacement.initial).toJson(),
        },
      };

  /// Reads a stored look, field by field: an unknown or missing value takes
  /// its default rather than discarding the rest, so a look saved by a newer
  /// build still restores what this build understands.
  factory RunShareLook.fromJson(Object? json) {
    if (json is! Map) return const RunShareLook();
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) {
      for (final v in values) {
        if (v.name == name) return v;
      }
      return fallback;
    }

    final rawStats = json['stats'];
    final stats = <RunShareStatKind>[
      if (rawStats is List)
        for (final k in RunShareStatKind.values)
          if (rawStats.contains(k.name)) k,
    ];
    const d = RunShareLook();
    final rawPlacements = json['placements'];
    return RunShareLook(
      layout: pick(RunStickerLayout.values, json['layout'], d.layout),
      ink: pick(RunShareInk.values, json['ink'], d.ink),
      aspect: pick(RunPhotoAspect.values, json['aspect'], d.aspect),
      stats: stats.isEmpty
          ? defaultStats
          : stats.take(maxStats).toList(growable: false),
      mark: json['mark'] is bool ? json['mark'] as bool : d.mark,
      placements: {
        for (final a in RunPhotoAspect.values)
          a: SharePlacement.fromJson(
              rawPlacements is Map ? rawPlacements[a.name] : null),
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RunShareLook &&
      other.layout == layout &&
      other.ink == ink &&
      other.aspect == aspect &&
      other.mark == mark &&
      listEquals(other.stats, stats) &&
      mapEquals(other.placements, placements);

  @override
  int get hashCode => Object.hash(
        layout,
        ink,
        aspect,
        mark,
        Object.hashAll(stats),
        Object.hashAll([for (final a in RunPhotoAspect.values) placements[a]]),
      );
}

/// Device-local, not a synced setting: see docs/backend/settings.md §
/// Device-local pairing prefs.
const shareLookPrefsKey = 'share_look';

/// The look saved on this device, or the default when none is saved or the
/// read fails. A failed read is logged, never thrown: the share sheet must
/// open whatever the store does.
Future<RunShareLook> loadShareLook() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(shareLookPrefsKey);
    if (raw == null) return const RunShareLook();
    return RunShareLook.fromJson(jsonDecode(raw));
  } catch (e) {
    debugPrint('loadShareLook: falling back to the default look: $e');
    return const RunShareLook();
  }
}

/// Saves [look] for the next share. A failed write is logged: losing the
/// remembered look costs a runner one re-pick, which is no reason to fail the
/// share in front of them.
Future<void> saveShareLook(RunShareLook look) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(shareLookPrefsKey, jsonEncode(look.toJson()));
  } catch (e) {
    debugPrint('saveShareLook: look not saved: $e');
  }
}

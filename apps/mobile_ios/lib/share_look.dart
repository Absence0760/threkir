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

/// What a sticker is about: the run's numbers ([stats], in one of the four
/// layouts), or the occasion the run marks: its [splits], a personal record
/// ([pr]), a day of a [streak], a [race] finish, a [badge] it earned, or the
/// [route] outline alone. Twin of `RUN_STICKER_KINDS` in share_look.ts.
enum RunStickerKind { stats, splits, pr, streak, race, badge, route }

/// What a run holds for each occasion: the splits it has, the records it set,
/// the streak day it was (as of its own day, not today), whether it is linked
/// to a race and earned a badge, and whether it has a line to draw.
@immutable
class RunStickerOccasions {
  final int splits;
  final int records;
  final int streakDays;
  final bool race;
  final bool badge;
  final bool route;

  const RunStickerOccasions({
    this.splits = 0,
    this.records = 0,
    this.streakDays = 0,
    this.race = false,
    this.badge = false,
    this.route = false,
  });
}

/// One split is a single number, not a breakdown.
const minSplitsStickerRows = 2;

/// A first run is not a streak.
const minStreakStickerDays = 2;

/// The kinds a run can print, in display order. [RunStickerKind.stats]
/// always; an occasion only when the run has its data, the same rule the stat
/// chips follow, so no sticker prints a dash.
List<RunStickerKind> offeredStickerKinds(RunStickerOccasions o) => [
      for (final k in RunStickerKind.values)
        if (switch (k) {
          RunStickerKind.stats => true,
          RunStickerKind.splits => o.splits >= minSplitsStickerRows,
          RunStickerKind.pr => o.records > 0,
          RunStickerKind.streak => o.streakDays >= minStreakStickerDays,
          RunStickerKind.race => o.race,
          RunStickerKind.badge => o.badge,
          RunStickerKind.route => o.route,
        })
          k,
    ];

/// The remembered [kind] when this run can print it, stats otherwise. The
/// stored look keeps the remembered kind for the next run that has it.
RunStickerKind stickerKindFor(
        RunStickerKind kind, List<RunStickerKind> offered) =>
    offered.contains(kind) ? kind : RunStickerKind.stats;

/// The room a splits sticker may take. It is sized for a 9:16 story 640
/// logical units tall, with the top and bottom eighths kept clear (the profile
/// header and the reply bar), of which it may cover half so the photo still
/// shows; and it may not be shrunk below [legibleDigitsPx] for the pace
/// digits.
abstract final class SplitsStickerBudget {
  static const double usableHeight = 480;
  static const double maxCover = 0.5;
  static const double legibleDigitsPx = 12;
}

/// The tallest a splits sticker may be at its natural size, for rows set at
/// [rowTextPx]: shrunk to the legibility floor, it must still fit the cover.
double splitsStickerMaxHeight(double rowTextPx) =>
    SplitsStickerBudget.usableHeight *
    SplitsStickerBudget.maxCover *
    rowTextPx /
    SplitsStickerBudget.legibleDigitsPx;

/// How many rows one table column holds inside the budget, given the row
/// pitch and the height of everything that is not a row.
int splitsColumnCapacity(double rowTextPx, double rowHeight, double chrome) {
  final n = ((splitsStickerMaxHeight(rowTextPx) - chrome) / rowHeight).floor();
  return n < 0 ? 0 : n;
}

/// A table of one column, of two, or one bar per split once even two columns
/// would overflow the budget.
enum SplitsStickerForm { single, paired, bars }

SplitsStickerForm splitsStickerForm(int rows, int capacity) {
  if (rows <= capacity) return SplitsStickerForm.single;
  if (rows <= capacity * 2) return SplitsStickerForm.paired;
  return SplitsStickerForm.bars;
}

/// One split as the sticker reads it: its pace, its length and whether it is
/// the short tail the run ended on.
@immutable
class SplitsStickerRow {
  final double paceSecPerKm;
  final double metres;
  final bool partial;

  const SplitsStickerRow({
    required this.paceSecPerKm,
    required this.metres,
    this.partial = false,
  });
}

/// The fastest whole split, or -1 when there is none. A partial tail is never
/// the fastest, as on run detail: a few hundred metres is not a split.
int fastestStickerSplit(List<SplitsStickerRow> rows) {
  var best = -1;
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    if (r.partial || !(r.paceSecPerKm > 0)) continue;
    if (best < 0 || r.paceSecPerKm < rows[best].paceSecPerKm) best = i;
  }
  return best;
}

/// The pace over every split, weighted by length: the time the splits add up
/// to over the distance they cover.
double? averageStickerPace(List<SplitsStickerRow> rows) {
  var seconds = 0.0;
  var metres = 0.0;
  for (final r in rows) {
    if (!(r.paceSecPerKm > 0) || !(r.metres > 0)) continue;
    seconds += r.paceSecPerKm * r.metres / 1000;
    metres += r.metres;
  }
  return metres > 0 ? seconds / metres * 1000 : null;
}

/// The colour the sticker's type and route are drawn in: [light] for a dark
/// photo, [dark] for a bright one, [brand] for the Threkir coral.
enum RunShareInk { light, dark, brand }

/// The canvas the photo style is cut to: a 4:5 feed [post] or a 9:16 [story].
enum RunPhotoAspect { post, story }

/// The look a runner chose for their share images, kept on this device so the
/// next run shares the same way without choosing again.
@immutable
class RunShareLook {
  final RunStickerKind kind;
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
    this.kind = RunStickerKind.stats,
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
    RunStickerKind? kind,
    RunStickerLayout? layout,
    RunShareInk? ink,
    RunPhotoAspect? aspect,
    List<RunShareStatKind>? stats,
    bool? mark,
    Map<RunPhotoAspect, SharePlacement>? placements,
  }) =>
      RunShareLook(
        kind: kind ?? this.kind,
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
        'kind': kind.name,
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
      kind: pick(RunStickerKind.values, json['kind'], d.kind),
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
      other.kind == kind &&
      other.layout == layout &&
      other.ink == ink &&
      other.aspect == aspect &&
      other.mark == mark &&
      listEquals(other.stats, stats) &&
      mapEquals(other.placements, placements);

  @override
  int get hashCode => Object.hash(
        kind,
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

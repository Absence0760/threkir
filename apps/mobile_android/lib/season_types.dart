/// The race list a multi-race season is planned from (issue #1181). The
/// season request extracts it from the runner's description, the runner
/// confirms or edits it, and the season builder turns it into one chained
/// plan per A race with the B / C races attached to the plan they fall
/// inside. Mirrors web `training/season_types.ts`.
library;

enum SeasonRacePriority { a, b, c }

class SeasonRace {
  final String name;

  /// ISO `yyyy-mm-dd`.
  final String date;
  final double distanceM;
  final SeasonRacePriority priority;
  final int? goalTimeSec;

  const SeasonRace({
    required this.name,
    required this.date,
    required this.distanceM,
    required this.priority,
    this.goalTimeSec,
  });
}

class SeasonRequestResult {
  final List<SeasonRace> races;

  /// Why a race holds what it holds when it is not simply what the runner
  /// wrote: one key per adjustment, rendered as a localized line.
  final List<String> assumptions;

  const SeasonRequestResult({required this.races, required this.assumptions});
}

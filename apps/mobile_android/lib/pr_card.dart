// The personal records one run set, as the PR share card prints them. A
// TS↔Dart parity pair with apps/web/src/lib/share/pr_card.ts
// (docs/architecture/parity_pairs.md), so both platforms offer the same
// brackets in the same order with the same improvement.
//
// Two sources, both owner-only: `personal_record_improvements`, the log the
// refresher writes when a run beats the cache (with the time it replaced), and
// `personal_records`, the cache itself. A record the run still holds but that
// predates the log has no known previous time, so it prints as a record with no
// "faster by" line rather than as a first.

import 'run_share_stats.dart' show formatShareDuration;

const List<String> prBrackets = [
  '1_mile',
  '5k',
  '8k',
  '10k',
  '12k',
  'half_marathon',
  'marathon',
];

/// The bracket's nominal distance, which orders the card's brackets longest
/// first.
const Map<String, double> prBracketMetres = {
  '1_mile': 1609.344,
  '5k': 5000,
  '8k': 8000,
  '10k': 10000,
  '12k': 12000,
  'half_marathon': 21097.5,
  'marathon': 42195,
};

/// One logged improvement: a `personal_record_improvements` row.
class PrImprovementRow {
  final String distance;
  final int bestTimeS;
  final int? previousTimeS;
  const PrImprovementRow(this.distance, this.bestTimeS, this.previousTimeS);
}

/// One held record: a `personal_records` row.
class PrHeldRow {
  final String distance;
  final int bestTimeS;
  const PrHeldRow(this.distance, this.bestTimeS);
}

/// [improved] beat an earlier record; [first] was the first time in that
/// bracket; [held] is a record the run holds from before the log existed.
enum PrCardKind { improved, first, held }

class PrCardEntry {
  final String distance;
  final int timeS;
  final int? previousS;
  final PrCardKind kind;

  const PrCardEntry({
    required this.distance,
    required this.timeS,
    required this.previousS,
    required this.kind,
  });

  @override
  bool operator ==(Object other) =>
      other is PrCardEntry &&
      other.distance == distance &&
      other.timeS == timeS &&
      other.previousS == previousS &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(distance, timeS, previousS, kind);

  @override
  String toString() => 'PrCardEntry($distance, $timeS, $previousS, ${kind.name})';
}

/// Every bracket the run set, longest first. A logged improvement wins over the
/// cache row for the same bracket, since only the log knows what it beat.
List<PrCardEntry> prCardEntries(
  List<PrImprovementRow> improvements,
  List<PrHeldRow> held,
) {
  final byBracket = <String, PrCardEntry>{};
  for (final row in held) {
    if (!prBracketMetres.containsKey(row.distance) || row.bestTimeS <= 0) continue;
    byBracket[row.distance] = PrCardEntry(
      distance: row.distance,
      timeS: row.bestTimeS,
      previousS: null,
      kind: PrCardKind.held,
    );
  }
  for (final row in improvements) {
    if (!prBracketMetres.containsKey(row.distance) || row.bestTimeS <= 0) continue;
    final prev = row.previousTimeS;
    final previous = prev != null && prev > row.bestTimeS ? prev : null;
    byBracket[row.distance] = PrCardEntry(
      distance: row.distance,
      timeS: row.bestTimeS,
      previousS: previous,
      kind: previous == null ? PrCardKind.first : PrCardKind.improved,
    );
  }
  return byBracket.values.toList()
    ..sort((a, b) =>
        prBracketMetres[b.distance]!.compareTo(prBracketMetres[a.distance]!));
}

/// Seconds faster than the record it beat, or null when nothing was beaten.
int? prImprovementSeconds(PrCardEntry entry) {
  final prev = entry.previousS;
  return prev == null ? null : prev - entry.timeS;
}

/// The improvement as the card prints it ("00:42"), or null.
String? formatPrImprovement(PrCardEntry entry) {
  final s = prImprovementSeconds(entry);
  return s == null ? null : formatShareDuration(Duration(seconds: s));
}

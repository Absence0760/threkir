/// Effort and heart-rate targets on a planned workout, and who last edited it
/// (issue #1186, decisions § 2092).
///
/// `plan_workouts.target_rpe_min/max` (1..10) and `target_hr_min_bpm/max_bpm`
/// (30..230) are each a range with either end open: "RPE 3-4" sets both,
/// "cap at 125 bpm" sets only the top. The bounds and the ordering rule are
/// the columns' CHECKs (migration 20270912000001); this module is the client
/// half so a form refuses what the database would.
///
/// Dart twin of `apps/web/src/lib/training/workout_prescription.ts` — keep the
/// bounds, the shapes, the rules and the test count in lockstep.
library;

const int rpeMin = 1;
const int rpeMax = 10;
const int targetHrMinBpm = 30;
const int targetHrMaxBpm = 230;

class RangeBounds {
  const RangeBounds(this.min, this.max);
  final int min;
  final int max;
}

const RangeBounds rpeBounds = RangeBounds(rpeMin, rpeMax);
const RangeBounds targetHrBounds = RangeBounds(targetHrMinBpm, targetHrMaxBpm);

/// How a range reads: [between] (3-4), [exact] (both ends equal), [atMost]
/// (a cap), [atLeast] (a floor). Null when neither end is set.
enum RangeShape { between, exact, atMost, atLeast }

RangeShape? rangeShape(int? min, int? max) {
  if (min == null && max == null) return null;
  if (min == null) return RangeShape.atMost;
  if (max == null) return RangeShape.atLeast;
  return min == max ? RangeShape.exact : RangeShape.between;
}

enum RangeRefusal { notWhole, outOfRange, reversed }

/// The outcome of [parseTargetRange]: the accepted ends, or why not.
class ParsedRange {
  const ParsedRange.ok(this.min, this.max) : reason = null;
  const ParsedRange.refused(RangeRefusal this.reason)
      : min = null,
        max = null;

  final int? min;
  final int? max;
  final RangeRefusal? reason;

  bool get ok => reason == null;
}

/// Validate a typed range. Each end may be empty (null). An end must be a
/// whole number inside [bounds], and a low end may not exceed the high end.
ParsedRange parseTargetRange(num? min, num? max, RangeBounds bounds) {
  for (final v in [min, max]) {
    if (v == null) continue;
    if (!v.isFinite || v != v.roundToDouble()) {
      return const ParsedRange.refused(RangeRefusal.notWhole);
    }
    if (v < bounds.min || v > bounds.max) {
      return const ParsedRange.refused(RangeRefusal.outOfRange);
    }
  }
  final lo = min?.toInt();
  final hi = max?.toInt();
  if (lo != null && hi != null && lo > hi) {
    return const ParsedRange.refused(RangeRefusal.reversed);
  }
  return ParsedRange.ok(lo, hi);
}

/// True when someone other than the plan's owner made the workout's last
/// edit, seen by the owner. Only the owner and an active coach can write a
/// plan's workouts (RLS, 20261116_001), so for the owner a different editor
/// is their coach. Null `updated_by` (never edited, or a server-side write)
/// is not.
bool isEditedByCoach({
  required String? updatedBy,
  required String? ownerId,
  required String? viewerId,
}) {
  if (ownerId == null || viewerId == null || viewerId != ownerId) return false;
  return updatedBy != null && updatedBy != ownerId;
}

/// How many equal-width entry fields a row of [maxWidth] should carry.
///
/// A row of `n` `Expanded` fields gives each `width / n`, and an
/// `InputDecoration` crops its label silently when that is too narrow — so a
/// localized label ("Distância", "Time (s)") or a larger OS text size leaves
/// the athlete reading a field whose name is gone. [minFieldWidth] is the
/// caller's per-field floor already scaled by `MediaQuery.textScalerOf`, which
/// is what makes the answer track the text rather than a guessed dp
/// (conventions.md's mechanism 2, § 500).
///
/// Rows are **balanced**, not greedily filled: five fields that fit four
/// across split 3+2 rather than stranding one field alone on a second row.
/// Never answers less than one — a floor wider than the row still has to put
/// the field somewhere, and a full-width crop beats an empty layout.
int fieldsPerRow({
  required int count,
  required double maxWidth,
  required double minFieldWidth,
  required double gap,
}) {
  if (count <= 1) return 1;
  final fit = ((maxWidth + gap) / (minFieldWidth + gap)).floor();
  final rows = (count / fit.clamp(1, count)).ceil();
  return (count / rows).ceil();
}

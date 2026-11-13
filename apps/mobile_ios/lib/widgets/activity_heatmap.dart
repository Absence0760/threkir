import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../goals.dart' show weekStartLocal;
import '../l10n/gen/app_localizations.dart';

/// Maps a horizontal tap offset on the run-heatmap grid to the start
/// date (week anchor) of the column it landed in. Columns are weeks;
/// the offset is clamped so a tap past either edge resolves to the
/// first or last visible week rather than off-grid.
DateTime heatmapWeekAnchor({
  required double localDx,
  required double cellSize,
  required double gap,
  required int weeks,
  required DateTime gridStart,
}) {
  final col = (localDx / (cellSize + gap)).floor().clamp(0, weeks - 1);
  // Calendar days — see `ActivityHeatmap.build`, where `gridStart` is derived.
  return DateTime(gridStart.year, gridStart.month, gridStart.day + 7 * col);
}

/// First day of the heatmap's leftmost column: the start of the week
/// containing [now] on the runner's [weekStartDay], [weeks] - 1 weeks back.
/// Each column is then one of the weeks a tap opens in the week summary.
DateTime heatmapGridStart(
  DateTime now,
  int weeks, {
  required String weekStartDay,
}) {
  final weekStart = weekStartLocal(now, weekStartDay: weekStartDay);
  // Calendar days, not 24-hour blocks: the grid reaches ~5 months back, so a
  // fixed-Duration step is guaranteed to cross a DST transition and land
  // `gridStart` at 23:00 the previous day — shifting every column of the
  // heatmap, and the week a tap resolves to, one day off the calendar.
  return DateTime(
    weekStart.year,
    weekStart.month,
    weekStart.day - 7 * (weeks - 1),
  );
}

/// GitHub-style activity heatmap — a 7×[weeks] grid of squares, intensity
/// scaled to the day's run count. Rightmost column is the current week;
/// leftmost is `weeks - 1` weeks ago. It lives on the weekly summary as a
/// week picker since it left Home, as web's did (decisions § 513, § 2284).
class ActivityHeatmap extends StatelessWidget {
  final List<Run> runs;
  final int weeks;
  final String weekStartDay;

  /// Tapping a week column picks that week; the weekly summary moves to it.
  /// Null leaves the heatmap a static read-only grid.
  final void Function(DateTime weekAnchor)? onWeekTap;

  /// The week the picker has selected, and how to name a week. With both and
  /// [onWeekTap], a screen reader hears the selected week as the grid's
  /// value and steps it with swipe up / down: TalkBack's double-tap lands a
  /// tap at the node's origin, which always picked the oldest column.
  final DateTime? selectedWeek;
  final String Function(DateTime weekStart)? weekLabel;

  const ActivityHeatmap({
    super.key,
    required this.runs,
    required this.weekStartDay,
    this.weeks = 20,
    this.onWeekTap,
    this.selectedWeek,
    this.weekLabel,
  });

  /// The grid column [week] falls in, clamped to the grid.
  static int columnOf(DateTime week, DateTime gridStart, int weeks) {
    final days = DateTime.utc(week.year, week.month, week.day)
        .difference(
          DateTime.utc(gridStart.year, gridStart.month, gridStart.day),
        )
        .inDays;
    return (days ~/ 7).clamp(0, weeks - 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final gridStart = heatmapGridStart(now, weeks, weekStartDay: weekStartDay);

    final counts = heatmapDayCounts(runs, gridStart);
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    DateTime weekAt(int col) =>
        DateTime(gridStart.year, gridStart.month, gridStart.day + 7 * col);
    final pick = onWeekTap;
    final label = weekLabel;
    final selectedCol = selectedWeek == null
        ? null
        : columnOf(selectedWeek!, gridStart, weeks);
    final canStep = pick != null && label != null && selectedCol != null;

    final ramp = ChartPalette.of(context).ramp;
    // The zero tile is a track, not a level: it carries "no run", and what a
    // reader needs from it is the calendar position that gives every filled
    // tile its meaning. A tonal fill cannot do that — surfaceContainerHighest
    // is 1.164:1 on the light card and 1.316:1 on the dark one, so the grid
    // frame was invisible and the ramp's own first two steps (1.952 / 2.102:1
    // as primary at 35 %) were under 1.4.11's floor. The frame is a hairline
    // in the line token §487 already holds at 3:1, and the levels are the
    // palette's ramp.
    final emptyFill = theme.colorScheme.surfaceContainerHighest;
    final emptyStroke = theme.dividerColor;

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 2.0;
        final cellSize = ((constraints.maxWidth - gap * (weeks - 1)) / weeks)
            .clamp(8.0, 16.0);
        final gridWidth = cellSize * weeks + gap * (weeks - 1);
        final gridHeight = cellSize * 7 + gap * 6;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ChartCardHeader(
              title: l10n.dashboardHeatmapTitle,
              note: l10n.dashboardSectionLast20Weeks,
            ),
            const SizedBox(height: 10),
            // Single CustomPaint replaces the previous 7×20=140 Container +
            // Builder + EdgeInsets allocations per dashboard rebuild.
            // One node for the grid: the paint has nothing to read, and the
            // gesture's own tap action would land at the origin (week 1).
            Semantics(
              container: true,
              excludeSemantics: true,
              label:
                  '${l10n.dashboardHeatmapTitle}. '
                  '${l10n.dashboardSectionLast20Weeks}. ${l10n.historyCount(total)}',
              value: canStep ? label(weekAt(selectedCol)) : null,
              increasedValue: canStep && selectedCol < weeks - 1
                  ? label(weekAt(selectedCol + 1))
                  : null,
              decreasedValue: canStep && selectedCol > 0
                  ? label(weekAt(selectedCol - 1))
                  : null,
              onIncrease: canStep && selectedCol < weeks - 1
                  ? () => pick(weekAt(selectedCol + 1))
                  : null,
              onDecrease: canStep && selectedCol > 0
                  ? () => pick(weekAt(selectedCol - 1))
                  : null,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: onWeekTap == null
                    ? null
                    : (details) => onWeekTap!(
                        heatmapWeekAnchor(
                          localDx: details.localPosition.dx,
                          cellSize: cellSize,
                          gap: gap,
                          weeks: weeks,
                          gridStart: gridStart,
                        ),
                      ),
                child: SizedBox(
                  width: gridWidth,
                  height: gridHeight,
                  child: CustomPaint(
                    key: const Key('dashboardHeatmapPainter'),
                    painter: _HeatmapPainter(
                      counts: counts,
                      gridStart: gridStart,
                      today: today,
                      weeks: weeks,
                      cellSize: cellSize,
                      gap: gap,
                      emptyFill: emptyFill,
                      emptyStroke: emptyStroke,
                      ramp: ramp,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    l10n.dashboardHeatmapLess,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                for (final level in [-1, 0, 1, 2]) ...[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: level < 0 ? emptyFill : ramp[level],
                      border: level < 0 ? Border.all(color: emptyStroke) : null,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 3),
                ],
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    l10n.dashboardHeatmapMore,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            if (onWeekTap != null) ...[
              const SizedBox(height: 6),
              Text(
                l10n.dashboardHeatmapTapHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// A calendar day's index, read off the date's fields through UTC. Dividing
/// the LOCAL midnight's epoch milliseconds by a day instead floors a 23:00 UTC
/// midnight into the previous day, so where the offset moves between +0 and +1
/// (London, Lisbon, Dublin) the spring change gave Sunday and Monday one key
/// and both tiles painted their summed count.
int _epochDay(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

/// Per-epoch-day run counts for the heatmap's visible window. Runs whose local
/// day is before [gridStart] are skipped — the painter only ever reads keys
/// inside the `[gridStart, gridStart + weeks*7)` grid, so counting all-time
/// history (the full `summaryRuns`) on every rebuild was wasted work. A
/// 3,000-run user spent ~5-15ms/rebuild on the unguarded scan; the window
/// guard makes it O(visible days).
@visibleForTesting
Map<int, int> heatmapDayCounts(List<Run> runs, DateTime gridStart) {
  final gridStartDay = _epochDay(gridStart);
  final counts = <int, int>{};
  for (final r in runs) {
    final key = _epochDay(r.startedAt.toLocal());
    if (key < gridStartDay) continue;
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}

class _HeatmapPainter extends CustomPainter {
  final Map<int, int> counts;
  final DateTime gridStart;
  final DateTime today;
  final int weeks;
  final double cellSize;
  final double gap;
  final Color emptyFill;
  final Color emptyStroke;
  final List<Color> ramp;

  _HeatmapPainter({
    required this.counts,
    required this.gridStart,
    required this.today,
    required this.weeks,
    required this.cellSize,
    required this.gap,
    required this.emptyFill,
    required this.emptyStroke,
    required this.ramp,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final radius = const Radius.circular(4);
    final emptyP = Paint()..color = emptyFill;
    final framePaint = Paint()
      ..color = emptyStroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final levelPaints = [for (final c in ramp) Paint()..color = c];

    for (var w = 0; w < weeks; w++) {
      for (var d = 0; d < 7; d++) {
        final day = DateTime(
          gridStart.year,
          gridStart.month,
          gridStart.day + w * 7 + d,
        );
        // Don't paint future days — they're outside the scale and look
        // weird with an "empty" tile shown.
        if (day.isAfter(today)) continue;
        final count = counts[_epochDay(day)] ?? 0;
        final x = w * (cellSize + gap);
        final y = d * (cellSize + gap);
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, cellSize, cellSize),
          radius,
        );
        if (count <= 0) {
          canvas.drawRRect(rect, emptyP);
          canvas.drawRRect(rect.deflate(0.5), framePaint);
        } else {
          canvas.drawRRect(
            rect,
            levelPaints[count > levelPaints.length
                ? levelPaints.length - 1
                : count - 1],
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_HeatmapPainter old) =>
      !identical(old.counts, counts) ||
      old.gridStart != gridStart ||
      old.today != today ||
      old.weeks != weeks ||
      old.cellSize != cellSize ||
      old.emptyFill != emptyFill ||
      old.emptyStroke != emptyStroke ||
      old.ramp.last != ramp.last;
}

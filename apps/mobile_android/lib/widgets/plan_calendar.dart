import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show AppTheme;

import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../training.dart';
import 'plan_card.dart';
import 'plan_day_cell.dart';

/// Month-by-month calendar projection of a training plan, mirroring the
/// web's `PlanCalendar.svelte`. Each day cell shows the workout kind +
/// target distance when one is scheduled, drawn in its done / missed /
/// skipped state by [PlanDayCell]; out-of-plan days are blank and
/// out-of-month days without a workout are dimmed. A cell that DOES carry a
/// workout is never dimmed: the dim is `AppTheme.dimmedSubtreeOpacity` over
/// the whole subtree, and a planned session on the first or last row of the
/// grid is content, not chrome.
///
/// The grid follows the runner's `week_start_day` ([weekStartDay]), as web's
/// does; "today" comes from [today], the screen's injected clock.
///
/// `onSelect` is invoked when the user taps a workout cell. Hosts pass
/// the same handler they use for the weekly grid (push the workout
/// detail screen).

class PlanCalendar extends StatefulWidget {
  final DateTime startDate;
  final DateTime endDate;
  final List<PlanWorkoutRow> workouts;
  final void Function(PlanWorkoutRow workout)? onSelect;

  /// 'monday' or 'sunday'.
  final String weekStartDay;

  /// The runner's local day.
  final DateTime today;

  const PlanCalendar({
    super.key,
    required this.startDate,
    required this.endDate,
    required this.workouts,
    required this.today,
    this.weekStartDay = 'monday',
    this.onSelect,
  });

  @override
  State<PlanCalendar> createState() => _PlanCalendarState();
}

class _PlanCalendarState extends State<PlanCalendar> {
  late int _currentIdx = _initialIdx();

  List<({int year, int month})> get _months {
    final out = <({int year, int month})>[];
    var y = widget.startDate.year;
    var m = widget.startDate.month - 1; // 0-indexed
    final ey = widget.endDate.year;
    final em = widget.endDate.month - 1;
    while (y < ey || (y == ey && m <= em)) {
      out.add((year: y, month: m));
      m += 1;
      if (m > 11) {
        m = 0;
        y += 1;
      }
    }
    return out;
  }

  /// The month holding today; before the plan the first month, after it the
  /// last, so a finished plan opens on its race rather than on week 1.
  int _initialIdx() {
    final m = _months;
    if (m.isEmpty) return 0;
    final today = _toIso(widget.today);
    if (today.compareTo(_toIso(widget.startDate)) < 0) return 0;
    if (today.compareTo(_toIso(widget.endDate)) > 0) return m.length - 1;
    final idx = m.indexWhere((e) =>
        e.year == widget.today.year && e.month == widget.today.month - 1);
    return idx >= 0 ? idx : 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    final months = _months;
    if (months.isEmpty) return const SizedBox.shrink();
    final current = months[_currentIdx.clamp(0, months.length - 1)];
    final today = _toIso(widget.today);
    final sundayFirst = widget.weekStartDay == 'sunday';

    final byDate = <String, PlanWorkoutRow>{
      for (final w in widget.workouts) _toIso(w.scheduledDate): w,
    };

    final cells = _buildGrid(current.year, current.month, sundayFirst);
    final startIso = _toIso(widget.startDate);
    final endIso = _toIso(widget.endDate);

    return Container(
      decoration: planCardDecoration(theme),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentIdx > 0
                    ? () => setState(() => _currentIdx -= 1)
                    : null,
                tooltip: l10n.planCalendarPrevMonth,
              ),
              Flexible(
                child: Text(
                  '${formatMonthName(DateTime(current.year, current.month + 1), tag)} ${current.year}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _currentIdx < months.length - 1
                    ? () => setState(() => _currentIdx += 1)
                    : null,
                tooltip: l10n.planCalendarNextMonth,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Center(
                    child: Text(
                      // 2026-01-04 is a Sunday, 2026-01-05 a Monday.
                      formatDow(
                          addDays(DateTime(2026, 1, sundayFirst ? 4 : 5), i),
                          tag),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // Render cells in rows of 7. Use a Column-of-Rows rather than
          // GridView so the cells size to their content (title + pill +
          // distance), which would otherwise force a fixed aspect ratio.
          for (var r = 0; r < cells.length; r += 7)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: _buildCell(
                        theme,
                        tag,
                        cells[r + i],
                        byDate[cells[r + i].iso],
                        today,
                        startIso,
                        endIso,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCell(
    ThemeData theme,
    String tag,
    _Cell cell,
    PlanWorkoutRow? wo,
    String today,
    String startIso,
    String endIso,
  ) {
    final inPlan = cell.iso.compareTo(startIso) >= 0 &&
        cell.iso.compareTo(endIso) <= 0;
    final hasWorkout = wo != null && inPlan;
    final day = DateTime.parse(cell.iso);
    final dayCell = PlanDayCell(
      header: '${cell.day}',
      workout: hasWorkout ? wo : null,
      todayIso: today,
      isToday: inPlan && cell.iso == today,
      semanticsDay: formatDowDateShort(day, tag),
      onSelect: widget.onSelect,
    );
    if (!inPlan) {
      return Opacity(
        opacity: cell.inMonth ? 1 : AppTheme.dimmedSubtreeOpacity,
        child: Container(
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.all(4),
          constraints: const BoxConstraints(minHeight: 56),
          child: Text('${cell.day}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              )),
        ),
      );
    }
    if (!hasWorkout && !cell.inMonth) {
      return Opacity(
          opacity: AppTheme.dimmedSubtreeOpacity, child: dayCell);
    }
    return dayCell;
  }

  static String _toIso(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }

  /// Build the 6-row × 7-col cell grid for the given month, padded with
  /// trailing days from the previous and following months, starting the row
  /// on Monday or, when [sundayFirst], on Sunday.
  List<_Cell> _buildGrid(int year, int month, bool sundayFirst) {
    final first = DateTime(year, month + 1, 1); // 1-indexed month
    final last = DateTime(year, month + 2, 0); // last day of this month
    final lastDay = last.day;
    // first.weekday is Mon=1..Sun=7.
    final leadDow = sundayFirst ? first.weekday % 7 : (first.weekday - 1) % 7;

    final cells = <_Cell>[];
    final prevLast = DateTime(year, month + 1, 0).day;
    for (var i = leadDow; i > 0; i--) {
      final d = prevLast - i + 1;
      final pm = month == 0 ? 11 : month - 1;
      final py = month == 0 ? year - 1 : year;
      cells.add(_Cell(
        iso: _isoFromYmd(py, pm, d),
        day: d,
        inMonth: false,
      ));
    }
    for (var d = 1; d <= lastDay; d++) {
      cells.add(_Cell(
        iso: _isoFromYmd(year, month, d),
        day: d,
        inMonth: true,
      ));
    }
    final remainder = cells.length % 7;
    if (remainder != 0) {
      final trail = 7 - remainder;
      for (var d = 1; d <= trail; d++) {
        final nm = month == 11 ? 0 : month + 1;
        final ny = month == 11 ? year + 1 : year;
        cells.add(_Cell(
          iso: _isoFromYmd(ny, nm, d),
          day: d,
          inMonth: false,
        ));
      }
    }
    return cells;
  }

  static String _isoFromYmd(int y, int monthZero, int d) {
    final mm = (monthZero + 1).toString().padLeft(2, '0');
    final dd = d.toString().padLeft(2, '0');
    final yy = y.toString().padLeft(4, '0');
    return '$yy-$mm-$dd';
  }
}

class _Cell {
  final String iso;
  final int day;
  final bool inMonth;
  const _Cell({required this.iso, required this.day, required this.inMonth});
}

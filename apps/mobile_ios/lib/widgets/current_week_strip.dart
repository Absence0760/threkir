import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show ChartCardHeader;

import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../training.dart';
import 'plan_day_cell.dart';

/// Focused current-week 7-day ribbon for `plan_detail_screen`, mirroring web's
/// `CurrentWeekStrip.svelte`. The 7-day window is anchored to the plan's
/// CURRENT week bucket (`startDate + weekIndex*7`), NOT the real calendar week,
/// so the strip's completion count matches the week card's count exactly. That
/// is also why it starts on the plan's first weekday rather than on the
/// runner's `week_start_day`: a plan week is not a calendar week.
class CurrentWeekStrip extends StatelessWidget {
  final DateTime startDate;
  final int weekIndex;
  final List<PlanWorkoutRow> weekWorkouts;
  final void Function(PlanWorkoutRow workout)? onSelect;

  /// The runner's local day, from the screen's injected clock.
  final DateTime today;

  /// Heading override: before the plan starts the strip shows its first week,
  /// which is not "This week".
  final String? title;

  const CurrentWeekStrip({
    super.key,
    required this.startDate,
    required this.weekIndex,
    required this.weekWorkouts,
    required this.today,
    this.title,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    final todayIso = toIsoDate(today);

    final byDate = <String, PlanWorkoutRow>{
      for (final w in weekWorkouts) toIsoDate(w.scheduledDate): w,
    };
    // Calendar days, not 24-hour blocks: `add(Duration(days:))` walks absolute
    // time, so across a DST fall-back a local midnight lands at 23:00 the
    // PREVIOUS day. That repeats a day in the row and drops the seventh — the
    // long run, on a Sunday-ending plan week — out of the strip entirely, and
    // a plan whose start is a transition away shifts all seven cells by a day.
    final weekStart = addDays(startDate, weekIndex * 7);
    final cells = [
      for (var i = 0; i < 7; i++) addDays(weekStart, i),
    ];

    final done = weekWorkouts.where(isWorkoutCompleted).length;
    final active = weekWorkouts
        .where((w) => w.kind != 'rest' && !isWorkoutSkipped(w.skippedAt))
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: ChartCardHeader(
            title: title ?? l10n.planDetailCurrentWeek,
            note: l10n.planDetailWeekDoneCount(done, active),
          ),
        ),
        Row(
          children: [
            for (final d in cells)
              Expanded(
                child: PlanDayCell(
                  header: formatDow(d, tag),
                  workout: byDate[toIsoDate(d)],
                  todayIso: todayIso,
                  isToday: toIsoDate(d) == todayIso,
                  semanticsDay: formatDowDateShort(d, tag),
                  minHeight: 60,
                  onSelect: onSelect,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

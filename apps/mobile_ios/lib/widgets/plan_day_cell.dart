import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show AppRadius, AppIconSize;

import '../l10n/gen/app_localizations.dart';
import '../plan_current.dart';
import '../training.dart';
import '../training_labels.dart';
import '../workout_kind_color.dart';
import 'plan_workout_status_style.dart';

/// Below this width a 7-column cell holds about 29-33 dp of text, so the kind
/// reads as its abbreviation; web switches at the same 600 px.
const double kPlanCellShortLabelBelow = 600;

/// One day of a plan grid: the month calendar and the current-week strip
/// share it so a state looks the same in both. [header] is the day number or
/// the weekday. A null [workout] draws an empty in-plan day.
class PlanDayCell extends StatelessWidget {
  final String header;
  final PlanWorkoutRow? workout;
  final String todayIso;
  final bool isToday;
  final String semanticsDay;
  final double minHeight;
  final void Function(PlanWorkoutRow workout)? onSelect;

  const PlanDayCell({
    super.key,
    required this.header,
    required this.workout,
    required this.todayIso,
    required this.isToday,
    required this.semanticsDay,
    this.minHeight = 56,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final wo = workout;
    final kind = wo == null ? null : workoutKindFromDb(wo.kind);
    final status = wo == null ? null : planWorkoutStatusOf(wo, todayIso);
    final look = status == null ? null : planWorkoutStatusLook(theme, status);
    final short =
        MediaQuery.sizeOf(context).width < kPlanCellShortLabelBelow;
    final radius = BorderRadius.circular(AppRadius.sm);

    Widget cell = Container(
      margin: const EdgeInsets.all(2),
      padding: const EdgeInsets.all(4),
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        color: wo == null
            ? Colors.transparent
            : (look?.fill ?? theme.colorScheme.surfaceContainerHigh),
        border: Border.all(
          color: isToday
              ? theme.colorScheme.primary
              : (look?.dashed ?? false)
                  ? Colors.transparent
                  : (look?.outline ?? theme.dividerColor),
          width: isToday ? 1.5 : 1,
        ),
        borderRadius: radius,
      ),
      foregroundDecoration: wo != null
          ? BoxDecoration(
              border: Border(
                left: BorderSide(
                    color: workoutKindMarkColor(theme, kind!), width: 3),
              ),
              borderRadius: radius,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            header,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          if (wo != null) ...[
            Text(
              short
                  ? workoutKindShortLabel(l10n, kind!)
                  : workoutKindLabel(l10n, kind!).toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w800,
                letterSpacing: short ? 0 : 0.4,
                decoration: status == PlanWorkoutStatus.skipped
                    ? TextDecoration.lineThrough
                    : null,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (wo.targetDistanceM != null && wo.kind != 'rest')
              Text(
                fmtKm(wo.targetDistanceM, 1),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (look?.glyph != null)
              Align(
                alignment: AlignmentDirectional.bottomEnd,
                child: Icon(look!.glyph,
                    size: AppIconSize.dense, color: look.glyphColor),
              ),
          ],
        ],
      ),
    );

    if (look != null && look.dashed && !isToday) {
      cell = CustomPaint(
        foregroundPainter: _InsetDashedOutline(look.outline!),
        child: cell,
      );
    }
    if (wo == null) return cell;
    return Semantics(
      button: onSelect != null,
      label: planWorkoutSemanticsLabel(
        l10n,
        wo,
        todayIso,
        day: semanticsDay,
        kind: workoutKindLabel(l10n, kind!),
        distance: wo.targetDistanceM != null && wo.kind != 'rest'
            ? fmtKm(wo.targetDistanceM, 1)
            : null,
      ),
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('planDayCell-${toIsoDate(wo.scheduledDate)}'),
        onTap: onSelect == null ? null : () => onSelect!(wo),
        borderRadius: radius,
        child: cell,
      ),
    );
  }
}

// The cell carries a 2 dp margin, so the dash is drawn inside it.
class _InsetDashedOutline extends CustomPainter {
  final Color color;
  const _InsetDashedOutline(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(2, 2);
    DashedOutlinePainter(color: color)
        .paint(canvas, Size(size.width - 4, size.height - 4));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_InsetDashedOutline old) => old.color != color;
}

import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show AppSemanticColors, AppRadius;

import '../l10n/gen/app_localizations.dart';
import '../plan_current.dart';
import '../training.dart';

// One look per plan-workout state, shared by every mobile surface that draws a
// planned workout: PlanCalendar, CurrentWeekStrip, the week rows and the Today
// card on plan detail. Before this, "done" was drawn three ways (a tertiary
// tick in the grid, a primary tick in the rows) and a missed workout looked
// exactly like an upcoming one. Web twin:
// apps/web/src/lib/training/plan_workout_status_style.ts and the reading in
// plan_workout_view.ts.
//
// Missed is neutral on purpose: the plan lets missed easy volume go (§ 144),
// so it is information, not a failure, and it borrows nothing from the error
// or warning colours. It is told apart by its dashed outline and its glyph.

/// Where [wo] stands on the runner's local day [todayIso].
PlanWorkoutStatus planWorkoutStatusOf(PlanWorkoutRow wo, String todayIso) =>
    planWorkoutStatus(
      scheduledIso: toIsoDate(wo.scheduledDate),
      kind: wo.kind,
      completed: isWorkoutCompleted(wo),
      skipped: isWorkoutSkipped(wo.skippedAt),
      todayIso: todayIso,
    );

class PlanWorkoutStatusLook {
  /// Cell fill, or null to keep the surface's own.
  final Color? fill;

  /// Outline colour, or null to keep the surface's own.
  final Color? outline;

  /// True for missed: the dash is what reads as "missed" without colour.
  final bool dashed;

  final IconData? glyph;
  final Color glyphColor;

  const PlanWorkoutStatusLook({
    required this.fill,
    required this.outline,
    required this.dashed,
    required this.glyph,
    required this.glyphColor,
  });
}

PlanWorkoutStatusLook planWorkoutStatusLook(
    ThemeData theme, PlanWorkoutStatus status) {
  final semantic = theme.extension<AppSemanticColors>() ??
      (theme.brightness == Brightness.dark
          ? AppSemanticColors.dark
          : AppSemanticColors.light);
  final muted = theme.colorScheme.onSurfaceVariant;
  return switch (status) {
    PlanWorkoutStatus.done => PlanWorkoutStatusLook(
        fill: Color.alphaBlend(semantic.success.withValues(alpha: 0.14),
            theme.colorScheme.surfaceContainerHigh),
        outline: semantic.success,
        dashed: false,
        glyph: Icons.check_circle,
        glyphColor: semantic.success,
      ),
    PlanWorkoutStatus.missed => PlanWorkoutStatusLook(
        fill: Colors.transparent,
        outline: muted,
        dashed: true,
        glyph: Icons.event_busy,
        glyphColor: muted,
      ),
    PlanWorkoutStatus.skipped => PlanWorkoutStatusLook(
        fill: Colors.transparent,
        outline: null,
        dashed: false,
        glyph: Icons.skip_next,
        glyphColor: muted,
      ),
    PlanWorkoutStatus.upcoming || PlanWorkoutStatus.rest =>
      PlanWorkoutStatusLook(
        fill: null,
        outline: null,
        dashed: false,
        glyph: null,
        glyphColor: muted,
      ),
  };
}

/// "Tue 13 Oct: Tempo, 8.0 km, missed". Web twin `planWorkoutAriaLabel`.
String planWorkoutSemanticsLabel(
  AppLocalizations l10n,
  PlanWorkoutRow wo,
  String todayIso, {
  required String day,
  required String kind,
  String? distance,
}) {
  final status = planWorkoutStatusOf(wo, todayIso);
  final suffix = switch (status) {
    PlanWorkoutStatus.done => l10n.planDetailAriaCompletedSuffix,
    PlanWorkoutStatus.skipped => l10n.planDetailAriaSkippedSuffix,
    PlanWorkoutStatus.missed => l10n.planDetailAriaMissedSuffix,
    _ => '',
  };
  final today =
      toIsoDate(wo.scheduledDate) == todayIso ? l10n.planDetailAriaTodaySuffix : '';
  final dist = distance != null ? ', $distance' : '';
  return '$day: $kind$dist$suffix$today';
}

/// Paints a dashed rounded outline over a cell, for the missed state.
class DashedOutlinePainter extends CustomPainter {
  final Color color;
  final double radius;
  final double strokeWidth;

  const DashedOutlinePainter({
    required this.color,
    this.radius = AppRadius.sm,
    this.strokeWidth = 1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          rect.deflate(strokeWidth / 2), Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    const dash = 4.0;
    const gap = 3.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(DashedOutlinePainter old) =>
      old.color != color || old.radius != radius || old.strokeWidth != strokeWidth;
}

import 'package:core_models/core_models.dart' show DistanceUnit;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:run_recorder/run_recorder.dart';
import 'package:ui_kit/ui_kit.dart' show AppSemanticColors, ProgressBar;

import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../l10n/number_format.dart';
import '../preferences.dart';
import '../training.dart' show fmtPace;
import '../workout_step_name.dart';

/// Top-of-map overlay that surfaces the current [WorkoutRunner] step
/// while the run screen is recording. Mirrors the spec in
/// [docs/features/workout_execution.md](../../../../docs/features/workout_execution.md).
///
/// Reads through a [ValueListenable] of `_BandState` snapshots so we
/// don't rebuild the whole run tree every GPS tick — the run screen
/// pushes a new state when transitions or progress events happen.
class WorkoutExecutionBand extends StatelessWidget {
  final ValueListenable<WorkoutBandState> state;
  final VoidCallback onSkip;
  final VoidCallback onRewind;
  final VoidCallback onAbandon;

  /// The workout's effort / heart-rate target as one line ("RPE 3–4 · Cap
  /// 125 bpm"), the same for every step; null hides it (decisions § 2092).
  final String? effortTarget;

  const WorkoutExecutionBand({
    super.key,
    required this.state,
    required this.onSkip,
    required this.onRewind,
    required this.onAbandon,
    this.effortTarget,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WorkoutBandState>(
      valueListenable: state,
      builder: (_, s, __) => _Band(
        state: s,
        onSkip: onSkip,
        onRewind: onRewind,
        onAbandon: onAbandon,
        effortTarget: effortTarget,
      ),
    );
  }
}

class WorkoutBandState {
  final WorkoutStep? step;
  final int totalSteps;
  final int currentIndex;
  final double progress; // 0..1
  final double remainingMetres;
  // Seconds remaining for duration-based steps. Zero for distance-based
  // (band reads `step.isDurationBased` to pick which to render).
  final Duration remainingDuration;
  final int? actualPaceSecPerKm;
  final PaceAdherence adherence;
  final bool complete;
  final bool abandoned;

  const WorkoutBandState({
    required this.step,
    required this.totalSteps,
    required this.currentIndex,
    required this.progress,
    required this.remainingMetres,
    this.remainingDuration = Duration.zero,
    required this.actualPaceSecPerKm,
    required this.adherence,
    required this.complete,
    required this.abandoned,
  });

  static const empty = WorkoutBandState(
    step: null,
    totalSteps: 0,
    currentIndex: 0,
    progress: 0,
    remainingMetres: 0,
    actualPaceSecPerKm: null,
    adherence: PaceAdherence.onPace,
    complete: false,
    abandoned: false,
  );
}

enum _BandAction { abandon }

class _Band extends StatelessWidget {
  final WorkoutBandState state;
  final VoidCallback onSkip;
  final VoidCallback onRewind;
  final VoidCallback onAbandon;
  final String? effortTarget;
  const _Band({
    required this.state,
    required this.onSkip,
    required this.onRewind,
    required this.onAbandon,
    this.effortTarget,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    if (state.abandoned) {
      return _shell(theme,
          child: Text(l10n.runWorkoutAbandonedBand,
              style: theme.textTheme.bodyMedium));
    }
    final step = state.step;
    if (step == null) {
      if (state.complete) {
        return _shell(theme,
            child: Text(
              l10n.runWorkoutCompleteBand,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ));
      }
      return const SizedBox.shrink();
    }

    return _shell(
      theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  // A walk-run step has no pace target: the easy pace it
                  // carries is only the plan's distance estimate.
                  step.paced
                      ? l10n.runWorkoutStepHeader(
                          workoutStepName(step, l10n),
                          _fmtTarget(step),
                          fmtPace(step.targetPaceSecPerKm),
                        )
                      : l10n.runWorkoutStepHeaderUnpaced(
                          workoutStepName(step, l10n),
                          _fmtTarget(step),
                        ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // A walk-run step is effort-led: no target to be on or off.
              if (step.paced)
                _PacePip(adherence: state.adherence, delta: _delta(step)),
            ],
          ),
          if (effortTarget != null)
            Text(
              effortTarget!,
              key: const Key('workoutBandEffortTarget'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 6),
          ProgressBar(value: state.progress.clamp(0.0, 1.0)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  l10n.runWorkoutStepCounter(
                      state.currentIndex + 1, state.totalSteps),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                _fmtRemaining(l10n, step),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // One labelled button: three equal labelled thirds broke "Rewind"
          // and "Abandon" mid-word on a phone (issue #1300). Abandon sits in
          // the menu because it ends the workout; run_screen confirms it.
          Row(
            children: [
              // Disabled on step 0: there is nothing to rewind to.
              Tooltip(
                message: l10n.runWorkoutRewind,
                excludeFromSemantics: true,
                child: IconButton(
                  key: const Key('workoutBandRewind'),
                  onPressed: state.currentIndex == 0 ? null : onRewind,
                  icon: Icon(Icons.skip_previous,
                      semanticLabel: l10n.runWorkoutRewind),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('workoutBandSkip'),
                  onPressed: onSkip,
                  icon: const Icon(Icons.skip_next, size: 18),
                  label: Text(
                    l10n.runWorkoutSkip,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<_BandAction>(
                key: const Key('workoutBandMore'),
                tooltip: l10n.runWorkoutMoreActions,
                icon: const Icon(Icons.more_vert),
                onSelected: (action) => switch (action) {
                  _BandAction.abandon => onAbandon(),
                },
                itemBuilder: (_) => [
                  PopupMenuItem<_BandAction>(
                    value: _BandAction.abandon,
                    child: Row(
                      children: [
                        Icon(Icons.cancel_outlined,
                            color: theme.colorScheme.error),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            l10n.runWorkoutAbandon,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _shell(ThemeData theme, {required Widget child}) {
    return Container(
      // The host column (RunTopOverlay) owns the top anchor and the outer
      // inset; this only matches the sibling badge row's 4 px gutter and
      // leaves a gap before the banners below.
      margin: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.95),
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  int? _delta(WorkoutStep step) {
    final actual = state.actualPaceSecPerKm;
    if (actual == null) return null;
    return actual - step.targetPaceSecPerKm;
  }

  static String _fmtDistance(double metres) {
    // Mid-workout pill — honour the user's active distance pref so
    // a mi-mode runner sees miles + yards instead of km + metres.
    final unit = activeDistanceUnit;
    final tag = activeLocaleTag;
    if (unit == DistanceUnit.mi) {
      const metresPerMile = 1609.344;
      if (metres >= metresPerMile) {
        return '${formatFixed(metres / metresPerMile, 1, tag)} mi';
      }
      return '${formatFixed((metres * 1.09361).round().toDouble(), 0, tag)} yd';
    }
    if (metres >= 1000) {
      return '${formatFixed(metres / 1000, 1, tag)} km';
    }
    return '${formatFixed(metres.round().toDouble(), 0, tag)} m';
  }

  static String _fmtDuration(Duration d) {
    final s = d.inSeconds;
    if (s >= 60) {
      final m = s ~/ 60;
      final r = s % 60;
      return r == 0 ? '${m}m' : '${m}m ${r}s';
    }
    return '${s}s';
  }

  // "Rep 3/6 · 400 m" or "Stride · 30s" depending on the step's axis.
  // Picks one or the other so the band header doesn't grow on duration
  // steps (the time target IS the size signal).
  static String _fmtTarget(WorkoutStep step) {
    if (step.isDurationBased) {
      return _fmtDuration(Duration(seconds: step.targetDurationSec!));
    }
    return _fmtDistance(step.targetDistanceMetres);
  }

  String _fmtRemaining(AppLocalizations l10n, WorkoutStep step) {
    if (step.isDurationBased) {
      return l10n.runWorkoutRemainingDuration(
          _fmtDuration(state.remainingDuration));
    }
    return l10n.runWorkoutRemainingDistance(
        UnitFormat.shortDistance(state.remainingMetres, activeDistanceUnit));
  }
}

class _PacePip extends StatelessWidget {
  final PaceAdherence adherence;
  final int? delta;
  const _PacePip({required this.adherence, required this.delta});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final color = switch (adherence) {
      PaceAdherence.onPace => semantic.success,
      PaceAdherence.ahead || PaceAdherence.behind => semantic.warning,
      PaceAdherence.wayAhead || PaceAdherence.wayBehind =>
        theme.colorScheme.error,
    };
    String label;
    if (delta == null) {
      label = '—';
    } else {
      final sign = delta! >= 0 ? '+' : '−';
      label = '$sign${delta!.abs()}s';
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

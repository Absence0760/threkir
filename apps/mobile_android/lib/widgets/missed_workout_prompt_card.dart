import 'package:core_models/core_models.dart' show PlanWeekRow, PlanWorkoutRow;
import 'package:flutter/material.dart';

import '../auth_error.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../plan_adherence.dart';
import '../plan_missed_prompt.dart';
import '../training.dart';
import '../training_labels.dart';
import '../training_service.dart';
import 'top_banner.dart';

/// Asks once about the runner's most recent missed workout
/// ([missedWorkoutPrompt], decisions § 2122), on Home above the Today card and
/// on plan detail's Today slot. The host shows it only to the owner of an
/// active, unfinished plan. "Let it go" records the answer here; "Make it up"
/// goes to the host's make-up preview, which records it on apply. Web twin:
/// `MissedWorkoutPrompt.svelte`.
class MissedWorkoutPromptCard extends StatefulWidget {
  final TrainingService training;
  final String planId;
  final MissedPrompt prompt;

  /// Opens the make-up preview. Required to offer "Make it up".
  final VoidCallback? onMakeUp;

  /// Runs after "Let it go" was recorded, so the host can re-read its plan.
  final Future<void> Function()? onAnswered;

  const MissedWorkoutPromptCard({
    super.key,
    required this.training,
    required this.planId,
    required this.prompt,
    this.onMakeUp,
    this.onAnswered,
  });

  /// The prompt for a loaded plan's rows on [now]'s local day, or null. A
  /// failure reads as nothing to ask, so it can never take the Today card
  /// with it.
  static MissedPrompt? promptFor({
    required List<PlanWeekRow> weeks,
    required List<PlanWorkoutRow> workouts,
    required DateTime now,
  }) {
    try {
      final byWeek = <String, List<PlanWorkoutRow>>{};
      for (final w in workouts) {
        byWeek.putIfAbsent(w.weekId, () => []).add(w);
      }
      return missedWorkoutPrompt(
        today: toIsoDate(now),
        weeks: [
          for (final w in weeks)
            MissedPromptWeek(
              weekIndex: w.weekIndex,
              phase: w.phase,
              plannedMetres: _plannedMetres(w, byWeek[w.id] ?? const []),
              workouts: [
                for (final x in byWeek[w.id] ?? const <PlanWorkoutRow>[])
                  MissedPromptWorkout(
                    id: x.id,
                    scheduledDate: toIsoDate(x.scheduledDate),
                    kind: x.kind,
                    targetDistanceM: x.targetDistanceM,
                    completed: isWorkoutCompleted(x),
                    skipped: isWorkoutSkipped(x.skippedAt),
                    answered: x.missedAckAt != null,
                  ),
              ],
            ),
        ],
      );
    } catch (e) {
      debugPrint('missed-workout prompt failed: $e');
      return null;
    }
  }

  static double _plannedMetres(PlanWeekRow w, List<PlanWorkoutRow> list) {
    final declared = w.targetVolumeM ?? 0;
    if (declared > 0) return declared;
    var sum = 0.0;
    for (final x in list) {
      if (x.kind != 'rest') sum += x.targetDistanceM ?? 0;
    }
    return sum;
  }

  @override
  State<MissedWorkoutPromptCard> createState() =>
      _MissedWorkoutPromptCardState();
}

class _MissedWorkoutPromptCardState extends State<MissedWorkoutPromptCard> {
  bool _busy = false;
  bool _answered = false;

  @override
  void didUpdateWidget(MissedWorkoutPromptCard old) {
    super.didUpdateWidget(old);
    if (old.prompt.workoutId != widget.prompt.workoutId) _answered = false;
  }

  Future<void> _letGo() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await widget.training.answerMissedWorkouts(
        planId: widget.planId,
        workoutIds: [widget.prompt.workoutId],
      );
    } catch (e) {
      debugPrint('missed-workout answer failed: $e');
      if (mounted) {
        setState(() => _busy = false);
        showTopBanner(
            context, l10n.missedPromptSaveFailed(friendlyError(l10n, e)));
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _answered = true;
    });
    showTopBanner(context, l10n.missedPromptLetGoDone);
    try {
      await widget.onAnswered?.call();
    } catch (e) {
      debugPrint('missed-workout host refresh failed: $e');
    }
  }

  String _body(AppLocalizations l10n, MissedPrompt p) {
    final makeUp = p.makeUp;
    if (makeUp != null) {
      return l10n.missedPromptMakeUpBody(
          fmtKm(makeUp.fromMetres), fmtKm(makeUp.toMetres));
    }
    return switch (p.advice.reason) {
      MissedWorkoutReason.keySession => l10n.missedPromptCoveredBody,
      MissedWorkoutReason.taper => l10n.missedPromptTaperBody,
      MissedWorkoutReason.recoverySoon => l10n.missedPromptRecoveryBody,
      MissedWorkoutReason.notLongRun => l10n.missedPromptLetGoBody,
    };
  }

  Widget _label(ThemeData theme, String action, bool recommended,
      AppLocalizations l10n) {
    if (!recommended) return Text(action);
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: action),
        const TextSpan(text: '  '),
        TextSpan(
          text: l10n.missedPromptRecommended,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: theme.textTheme.labelSmall?.fontSize,
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_answered) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    final p = widget.prompt;
    final offerMakeUp = p.makeUp != null && widget.onMakeUp != null;
    final day = formatDowDateShort(DateTime.parse(p.scheduledDate), tag);
    final kind = workoutKindLabel(l10n, workoutKindFromDb(p.kind));
    return Card(
      key: const Key('missedPrompt'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.event_busy, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.missedPromptTitle(kind, day),
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _body(l10n, p),
                        key: const Key('missedPromptBody'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (offerMakeUp)
                  FilledButton(
                    key: const Key('missedPromptMakeUp'),
                    onPressed: _busy ? null : widget.onMakeUp,
                    child: _label(theme, l10n.missedPromptMakeUp, true, l10n),
                  ),
                if (offerMakeUp)
                  OutlinedButton(
                    key: const Key('missedPromptLetGo'),
                    onPressed: _busy ? null : _letGo,
                    child: _label(theme, l10n.missedPromptLetGo, false, l10n),
                  )
                else
                  FilledButton(
                    key: const Key('missedPromptLetGo'),
                    onPressed: _busy ? null : _letGo,
                    child: _label(theme, l10n.missedPromptLetGo, true, l10n),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

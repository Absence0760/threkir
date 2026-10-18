import 'package:flutter/material.dart';

import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../plan_current.dart';
import '../training.dart' show toIsoDate;
import '../training_service.dart';
import 'top_banner.dart';

/// An active plan whose last day has passed ([isPlanFinished]) asks the
/// runner to file it under Completed. Nothing writes `completed` on its own,
/// so until they do the plan keeps reading as theirs. Shown on Home in the
/// race-countdown slot and under the plan detail header. Web twin:
/// `FinishPlanPrompt.svelte`.
class FinishPlanCard extends StatefulWidget {
  final TrainingService training;
  final String planId;
  final String planName;
  final DateTime endDate;

  /// Runs after the plan was filed, so the host can re-read its overview.
  final Future<void> Function() onFinished;

  const FinishPlanCard({
    super.key,
    required this.training,
    required this.planId,
    required this.planName,
    required this.endDate,
    required this.onFinished,
  });

  /// Whether a plan with [status] ending on [endDate] is finished on [now]'s
  /// local day.
  static bool shows({
    required String status,
    required DateTime endDate,
    required DateTime now,
  }) =>
      isPlanFinished(
        status: status,
        endIso: toIsoDate(endDate),
        todayIso: toIsoDate(now),
      );

  @override
  State<FinishPlanCard> createState() => _FinishPlanCardState();
}

class _FinishPlanCardState extends State<FinishPlanCard> {
  bool _busy = false;

  Future<void> _finish() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await widget.training.finishPlan(widget.planId);
    } catch (e) {
      debugPrint('finish plan failed: $e');
      if (mounted) {
        setState(() => _busy = false);
        showTopBanner(context, l10n.planFinishFailed);
      }
      return;
    }
    if (!mounted) return;
    showTopBanner(context, l10n.planFinishDone(widget.planName));
    await widget.onFinished();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    return Card(
      key: const Key('finishPlanCard'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle_outline,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.planFinishTitle(widget.planName),
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.planFinishBody(
                            formatDateMed(widget.endDate, tag)),
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
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                key: const Key('finishPlanButton'),
                onPressed: _busy ? null : _finish,
                child: Text(
                    _busy ? l10n.planFinishFinishing : l10n.planFinishAction),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

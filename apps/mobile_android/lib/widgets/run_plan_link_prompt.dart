import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../preferences.dart';
import '../training.dart' show fmtHms, parseIsoDate, workoutKindFromDb;
import '../training_labels.dart';
import '../training_service.dart' show PlanWorkoutLinkCandidate;
import 'top_banner.dart';

/// Run-detail prompt for a planned workout done a day or two early or late.
/// Mirrors web `RunPlanWorkoutPrompt.svelte`.
///
/// The database links a run on its own local day only (decisions § 2079); a
/// workout within two days either side is asked about here and never linked
/// without a tap. "Not this one" moves on to the next candidate. The fetch is
/// an L4 effect: a failure shows nothing and never touches the rest of run
/// detail.
class RunPlanLinkPrompt extends StatefulWidget {
  final Future<List<PlanWorkoutLinkCandidate>> Function() load;
  final Future<void> Function(String workoutId) link;
  final VoidCallback? onLinked;

  const RunPlanLinkPrompt({
    super.key,
    required this.load,
    required this.link,
    this.onLinked,
  });

  @override
  State<RunPlanLinkPrompt> createState() => _RunPlanLinkPromptState();
}

class _RunPlanLinkPromptState extends State<RunPlanLinkPrompt> {
  List<PlanWorkoutLinkCandidate> _candidates = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final candidates = await widget.load();
      if (mounted) setState(() => _candidates = candidates);
    } catch (e) {
      debugPrint('RunPlanLinkPrompt: candidates failed: $e');
    }
  }

  Future<void> _confirm(PlanWorkoutLinkCandidate c) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await widget.link(c.workoutId);
      if (!mounted) return;
      setState(() => _candidates = const []);
      showTopBanner(context, l10n.planLinkLinked);
      widget.onLinked?.call();
    } catch (e) {
      debugPrint('RunPlanLinkPrompt: link failed: $e');
      if (mounted) showTopBanner(context, l10n.planLinkFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _target(PlanWorkoutLinkCandidate c) {
    final distance = c.targetDistanceM;
    if (distance != null && distance > 0) return formatDistanceForPref(distance);
    final duration = c.targetDurationSeconds;
    if (duration != null && duration > 0) return fmtHms(duration);
    return '';
  }

  @override
  Widget build(BuildContext context) {
    if (_candidates.isEmpty) return const SizedBox.shrink();
    final c = _candidates.first;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    final day = DateFormat.EEEE(tag).format(parseIsoDate(c.scheduledDate));
    final target = _target(c);
    final kind = workoutKindLabel(l10n, workoutKindFromDb(c.kind));

    return Card(
      key: const Key('plan-link-prompt'),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              c.dayOffset > 0
                  ? l10n.planLinkPromptEarly(day)
                  : l10n.planLinkPromptLate(day),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              target.isEmpty ? kind : '$kind · $target',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(
                          () => _candidates = _candidates.sublist(1)),
                  child: Text(l10n.planLinkDismiss),
                ),
                FilledButton(
                  onPressed: _busy ? null : () => _confirm(c),
                  child: Text(l10n.planLinkConfirm),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

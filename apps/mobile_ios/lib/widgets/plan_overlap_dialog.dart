import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';

import '../backend_timeout.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../training.dart';
import '../training_service.dart';

/// Asks what to do with the active plans a new plan's `[startIso, endIso]`
/// window overlaps, before any create path writes. Several plans may be
/// active when their windows don't overlap, so a plan queued before or after
/// the new one is left alone and never prompts.
///
/// Returns [PlanOverlapAction.replace] with no dialog when nothing overlaps,
/// the chosen action otherwise, or null when the runner keeps their plans.
/// "End <plan> on <date>" is offered only when [canTrimOverlap] holds. A
/// failed lookup (offline) proceeds rather than blocking creation: the
/// server-side constraint still refuses an overlapping write, and the
/// service maps that refusal to [ActivePlanExistsError].
Future<PlanOverlapAction?> confirmPlanOverlap(
  BuildContext context,
  TrainingService training, {
  required String startIso,
  required String endIso,
}) async {
  final List<TrainingPlanRow> overlapping;
  try {
    overlapping = overlappingActivePlans(
      await training.fetchActivePlans().timeout(kBackendLoadTimeout),
      startIso,
      endIso,
    )..sort((a, b) => a.startDate.compareTo(b.startDate));
  } catch (e) {
    debugPrint('confirmPlanOverlap: active plan lookup failed: $e');
    return PlanOverlapAction.replace;
  }
  if (overlapping.isEmpty) return PlanOverlapAction.replace;
  if (!context.mounted) return null;

  final l10n = AppLocalizations.of(context);
  final tag = localeToTag(Localizations.localeOf(context));
  String med(String iso) => formatDateMed(parseIsoDate(iso), tag);
  final trimmable = canTrimOverlap(overlapping, startIso);
  final trimEnd = med(dayBeforeIso(startIso));

  return showDialog<PlanOverlapAction>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return AlertDialog(
        title: Text(l10n.planOverlapTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.planOverlapBody(med(startIso), med(endIso))),
              const SizedBox(height: 8),
              for (final p in overlapping)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    l10n.planOverlapPlanLine(
                      p.name,
                      formatDateMed(p.startDate, tag),
                      formatDateMed(p.endDate, tag),
                    ),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                trimmable
                    ? l10n.planOverlapTrimHint(overlapping.single.name, trimEnd)
                    : l10n.planOverlapReplaceHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.planNewReplaceActiveKeep),
          ),
          if (trimmable)
            TextButton(
              key: const Key('planOverlapTrim'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: () => Navigator.pop(ctx, PlanOverlapAction.trim),
              child: Text(
                  l10n.planOverlapTrim(overlapping.single.name, trimEnd)),
            ),
          FilledButton(
            key: const Key('planOverlapReplace'),
            onPressed: () => Navigator.pop(ctx, PlanOverlapAction.replace),
            child: Text(l10n.planNewReplaceActiveConfirm),
          ),
        ],
      );
    },
  );
}

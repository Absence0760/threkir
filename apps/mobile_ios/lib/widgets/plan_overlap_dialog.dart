import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';

import '../backend_timeout.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../plan_overlap.dart';
import '../training.dart';
import '../training_service.dart';
import 'top_banner.dart';

/// Asks what to do with the active plans a new plan's `[startIso, endIso]`
/// window overlaps, before any create path writes. Several plans may be
/// active when their windows don't overlap, so a plan queued before or after
/// the new one is left alone and never prompts.
///
/// Returns [PlanOverlapAction.refuse] with no dialog when nothing overlaps
/// (so a plan created since this lookup is refused by the server rather than
/// replaced unasked, decisions § 2050), the chosen action otherwise, or null
/// when the runner keeps their plans. "End <plan> on <date>" is offered only
/// when [canTrimOverlap] holds. A failed lookup shows an error and returns
/// null: without knowing what overlaps there is nothing to ask the runner,
/// so nothing is created.
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
    if (context.mounted) {
      showTopBanner(
          context, AppLocalizations.of(context).planOverlapLookupFailed);
    }
    return null;
  }
  if (overlapping.isEmpty) return PlanOverlapAction.refuse;
  if (!context.mounted) return null;

  final l10n = AppLocalizations.of(context);
  final tag = localeToTag(Localizations.localeOf(context));
  String med(String iso) => formatDateMed(parseIsoDate(iso), tag);
  final trimmable =
      canTrimOverlap(overlapping, startIso, start: planRowStartIso);
  final trimEnd = med(dayBeforeIso(startIso));
  // Ending early trims every overlapped plan, not one of them, so the choice
  // names them all — the same list web's trimBlockedMessage gives.
  final trimmed = overlapping.map((p) => p.name).join(', ');

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
                    ? l10n.planOverlapTrimHint(trimmed, trimEnd)
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
                  l10n.planOverlapTrim(trimmed, trimEnd)),
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

/// The message a create or clone refused over overlapping plans shows: the
/// overlap refusal ([ActivePlanExistsError]) or the trim refusal
/// ([PlanTrimBlockedError]). Null for any other failure, which the caller
/// words itself.
String? planOverlapErrorText(BuildContext context, Object error) {
  final l10n = AppLocalizations.of(context);
  if (error is ActivePlanExistsError) return l10n.planOverlapConflict;
  if (error is PlanTrimBlockedError) {
    final tag = localeToTag(Localizations.localeOf(context));
    final date = formatDateMed(parseIsoDate(error.trimEndIso), tag);
    final name = error.planName;
    return name == null
        ? l10n.planOverlapTrimBlockedUnnamed(date)
        : l10n.planOverlapTrimBlocked(name, date);
  }
  return null;
}

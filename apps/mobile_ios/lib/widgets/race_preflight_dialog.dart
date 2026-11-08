import 'package:flutter/material.dart';

import '../course_gates.dart'
    show
        GateWhich,
        PreflightCode,
        PreflightIssue,
        PreflightSeverity,
        preflightBlocks;
import '../l10n/gen/app_localizations.dart';

/// One preflight issue as the race director reads it.
String preflightIssueText(
    AppLocalizations l10n, PreflightIssue issue, String course) {
  return switch (issue.code) {
    PreflightCode.noFinish => l10n.eventRacePreflightNoFinish(course),
    PreflightCode.noStart => l10n.eventRacePreflightNoStart(course),
    PreflightCode.selfCross => l10n.eventRacePreflightSelfCross(course),
    PreflightCode.gateFarFromRoute => issue.which == GateWhich.start
        ? l10n.eventRacePreflightFarStart(course)
        : l10n.eventRacePreflightFarFinish(course),
  };
}

/// The Arm preflight (#1305, decisions § 2390). True when the race should be
/// armed: no issues at all, or only warnings the director chose to arm
/// through. An error blocks, with nothing to choose but to close.
Future<bool> confirmRacePreflight(
  BuildContext context,
  List<PreflightIssue> issues,
  String Function(String courseId) courseName,
) async {
  if (issues.isEmpty) return true;
  final l10n = AppLocalizations.of(context);
  final blocked = preflightBlocks(issues);
  final shown = blocked
      ? issues.where((i) => i.severity == PreflightSeverity.error).toList()
      : issues;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('race-preflight-dialog'),
      title: Text(blocked
          ? l10n.eventRacePreflightBlockedTitle
          : l10n.eventRacePreflightTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final i in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      blocked ? Icons.error_outline : Icons.warning_amber,
                      size: 18,
                      color: blocked
                          ? Theme.of(ctx).colorScheme.error
                          : Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(preflightIssueText(
                          l10n, i, courseName(i.courseId))),
                    ),
                  ],
                ),
              ),
            Text(
              l10n.eventRacePreflightFixOnWeb,
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: blocked
          ? [
              TextButton(
                key: const Key('race-preflight-ok'),
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.eventRacePreflightOk),
              ),
            ]
          : [
              TextButton(
                key: const Key('race-preflight-cancel'),
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                key: const Key('race-preflight-arm'),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l10n.eventRaceArmAnyway),
              ),
            ],
    ),
  );
  return ok == true;
}

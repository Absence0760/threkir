import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../screens/help_screen.dart';

enum RaceStopChoice { resume, finish }

/// What Stop means during a live race: a pause, with the choice of carrying
/// on or finishing. The recording is already paused when this opens, and
/// dismissing it leaves it paused — the gun clock keeps running either way.
/// [coverageMet] false says up front that finishing now records a DNF.
Future<RaceStopChoice?> showRaceStopSheet(
  BuildContext context, {
  required bool coverageMet,
}) {
  return showModalBottomSheet<RaceStopChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => RaceStopSheet(coverageMet: coverageMet),
  );
}

class RaceStopSheet extends StatelessWidget {
  const RaceStopSheet({super.key, required this.coverageMet});

  final bool coverageMet;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.runRaceStopTitle, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(l10n.runRaceStopBody, style: theme.textTheme.bodyMedium),
              if (!coverageMet) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.runRaceStopBodyDnf,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const Key('race-stop-resume'),
                onPressed: () => Navigator.pop(context, RaceStopChoice.resume),
                icon: const Icon(Icons.play_arrow),
                label: Text(l10n.runRaceResume),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('race-stop-finish'),
                style: coverageMet
                    ? null
                    : OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                onPressed: () => Navigator.pop(context, RaceStopChoice.finish),
                icon: const Icon(Icons.sports_score),
                label: Text(
                  coverageMet ? l10n.runRaceFinish : l10n.runRaceFinishDnf,
                ),
              ),
              const SizedBox(height: 8),
              // Pausing to ask is the moment the rules matter, and the
              // recording stays paused while the guide is open.
              TextButton.icon(
                key: const Key('race-stop-help'),
                onPressed: () => openHelpForRoutes(context, const [
                  '/clubs/[slug]/events/[id]',
                ], audience: 'participant'),
                icon: const Icon(Icons.help_outline),
                label: Text(l10n.helpHowThisWorks),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

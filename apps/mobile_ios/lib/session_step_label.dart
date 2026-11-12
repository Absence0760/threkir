import 'l10n/gen/app_localizations.dart';
import 'session_steps.dart';

/// The display line for one expanded session step, web's `sessionStepLabel`:
/// the side word for a per-side item, then its reps, flow or hold seconds.
/// `expandSessionSteps` only carries the side and kind; the wording belongs
/// here so the plan screen and the event page read the same.
String sessionStepLabel(AppLocalizations l10n, SessionStep s) {
  final name = switch (s.side) {
    SessionSide.left => l10n.sessionSideLeft(s.movementName),
    SessionSide.right => l10n.sessionSideRight(s.movementName),
    null => s.movementName,
  };
  return switch (s.kind) {
    SessionItemKind.reps => l10n.sessionStepReps(name, s.reps ?? 0),
    SessionItemKind.flow => l10n.sessionStepFlow(name, s.durationS ?? 0),
    SessionItemKind.hold => l10n.sessionStepHold(name, s.durationS ?? 0),
  };
}

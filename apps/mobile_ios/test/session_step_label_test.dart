import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/session_step_label.dart';
import '../lib/session_steps.dart';

// One line per expanded session step, shared by the plan screen and the event
// page. Mirrors web's sessionStepLabel.
void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  SessionStep step(SessionItemKind kind,
          {String name = 'Pigeon', int? durationS, int? reps, SessionSide? side}) =>
      SessionStep(
        itemId: 'i1',
        movementName: name,
        kind: kind,
        durationS: durationS,
        reps: reps,
        tempo: null,
        cue: null,
        side: side,
        cumulativeS: 0,
      );

  test('a hold, a flow and a reps item each read their own measure', () {
    expect(sessionStepLabel(en, step(SessionItemKind.hold, durationS: 45)),
        'Pigeon · hold 45s');
    expect(sessionStepLabel(en, step(SessionItemKind.flow, durationS: 90)),
        'Pigeon · flow 90s');
    expect(sessionStepLabel(en, step(SessionItemKind.reps, reps: 12)),
        'Pigeon · 12 reps');
  });

  test('a per-side item names its side before the measure', () {
    expect(
        sessionStepLabel(
            en, step(SessionItemKind.hold, durationS: 30, side: SessionSide.left)),
        'Pigeon (Left) · hold 30s');
    expect(
        sessionStepLabel(
            en, step(SessionItemKind.reps, reps: 8, side: SessionSide.right)),
        'Pigeon (Right) · 8 reps');
  });

  test('a missing measure reads as zero rather than throwing', () {
    expect(sessionStepLabel(en, step(SessionItemKind.hold)), 'Pigeon · hold 0s');
    expect(sessionStepLabel(en, step(SessionItemKind.reps)), 'Pigeon · 0 reps');
  });

  test('every locale keeps the movement name and the number', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = lookupAppLocalizations(locale);
      for (final s in [
        step(SessionItemKind.hold, durationS: 45, side: SessionSide.left),
        step(SessionItemKind.flow, durationS: 90),
        step(SessionItemKind.reps, reps: 12, side: SessionSide.right),
      ]) {
        final label = sessionStepLabel(l10n, s);
        expect(label, contains('Pigeon'), reason: '$locale ${s.kind}');
        expect(label, contains('${s.durationS ?? s.reps}'),
            reason: '$locale ${s.kind}');
      }
      expect(
          sessionStepLabel(l10n,
              step(SessionItemKind.hold, durationS: 30, side: SessionSide.left)),
          isNot(sessionStepLabel(l10n,
              step(SessionItemKind.hold, durationS: 30, side: SessionSide.right))),
          reason: '$locale: left and right must read differently');
    }
  });
}

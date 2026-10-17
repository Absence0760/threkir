// Renders the workout summary out of the real catalogues. Mirrors
// apps/web/src/lib/training/workout_summary_format.test.ts.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/training.dart';
import '../lib/workout_summary.dart';
import '../lib/workout_summary_format.dart';

const week1 = WorkoutStructure(
  warmup: {'duration_s': 300, 'pace': 'easy'},
  repeats: {
    'count': 8,
    'duration_s': 60,
    'pace_sec_per_km': 420,
    'recovery_duration_s': 90,
    'recovery_pace': 'walk',
  },
  cooldown: {'duration_s': 300, 'pace': 'easy'},
);

const graduation = WorkoutStructure(
  repeats: {
    'count': 1,
    'duration_s': 1800,
    'pace_sec_per_km': 420,
    'recovery_duration_s': 90,
    'recovery_pace': 'walk',
  },
);

void main() {
  test('en: a week-1 walk-run reads as its pattern and its length', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final p = walkRunPattern(week1)!;
    expect(formatWalkRunPattern(l10n, p),
        '5 min warm-up, 8 × (1 min run / 90 s walk), 5 min cool-down');
    // 300 + 8 × 60 + 7 × 90 + 300 = 1710 s, 28.5 min rounds to 29.
    expect(formatWalkRunTotal(l10n, p), 'about 29 min');
  });

  test('en: the graduation week is one continuous run, no walk breaks', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(formatWalkRunPattern(l10n, walkRunPattern(graduation)!), '30 min run');
  });

  test('en: a Daniels code is named, free text is shown as typed', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(formatPaceZone(l10n, ' T ', paceZoneName(' T ')), 'Zone T · Tempo');
    expect(formatPaceZone(l10n, 'Z2', paceZoneName('Z2')), 'Zone Z2');
  });

  test('fr + pt-BR: the walk-run wording the translation review settled on',
      () {
    final fr = lookupAppLocalizations(const Locale('fr'));
    expect(fr.workoutEffortJog, 'footing');
    expect(formatWalkRunPattern(fr, walkRunPattern(week1)!),
        "5 min d'échauffement, 8 × (1 min de course / 90 s de marche), "
        '5 min de retour au calme');
    final ptBR = lookupAppLocalizations(const Locale('pt', 'BR'));
    expect(ptBR.workoutTaglineWalkRun, contains('caminhada-corrida'));
  });

  test('every locale renders the pattern with no unfilled placeholder', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = lookupAppLocalizations(locale);
      for (final s in [week1, graduation]) {
        final p = walkRunPattern(s)!;
        for (final out in [
          formatWalkRunPattern(l10n, p),
          formatWalkRunTotal(l10n, p),
        ]) {
          expect(out, isNot(matches(RegExp(r'[{}]'))), reason: '$locale: $out');
        }
      }
      expect(formatPaceZone(l10n, 'I', PaceZoneName.interval),
          isNot(matches(RegExp(r'[{}]'))));
    }
  });
}

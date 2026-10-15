import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';

/// Every string that tells an Android runner which location option to pick
/// must quote the one label Android itself shows in that language, or the
/// runner hunts Settings for an option that does not exist.
void main() {
  final androidLabel = {
    const Locale('en'): 'Allow all the time',
    const Locale('de'): 'Immer zulassen',
    const Locale('fr'): 'Toujours autoriser',
    const Locale('es'): 'Permitir todo el tiempo',
    const Locale('ja'): '常に許可',
    const Locale('pt'): 'Permitir sempre',
    const Locale('pt', 'BR'): 'Permitir o tempo todo',
  };

  for (final entry in androidLabel.entries) {
    test('${entry.key} quotes "${entry.value}" in every location string', () {
      final l10n = lookupAppLocalizations(entry.key);
      final strings = {
        'runBackgroundLocationNudgeBody': l10n.runBackgroundLocationNudgeBody,
        'runBackgroundLocationPaused': l10n.runBackgroundLocationPaused,
        'onboardingLocationBodyAndroid': l10n.onboardingLocationBodyAndroid,
      };
      for (final s in strings.entries) {
        expect(s.value, contains(entry.value), reason: s.key);
      }
    });
  }

  test('pt-PT names the option the way pt-PT Android does, not pt-BR', () {
    final pt = lookupAppLocalizations(const Locale('pt'));
    for (final s in [
      pt.runBackgroundLocationNudgeTitle,
      pt.runBackgroundLocationNudgeBody,
      pt.runBackgroundLocationPaused,
      pt.onboardingLocationBodyAndroid,
    ]) {
      expect(s, isNot(contains('tempo todo')));
    }
  });
}

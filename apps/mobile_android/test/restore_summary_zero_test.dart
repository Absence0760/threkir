// A restore summary names three counts, and a backup with no routes or no
// GPS tracks is ordinary. French and Portuguese put 0 in the `one` category,
// so without an `=0` branch "0 trajeto" and "0 itinéraire" read as singular.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';

void main() {
  final cases = {
    const Locale('fr'): ('aucune course', 'aucune trace', 'aucun itinéraire'),
    const Locale('pt'): ('0 corridas', '0 trajetos', '0 rotas'),
    const Locale('pt', 'BR'): ('0 corridas', '0 trajetos', '0 rotas'),
  };

  for (final MapEntry(key: locale, value: (runs, tracks, routes))
      in cases.entries) {
    test('$locale restore summaries read a zero count as zero', () {
      final l10n = lookupAppLocalizations(locale);
      for (final summary in [
        l10n.importStatusBackupRestored(0, 0, 0),
        l10n.settingsAccountRestoreDone(0, 0, 0, ''),
      ]) {
        expect(summary, contains(runs));
        expect(summary, contains(tracks));
        expect(summary, contains(routes));
      }
      expect(l10n.importStatusBackupRestored(1, 2, 1),
          isNot(contains('0 ')));
      expect(l10n.settingsAccountRestoreIncompleteArchive(0),
          isNot(contains('0 corrida ')));
    });
  }
}

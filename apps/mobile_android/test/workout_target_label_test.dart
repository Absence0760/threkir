import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/workout_target_label.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  group('rpeTargetLabel', () {
    test('reads each range shape', () {
      expect(rpeTargetLabel(en, 3, 4), 'Effort 3–4/10');
      expect(rpeTargetLabel(en, 6, 6), 'Effort 6/10');
      expect(rpeTargetLabel(en, null, 5), 'Effort up to 5/10');
      expect(rpeTargetLabel(en, 7, null), 'Effort 7/10 or harder');
    });

    test('no target is no label', () {
      expect(rpeTargetLabel(en, null, null), isNull);
    });
  });

  group('hrTargetLabel', () {
    test('reads each range shape', () {
      expect(hrTargetLabel(en, 140, 155), '140–155 bpm');
      expect(hrTargetLabel(en, 150, 150), '150 bpm');
      expect(hrTargetLabel(en, null, 125), 'Cap 125 bpm');
      expect(hrTargetLabel(en, 160, null), 'At least 160 bpm');
    });

    test('no target is no label', () {
      expect(hrTargetLabel(en, null, null), isNull);
    });
  });

  test('every locale renders every shape without throwing, and keeps the numbers',
      () {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = lookupAppLocalizations(locale);
      for (final (min, max) in [(3, 4), (6, 6), (null, 5), (7, null)]) {
        final rpe = rpeTargetLabel(l10n, min, max)!;
        for (final n in [min, max].whereType<int>()) {
          expect(rpe, contains('$n'), reason: '$locale rpe($min, $max)');
        }
      }
      for (final (min, max) in [(140, 155), (150, 150), (null, 125), (160, null)]) {
        final hr = hrTargetLabel(l10n, min, max)!;
        for (final n in [min, max].whereType<int>()) {
          expect(hr, contains('$n'), reason: '$locale hr($min, $max)');
        }
      }
    }
  });
}

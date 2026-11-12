import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/plan_parse_message.dart';
import '../lib/plan_serialize.dart';

void main() {
  const params = {
    'cell': 'CELL',
    'column': 'COLUMN',
    'name': 'NAME',
    'max': '120',
    'date': '2026-07-05',
    'kind': 'easy',
    'start': '2026-07-06',
    'value': 'VALUE',
  };

  test('every refusal code reads in every locale, carrying its cells', () {
    final en = lookupAppLocalizations(const Locale('en'));
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = lookupAppLocalizations(locale);
      for (final code in PlanParseCode.values) {
        final e = PlanParseError(code, params, 'English message');
        final text = planParseErrorMessage(l10n, e);
        expect(text, isNotEmpty, reason: '$locale $code');
        expect(text, isNot(contains('English message')),
            reason: '$locale $code shows the parser message');
        if (locale.languageCode != 'en') {
          expect(text, isNot(planParseErrorMessage(en, e)),
              reason: '$locale $code is still English');
        }
      }
    }
  });

  test('a cell the parser could not read is named in the reason', () {
    final en = lookupAppLocalizations(const Locale('en'));
    expect(
        planParseErrorMessage(
            en,
            const PlanParseError(
                PlanParseCode.badDate, {'cell': '07/05/2026'}, 'Bad date')),
        'Couldn\'t read the date "07/05/2026". Use YYYY-MM-DD.');
    expect(
        planParseErrorMessage(
            en,
            const PlanParseError(PlanParseCode.beforeStart,
                {'date': '2027-03-07', 'start': '2027-03-08'}, 'x')),
        contains('2027-03-07'));
  });
}

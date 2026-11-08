import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/route_surface_label.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  test('the three stored surfaces read in the runner\'s language', () {
    expect(routeSurfaceLabel(en, 'road'), 'Road');
    expect(routeSurfaceLabel(en, 'trail'), 'Trail');
    expect(routeSurfaceLabel(en, 'mixed'), 'Mixed');
  });

  test('an unknown token is shown verbatim in every locale, never guessed', () {
    // A token this client doesn't know can only come from a newer database;
    // a prettified guess or a silent "Road" would read as a real translation.
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = lookupAppLocalizations(locale);
      expect(routeSurfaceLabel(l10n, 'gravel'), 'gravel', reason: '$locale');
      expect(routeSurfaceLabel(l10n, ''), '', reason: '$locale');
      expect(routeSurfaceLabel(l10n, 'Road'), 'Road',
          reason: 'tokens are lowercase; "Road" is not "road" ($locale)');
    }
  });

  test('each known surface has its own label in every locale', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = lookupAppLocalizations(locale);
      final labels = {
        for (final s in ['road', 'trail', 'mixed']) routeSurfaceLabel(l10n, s),
      };
      expect(labels, hasLength(3), reason: '$locale');
    }
  });
}

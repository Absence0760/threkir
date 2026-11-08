import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/club_role_labels.dart';
import '../lib/l10n/gen/app_localizations.dart';

void main() {
  test('the assignable roles are the four web offers, in its order, never owner',
      () {
    expect(assignableClubRoles,
        ['admin', 'event_organiser', 'race_director', 'member']);
    expect(assignableClubRoles, isNot(contains('owner')),
        reason: 'ownership moves only through a club transfer');
  });

  test('every role has its own label in every locale', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = lookupAppLocalizations(locale);
      expect(clubRoleLabel(l10n, 'owner'), l10n.clubRoleOwner);
      expect(clubRoleLabel(l10n, 'admin'), l10n.clubRoleAdmin);
      expect(clubRoleLabel(l10n, 'event_organiser'), l10n.clubRoleEventOrganiser);
      expect(clubRoleLabel(l10n, 'race_director'), l10n.clubRoleRaceDirector);
      expect(clubRoleLabel(l10n, 'member'), l10n.clubRoleMember);
      final labels = {
        for (final r in ['owner', ...assignableClubRoles]) clubRoleLabel(l10n, r),
      };
      expect(labels, hasLength(5), reason: '$locale');
    }
  });

  test('an unknown role reads as a plain member', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(clubRoleLabel(l10n, 'moderator'), l10n.clubRoleMember);
    expect(clubRoleLabel(l10n, ''), l10n.clubRoleMember);
  });
}

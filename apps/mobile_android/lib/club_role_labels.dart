import 'l10n/gen/app_localizations.dart';

/// The roles an admin can hand out from the roster. `owner` is not one of
/// them: ownership moves only through a club transfer. Web's role `<select>`
/// offers the same four in the same order.
const List<String> assignableClubRoles = [
  'admin',
  'event_organiser',
  'race_director',
  'member',
];

/// The display label for a `club_members.role` value. Mirrors web's
/// `clubRoleLabel`; an unknown value reads as a plain member.
String clubRoleLabel(AppLocalizations l10n, String role) {
  switch (role) {
    case 'owner':
      return l10n.clubRoleOwner;
    case 'admin':
      return l10n.clubRoleAdmin;
    case 'event_organiser':
      return l10n.clubRoleEventOrganiser;
    case 'race_director':
      return l10n.clubRoleRaceDirector;
    case 'member':
    default:
      return l10n.clubRoleMember;
  }
}

import 'package:core_models/core_models.dart' show IntegrationRow;

/// The runner's UltraSignup person: who they are on UltraSignup, as Settings
/// stores it and the race import sends it (decisions § 1841). Mirrors
/// `apps/web/src/lib/integrations/ultrasignup_person.ts`.
///
/// UltraSignup's results feed is keyed by NAME and answers with every
/// same-named person, so an import needs the name AND the `Id` the runner
/// picked out of the people it returns. The Edge Function owns the validation;
/// this reads its answers defensively and turns the stored `integrations` row
/// back into a link.

/// The longest name part the Edge Function sends, and the
/// `integrations.external_*_name` CHECK (20270726000003).
const int ultraSignUpNameMaxLen = 60;

/// The token `integrations.provider` and `race-results-import` both use.
const String ultraSignUpProvider = 'ultrasignup';

final RegExp _id = RegExp(r'^[1-9][0-9]{0,11}$');
final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

class UltraSignUpRecentEvent {
  final String name;

  /// `YYYY-MM-DD`, or null where UltraSignup gave no readable date.
  final String? date;

  const UltraSignUpRecentEvent({required this.name, this.date});
}

/// One person UltraSignup knows by the name looked up.
class UltraSignUpCandidate {
  final String id;
  final String firstName;
  final String lastName;

  /// Null where UltraSignup does not know it.
  final int? age;
  final int resultCount;
  final List<UltraSignUpRecentEvent> recentEvents;

  const UltraSignUpCandidate({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.age,
    required this.resultCount,
    required this.recentEvents,
  });
}

/// The person a runner picked, as the import sends it.
class UltraSignUpPersonLink {
  final String personId;
  final String firstName;
  final String lastName;

  const UltraSignUpPersonLink({
    required this.personId,
    required this.firstName,
    required this.lastName,
  });

  @override
  bool operator ==(Object other) =>
      other is UltraSignUpPersonLink &&
      other.personId == personId &&
      other.firstName == firstName &&
      other.lastName == lastName;

  @override
  int get hashCode => Object.hash(personId, firstName, lastName);
}

String _str(Object? v) => v is String ? v.trim() : '';

/// Whether a name can be looked up: both halves present and within the cap,
/// counted in code points as web counts them. Only the shape the form can see —
/// the function decides the rest and answers `ultrasignup_name_required` when
/// it disagrees.
bool ultraSignUpNameReady(String firstName, String lastName) {
  bool ok(String s) {
    final t = s.trim();
    return t.isNotEmpty && t.runes.length <= ultraSignUpNameMaxLen;
  }

  return ok(firstName) && ok(lastName);
}

/// The lookup's `candidates`, keeping only rows that could be stored: a person
/// without a usable id or name could never be linked, so offering them would
/// only fail one step later. Anything that is not the expected envelope is no
/// candidates rather than a guess.
List<UltraSignUpCandidate> parseUltraSignUpCandidates(Object? payload) {
  final rows = payload is Map ? payload['candidates'] : null;
  if (rows is! List) return const [];
  final out = <UltraSignUpCandidate>[];
  for (final raw in rows) {
    if (raw is! Map) continue;
    final id = _str(raw['id']);
    final firstName = _str(raw['firstName']);
    final lastName = _str(raw['lastName']);
    if (!_id.hasMatch(id) || firstName.isEmpty || lastName.isEmpty) continue;
    final age = raw['age'];
    final count = raw['resultCount'];
    final events = raw['recentEvents'];
    out.add(UltraSignUpCandidate(
      id: id,
      firstName: firstName,
      lastName: lastName,
      age: age is int && age > 0 ? age : null,
      resultCount: count is int && count >= 0 ? count : 0,
      recentEvents: [
        if (events is List)
          for (final e in events)
            if (e is Map && _str(e['name']).isNotEmpty)
              UltraSignUpRecentEvent(
                name: _str(e['name']),
                date: _isoDate.hasMatch(_str(e['date'])) ? _str(e['date']) : null,
              ),
      ],
    ));
  }
  return out;
}

/// The link a picked candidate becomes. UltraSignup's own spelling of the name
/// is kept, not the runner's typing — it is the spelling the feed answered to.
UltraSignUpPersonLink linkFromCandidate(UltraSignUpCandidate c) =>
    UltraSignUpPersonLink(
        personId: c.id, firstName: c.firstName, lastName: c.lastName);

/// The stored `integrations` row as a link, or null when there is none, it
/// belongs to another provider, or it is not a whole one.
UltraSignUpPersonLink? ultraSignUpLinkFromRow(IntegrationRow? row) {
  if (row == null || row.provider != ultraSignUpProvider) return null;
  final personId = _str(row.externalId);
  final firstName = _str(row.externalFirstName);
  final lastName = _str(row.externalLastName);
  if (!_id.hasMatch(personId) || firstName.isEmpty || lastName.isEmpty) {
    return null;
  }
  return UltraSignUpPersonLink(
      personId: personId, firstName: firstName, lastName: lastName);
}

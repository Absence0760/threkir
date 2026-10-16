/// The `strava-clubs` Edge Function's answers, graded rather than cast
/// (decisions § 1959), and the hand-off from a Strava club to the create form.
///
/// TS↔Dart parity pair with `apps/web/src/lib/integrations/strava_clubs.ts`.
/// Lives in the SHARED core_models package because `api_client` consumes it,
/// so it needs no iOS-twin mirror. Two web helpers have no half here: the
/// `strava_club` URL parameter (`parseStravaClubParam`) because the phone
/// hands the id to the form directly, and the length clamps on the prefill,
/// which the form applies against `text_limits.dart` exactly as web's
/// `/clubs/new` re-clamps what it reads from the URL.
library;

class StravaLinkedClub {
  const StravaLinkedClub({
    required this.id,
    required this.slug,
    required this.name,
  });

  final String id;
  final String slug;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is StravaLinkedClub &&
      other.id == id &&
      other.slug == slug &&
      other.name == name;

  @override
  int get hashCode => Object.hash(id, slug, name);
}

class StravaClub {
  const StravaClub({
    required this.stravaClubId,
    required this.name,
    this.city,
    this.state,
    this.country,
    this.sportType,
    this.memberCount,
    this.viewerIsAdmin,
    this.linkedClub,
  });

  final int stravaClubId;
  final String name;
  final String? city;
  final String? state;
  final String? country;
  final String? sportType;
  final int? memberCount;

  /// Strava said whether the viewer administers this club; null when the
  /// list did not carry it. The link action asks Strava again either way.
  final bool? viewerIsAdmin;
  final StravaLinkedClub? linkedClub;

  StravaClub withLinkedClub(StravaLinkedClub? linked) => StravaClub(
        stravaClubId: stravaClubId,
        name: name,
        city: city,
        state: state,
        country: country,
        sportType: sportType,
        memberCount: memberCount,
        viewerIsAdmin: viewerIsAdmin,
        linkedClub: linked,
      );

  @override
  bool operator ==(Object other) =>
      other is StravaClub &&
      other.stravaClubId == stravaClubId &&
      other.name == name &&
      other.city == city &&
      other.state == state &&
      other.country == country &&
      other.sportType == sportType &&
      other.memberCount == memberCount &&
      other.viewerIsAdmin == viewerIsAdmin &&
      other.linkedClub == linkedClub;

  @override
  int get hashCode => Object.hash(stravaClubId, name, city, state, country,
      sportType, memberCount, viewerIsAdmin, linkedClub);
}

enum StravaClubsStatus { connected, notConnected, reconnectRequired }

class StravaClubsResult {
  const StravaClubsResult(this.status, [this.clubs = const []]);

  final StravaClubsStatus status;

  /// Empty unless [status] is [StravaClubsStatus.connected].
  final List<StravaClub> clubs;
}

const int _maxSafeInteger = 9007199254740991;

String? _str(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

/// A whole number in JS's safe-integer range, so a `12.0` JSON number reads
/// the way web's `Number.isSafeInteger` reads it.
int? _safeInt(Object? v) {
  if (v is int) return v.abs() <= _maxSafeInteger ? v : null;
  if (v is double && v.isFinite && v == v.truncateToDouble()) {
    return v.abs() <= _maxSafeInteger ? v.toInt() : null;
  }
  return null;
}

StravaLinkedClub? _parseLinked(Object? v) {
  if (v is! Map) return null;
  final id = _str(v['id']);
  final slug = _str(v['slug']);
  final name = _str(v['name']);
  return id != null && slug != null && name != null
      ? StravaLinkedClub(id: id, slug: slug, name: name)
      : null;
}

StravaClub? _parseClub(Object? v) {
  if (v is! Map) return null;
  final id = _safeInt(v['strava_club_id']);
  final name = _str(v['name']);
  if (id == null || id <= 0 || name == null) return null;
  final members = _safeInt(v['member_count']);
  final admin = v['viewer_is_admin'];
  return StravaClub(
    stravaClubId: id,
    name: name,
    city: _str(v['city']),
    state: _str(v['state']),
    country: _str(v['country']),
    sportType: _str(v['sport_type']),
    memberCount: members != null && members >= 0 ? members : null,
    viewerIsAdmin: admin is bool ? admin : null,
    linkedClub: _parseLinked(v['linked_club']),
  );
}

/// A body that is not one of the three shapes throws, so the section shows
/// its error rather than an empty "you're in no clubs" it was never told.
StravaClubsResult parseStravaClubsResult(Object? data) {
  final r = data is Map ? data : const <String, Object?>{};
  final status = r['status'];
  if (status == 'not_connected') {
    return const StravaClubsResult(StravaClubsStatus.notConnected);
  }
  if (status == 'reconnect_required') {
    return const StravaClubsResult(StravaClubsStatus.reconnectRequired);
  }
  final clubs = r['clubs'];
  if (status == 'connected' && clubs is List) {
    return StravaClubsResult(
      StravaClubsStatus.connected,
      clubs.map(_parseClub).whereType<StravaClub>().toList(growable: false),
    );
  }
  throw const FormatException('unexpected_response');
}

/// "Richmond, Virginia, United States" — whatever parts Strava filled in, in
/// that order, with an exact repeat dropped (a city-state names itself twice).
String stravaClubLocation({String? city, String? state, String? country}) {
  final parts = <String>[];
  for (final p in [city, state, country]) {
    if (p != null && p.isNotEmpty && !parts.contains(p)) parts.add(p);
  }
  return parts.join(', ');
}

/// What "Set up on Threkir" hands the create form: the club's name and place
/// to prefill, and its id so the new club is linked once it exists.
typedef StravaClubSetup = ({String name, String location, int stravaClubId});

StravaClubSetup stravaClubSetup(StravaClub club) => (
      name: club.name,
      location: stravaClubLocation(
          city: club.city, state: club.state, country: club.country),
      stravaClubId: club.stravaClubId,
    );

/// The edge function's refusal codes the clubs screen explains in words.
enum StravaClubLinkError {
  stravaAdminRequired,
  stravaClubAlreadyLinked,
  notClubAdmin,
  reconnect,
  generic,
}

StravaClubLinkError stravaClubLinkError(String? code) {
  switch (code) {
    case 'strava_admin_required':
      return StravaClubLinkError.stravaAdminRequired;
    case 'strava_club_already_linked':
      return StravaClubLinkError.stravaClubAlreadyLinked;
    case 'not_club_admin':
      return StravaClubLinkError.notClubAdmin;
    case 'refresh_failed':
    case 'strava_not_connected':
      return StravaClubLinkError.reconnect;
    default:
      return StravaClubLinkError.generic;
  }
}

/// A link or unlink the server refused, naming which refusal.
class StravaClubLinkFailure implements Exception {
  const StravaClubLinkFailure(this.reason);

  final StravaClubLinkError reason;

  @override
  String toString() => 'StravaClubLinkFailure(${reason.name})';
}

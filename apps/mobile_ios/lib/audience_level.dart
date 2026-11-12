/// Who can see a run or a route, as the owner chooses it and as the row
/// stores it (decisions § 1874). The Dart half of the web
/// `social/run_visibility.ts` parity pair.
///
/// `is_public` is Public, `followers_only` is Followers, a live grant in
/// `run_shares` / `route_shares` is Specific people, and none of them is Only
/// me. `is_public` wins over the other two, which the server's normalize
/// trigger also enforces. Choosing Only me revokes every grant, because "only
/// me" with a named reader left in place would be a lie; the wider levels
/// leave grants in place.
library;

enum AudienceLevel { private, followers, specific, public }

const List<AudienceLevel> audienceLevels = AudienceLevel.values;

/// The two stored columns a level writes. Specific people is a private row
/// plus grants, so it writes the same columns as Only me.
class AudienceColumns {
  final bool isPublic;
  final bool followersOnly;

  const AudienceColumns({required this.isPublic, required this.followersOnly});

  @override
  bool operator ==(Object other) =>
      other is AudienceColumns &&
      other.isPublic == isPublic &&
      other.followersOnly == followersOnly;

  @override
  int get hashCode => Object.hash(isPublic, followersOnly);

  @override
  String toString() =>
      'AudienceColumns(isPublic: $isPublic, followersOnly: $followersOnly)';
}

AudienceColumns audienceColumns(AudienceLevel level) => AudienceColumns(
      isPublic: level == AudienceLevel.public,
      followersOnly: level == AudienceLevel.followers,
    );

/// The level a row is at. [shareCount] only decides between Only me and
/// Specific people: a grant on a public or followers-only entity changes
/// nothing the owner can see from the level.
AudienceLevel audienceOf({
  required bool? isPublic,
  bool? followersOnly,
  required int shareCount,
}) {
  if (isPublic == true) return AudienceLevel.public;
  if (followersOnly == true) return AudienceLevel.followers;
  return shareCount > 0 ? AudienceLevel.specific : AudienceLevel.private;
}

/// The universal `privacy_default` preference, mapped to the columns a new
/// run is written with. `followers` writes `followers_only` instead of
/// collapsing to owner-only; the server stores it owner-only until audience
/// sharing is switched on (§ 1875). Unknown values fail closed.
AudienceColumns privacyDefaultToAudience(String? pref) {
  if (pref == 'public') return audienceColumns(AudienceLevel.public);
  if (pref == 'followers') return audienceColumns(AudienceLevel.followers);
  return audienceColumns(AudienceLevel.private);
}

/// Whether choosing [next] has to revoke grants first. Only me is the one
/// level that promises no named reader is left.
bool levelRevokesGrants(AudienceLevel next) => next == AudienceLevel.private;

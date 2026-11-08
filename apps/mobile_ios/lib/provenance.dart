/// Where a piece of content came from, as the four labels of issue #1190
/// (decisions § 2406): published by the verified organiser, from a data
/// partner or provider sync, traced from the race's published map, or the
/// community. Every input is a server-derived fact no client can write
/// (`is_official` and `organiser_is_official`, both from the club's current
/// verification), so this only classifies; it never decides trust.
///
/// Parity pair with apps/web/src/lib/social/provenance.ts; both read
/// fixtures/provenance_cases.json.
enum Provenance { official, verifiedSource, traced, community }

/// The wire token for each kind, as the shared fixture spells it.
const Map<Provenance, String> provenanceTokens = {
  Provenance.official: 'official',
  Provenance.verifiedSource: 'verified_source',
  Provenance.traced: 'traced',
  Provenance.community: 'community',
};

const List<Provenance> provenanceKinds = [
  Provenance.official,
  Provenance.verifiedSource,
  Provenance.traced,
  Provenance.community,
];

/// A route, plan, gym routine, challenge or session plan.
Provenance contentProvenance(bool? isOfficial) =>
    isOfficial == true ? Provenance.official : Provenance.community;

/// A race listing. The organiser outranks the provider it was synced from; a
/// hand-added (`manual`) listing is never a partner source.
Provenance raceListingProvenance({
  required bool? organiserIsOfficial,
  required String? provider,
  required bool? isVerified,
}) {
  if (organiserIsOfficial == true) return Provenance.official;
  if (provider != null &&
      provider.isNotEmpty &&
      provider != 'manual' &&
      isVerified == true) {
    return Provenance.verifiedSource;
  }
  return Provenance.community;
}

/// The course linked to a race listing, or null when there is none. Only a
/// club that is verified right now vouches for a course.
Provenance? raceCourseProvenance({
  required bool hasCourse,
  required bool? organiserIsOfficial,
  required String? courseSource,
}) {
  if (!hasCourse) return null;
  if (organiserIsOfficial != true) return Provenance.community;
  if (courseSource == 'official') return Provenance.official;
  if (courseSource == 'traced') return Provenance.traced;
  return Provenance.community;
}

/// Whether a card shows a badge: everything but community, which is the
/// default and needs no mark.
bool provenanceShowsBadge(Provenance kind) => kind != Provenance.community;

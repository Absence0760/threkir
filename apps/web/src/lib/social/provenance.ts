// Where a piece of content came from, as the four labels of issue #1190
// (decisions § 2406): published by the verified organiser, from a data
// partner or provider sync, traced from the race's published map, or the
// community. Every input is a server-derived fact no client can write
// (`is_official` and `organiser_is_official`, both from the club's current
// verification), so this only classifies; it never decides trust.
//
// Parity pair with apps/mobile_android/lib/provenance.dart; both read
// fixtures/provenance_cases.json.

export type Provenance = 'official' | 'verified_source' | 'traced' | 'community';

export const PROVENANCE_KINDS: readonly Provenance[] = ['official', 'verified_source', 'traced', 'community'];

/// A route, plan, gym routine, challenge or session plan.
export function contentProvenance(isOfficial: boolean | null | undefined): Provenance {
	return isOfficial === true ? 'official' : 'community';
}

export interface ListingProvenanceInput {
	organiserIsOfficial: boolean | null | undefined;
	provider: string | null | undefined;
	isVerified: boolean | null | undefined;
}

/// A race listing. The organiser outranks the provider it was synced from; a
/// hand-added (`manual`) listing is never a partner source.
export function raceListingProvenance(input: ListingProvenanceInput): Provenance {
	if (input.organiserIsOfficial === true) return 'official';
	if (input.provider && input.provider !== 'manual' && input.isVerified === true) return 'verified_source';
	return 'community';
}

export interface CourseProvenanceInput {
	hasCourse: boolean;
	organiserIsOfficial: boolean | null | undefined;
	courseSource: string | null | undefined;
}

/// The course linked to a race listing, or null when there is none. Only a
/// club that is verified right now vouches for a course.
export function raceCourseProvenance(input: CourseProvenanceInput): Provenance | null {
	if (!input.hasCourse) return null;
	if (input.organiserIsOfficial !== true) return 'community';
	if (input.courseSource === 'official') return 'official';
	if (input.courseSource === 'traced') return 'traced';
	return 'community';
}

/// Whether a card shows a badge: everything but community, which is the
/// default and needs no mark.
export function provenanceShowsBadge(kind: Provenance): boolean {
	return kind !== 'community';
}

// Which race-course actions the signed-in runner is offered (decisions § 2381).
//
// The RPCs are the gate; this only decides which buttons to show, from the
// same facts `private.is_official_publisher` reads: an ACTIVE owner/admin of a
// club that is verified, public and not moderated away. Mobile's
// `raceCourseAccess` in race_service.dart answers the same way.

export interface OrganiserClubCandidate {
	id: string;
	name: string;
	slug: string | null;
}

export interface ClubMembershipFacts {
	id: string;
	name: string;
	slug: string | null;
	is_verified: boolean | null;
	is_public: boolean | null;
	shadow_hidden: boolean | null;
	viewer_role: string | null;
	viewer_status: string | null;
}

/// The clubs the runner can claim a race or link a course for.
export function organiserClubsOf(clubs: readonly ClubMembershipFacts[]): OrganiserClubCandidate[] {
	return clubs
		.filter(
			(c) =>
				c.is_verified === true &&
				c.is_public === true &&
				c.shadow_hidden !== true &&
				c.viewer_status === 'active' &&
				(c.viewer_role === 'owner' || c.viewer_role === 'admin'),
		)
		.map((c) => ({ id: c.id, name: c.name, slug: c.slug }));
}

export interface RaceCourseAccess {
	/// Unclaimed, and the runner administers a verified club.
	canClaim: boolean;
	/// The runner administers the race's organiser club: link, re-check,
	/// remove the course, approve or reject suggestions.
	canManage: boolean;
	/// Signed in and not a manager: may suggest a course.
	canSuggest: boolean;
}

export function raceCourseAccess(input: {
	signedIn: boolean;
	organiserClubId: string | null;
	myOrganiserClubs: readonly OrganiserClubCandidate[];
}): RaceCourseAccess {
	const { signedIn, organiserClubId, myOrganiserClubs } = input;
	if (!signedIn) return { canClaim: false, canManage: false, canSuggest: false };
	const canManage =
		organiserClubId != null && myOrganiserClubs.some((c) => c.id === organiserClubId);
	const canClaim = organiserClubId == null && myOrganiserClubs.length > 0;
	return { canClaim, canManage, canSuggest: !canManage };
}

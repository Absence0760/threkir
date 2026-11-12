import { test } from 'node:test';
import assert from 'node:assert/strict';
import { organiserClubsOf, raceCourseAccess, type ClubMembershipFacts } from './race_course_access';

const club = (over: Partial<ClubMembershipFacts>): ClubMembershipFacts => ({
	id: 'c1',
	name: 'Richmond Marathon',
	slug: 'richmond-marathon',
	is_verified: true,
	is_public: true,
	shadow_hidden: false,
	viewer_role: 'owner',
	viewer_status: 'active',
	...over,
});

test('organiserClubsOf keeps an active owner or admin of a public, verified, visible club', () => {
	const kept = organiserClubsOf([
		club({ id: 'owner' }),
		club({ id: 'admin', viewer_role: 'admin' }),
		club({ id: 'member', viewer_role: 'member' }),
		club({ id: 'organiser', viewer_role: 'event_organiser' }),
		club({ id: 'pending', viewer_status: 'pending' }),
		club({ id: 'unverified', is_verified: false }),
		club({ id: 'private', is_public: false }),
		club({ id: 'hidden', shadow_hidden: true }),
	]);
	assert.deepEqual(
		kept.map((c) => c.id),
		['owner', 'admin'],
	);
	assert.deepEqual(kept[0], { id: 'owner', name: 'Richmond Marathon', slug: 'richmond-marathon' });
});

test('raceCourseAccess offers a claim only on an unclaimed race to a verified-club admin', () => {
	const mine = [{ id: 'c1', name: 'A', slug: null }];
	assert.deepEqual(raceCourseAccess({ signedIn: true, organiserClubId: null, myOrganiserClubs: mine }), {
		canClaim: true,
		canManage: false,
		canSuggest: true,
	});
	assert.deepEqual(raceCourseAccess({ signedIn: true, organiserClubId: null, myOrganiserClubs: [] }), {
		canClaim: false,
		canManage: false,
		canSuggest: true,
	});
});

test('raceCourseAccess lets the organiser club manage, and another club only suggest', () => {
	const mine = [{ id: 'c1', name: 'A', slug: null }];
	assert.deepEqual(raceCourseAccess({ signedIn: true, organiserClubId: 'c1', myOrganiserClubs: mine }), {
		canClaim: false,
		canManage: true,
		canSuggest: false,
	});
	assert.deepEqual(raceCourseAccess({ signedIn: true, organiserClubId: 'c2', myOrganiserClubs: mine }), {
		canClaim: false,
		canManage: false,
		canSuggest: true,
	});
});

test('raceCourseAccess offers nothing to a signed-out visitor', () => {
	assert.deepEqual(
		raceCourseAccess({ signedIn: false, organiserClubId: null, myOrganiserClubs: [{ id: 'c1', name: 'A', slug: null }] }),
		{ canClaim: false, canManage: false, canSuggest: false },
	);
});

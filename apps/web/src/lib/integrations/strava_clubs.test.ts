import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { TEXT_LIMITS } from '../core/text_limits.ts';
import {
	parseStravaClubParam,
	parseStravaClubsResult,
	prefilledClubLocation,
	stravaClubLinkError,
	stravaClubLocation,
	stravaClubSetupHref,
} from './strava_clubs.ts';

const WIRE = {
	strava_club_id: 101,
	name: 'Richmond Run Club',
	city: 'Richmond',
	state: 'Virginia',
	country: 'United States',
	sport_type: 'running',
	member_count: 42,
	profile_url: 'https://dgalywyr863hv.cloudfront.net/x.jpg',
	viewer_is_admin: true,
	linked_club: { id: 'c-1', slug: 'richmond-run-club', name: 'Richmond RC' },
};

test('a connected answer is graded club by club', () => {
	const r = parseStravaClubsResult({
		status: 'connected',
		clubs: [WIRE, { ...WIRE, strava_club_id: 'x' }, { strava_club_id: 7, name: 'Seven', viewer_is_admin: 'yes' }],
	});
	assert.equal(r.status, 'connected');
	if (r.status !== 'connected') return;
	assert.equal(r.clubs.length, 2);
	assert.deepEqual(r.clubs[0], {
		stravaClubId: 101,
		name: 'Richmond Run Club',
		city: 'Richmond',
		state: 'Virginia',
		country: 'United States',
		sportType: 'running',
		memberCount: 42,
		viewerIsAdmin: true,
		linkedClub: { id: 'c-1', slug: 'richmond-run-club', name: 'Richmond RC' },
	});
	assert.equal(r.clubs[1].viewerIsAdmin, null);
	assert.equal(r.clubs[1].linkedClub, null);
	assert.equal(r.clubs[1].memberCount, null);
});

test('not connected and a dead grant are answers, not errors', () => {
	assert.deepEqual(parseStravaClubsResult({ status: 'not_connected' }), { status: 'not_connected' });
	assert.deepEqual(parseStravaClubsResult({ status: 'reconnect_required' }), { status: 'reconnect_required' });
});

test('a body in none of the three shapes throws rather than reading as "no clubs"', () => {
	assert.throws(() => parseStravaClubsResult(null));
	assert.throws(() => parseStravaClubsResult({ status: 'connected' }));
	assert.throws(() => parseStravaClubsResult({ clubs: [] }));
});

test('the location joins what Strava filled in and drops an exact repeat', () => {
	assert.equal(stravaClubLocation({ city: 'Richmond', state: 'Virginia', country: 'United States' }), 'Richmond, Virginia, United States');
	assert.equal(stravaClubLocation({ city: 'Singapore', state: 'Singapore', country: 'Singapore' }), 'Singapore');
	assert.equal(stravaClubLocation({ city: null, state: null, country: 'France' }), 'France');
	assert.equal(stravaClubLocation({ city: null, state: null, country: null }), '');
});

test('setting up a Strava club on Threkir carries its name, place and id to the form', () => {
	const href = stravaClubSetupHref({ stravaClubId: 101, name: 'Run & Done', city: 'Leeds', state: null, country: 'United Kingdom' });
	const url = new URL(href, 'https://threkir.test');
	assert.equal(url.pathname, '/clubs/new');
	assert.equal(url.searchParams.get('name'), 'Run & Done');
	assert.equal(url.searchParams.get('location'), 'Leeds, United Kingdom');
	assert.equal(url.searchParams.get('strava_club'), '101');
	const bare = new URL(stravaClubSetupHref({ stravaClubId: 5, name: 'X', city: null, state: null, country: null }), 'https://threkir.test');
	assert.equal(bare.searchParams.has('location'), false);
});

test('the prefilled location is held to the column bound', () => {
	const long = 'a'.repeat(TEXT_LIMITS.clubLocationLabel + 20);
	assert.equal(prefilledClubLocation(long).length, TEXT_LIMITS.clubLocationLabel);
	assert.equal(prefilledClubLocation('  Leeds  '), 'Leeds');
	assert.equal(prefilledClubLocation(null), '');
});

test('only a positive integer survives as a Strava club id from the URL', () => {
	assert.equal(parseStravaClubParam('101'), 101);
	for (const bad of [null, '', '0', '-3', '1.5', '01', 'abc', '1e3', '99999999999999999']) {
		assert.equal(parseStravaClubParam(bad), null, String(bad));
	}
});

test('each link refusal maps to the sentence that explains it', () => {
	assert.equal(stravaClubLinkError('strava_admin_required'), 'strava_admin_required');
	assert.equal(stravaClubLinkError('strava_club_already_linked'), 'strava_club_already_linked');
	assert.equal(stravaClubLinkError('not_club_admin'), 'not_club_admin');
	assert.equal(stravaClubLinkError('refresh_failed'), 'reconnect');
	assert.equal(stravaClubLinkError('strava_not_connected'), 'reconnect');
	assert.equal(stravaClubLinkError('link_failed'), 'generic');
	assert.equal(stravaClubLinkError(null), 'generic');
});

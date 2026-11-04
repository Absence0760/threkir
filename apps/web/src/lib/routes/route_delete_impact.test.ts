import assert from 'node:assert/strict';
import { test } from 'node:test';

import { routeDeleteImpactLines, type RouteDeleteImpact } from './route_delete_impact';

const none: RouteDeleteImpact = {
	saved_by_others: 0,
	reviews_by_others: 0,
	conditions_by_others: 0,
	segments_by_others: 0,
	segment_efforts_by_others: 0,
	shares: 0,
	race_listings: 0,
	events: 0,
	linked_runs: 0,
	photos: 0,
	markers: 0,
};

test('a private route nothing references adds no lines', () => {
	assert.deepEqual(routeDeleteImpactLines(none, false), []);
});

test('a public route says so even when nothing references it', () => {
	assert.deepEqual(routeDeleteImpactLines(none, true), [
		{ key: 'routeDetail.deleteImpact.public', count: 1 },
	]);
});

test('other people\'s dependents come before the owner\'s own content', () => {
	const all: RouteDeleteImpact = {
		saved_by_others: 3,
		reviews_by_others: 4,
		conditions_by_others: 5,
		segments_by_others: 6,
		segment_efforts_by_others: 7,
		shares: 8,
		race_listings: 1,
		events: 2,
		linked_runs: 9,
		photos: 10,
		markers: 11,
	};
	assert.deepEqual(
		routeDeleteImpactLines(all, true).map((l) => [l.key, l.count]),
		[
			['routeDetail.deleteImpact.public', 1],
			['routeDetail.deleteImpact.raceListings', 1],
			['routeDetail.deleteImpact.events', 2],
			['routeDetail.deleteImpact.saved', 3],
			['routeDetail.deleteImpact.shares', 8],
			['routeDetail.deleteImpact.segments', 6],
			['routeDetail.deleteImpact.efforts', 7],
			['routeDetail.deleteImpact.reviews', 4],
			['routeDetail.deleteImpact.conditions', 5],
			['routeDetail.deleteImpact.runs', 9],
			['routeDetail.deleteImpact.photos', 10],
			['routeDetail.deleteImpact.markers', 11],
		],
	);
});

test('a zero count drops only its own line', () => {
	assert.deepEqual(
		routeDeleteImpactLines({ ...none, race_listings: 1, photos: 2 }, false),
		[
			{ key: 'routeDetail.deleteImpact.raceListings', count: 1 },
			{ key: 'routeDetail.deleteImpact.photos', count: 2 },
		],
	);
});

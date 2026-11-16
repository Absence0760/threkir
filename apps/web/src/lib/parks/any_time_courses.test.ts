import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	anyTimeSearchHits,
	orderAnyTimeCourses,
	orderAnyTimeParks,
	parkSearchMatches,
	parkSearchTerms,
	type AnyTimeCourseKey,
	type AnyTimeParkKey,
	type AnyTimeSearchView,
} from './any_time_courses';

function course(over: Partial<AnyTimeCourseKey> & { slug: string }): AnyTimeCourseKey {
	return {
		regionCode: 'US-VA',
		parkName: 'Pocahontas',
		courseName: over.slug,
		distanceM: 5000,
		status: 'open',
		start: null,
		...over,
	};
}

const slugs = (rows: { course: AnyTimeCourseKey }[]) => rows.map((r) => r.course.slug);
const id = (c: AnyTimeCourseKey) => c;

test('orderAnyTimeCourses: without an origin, region then park then distance then name', () => {
	const rows = orderAnyTimeCourses(
		[
			course({ slug: 'wv', regionCode: 'US-WV' }),
			course({ slug: 'swift-10k', parkName: 'Swift Creek', distanceM: 10000 }),
			course({ slug: 'swift-5k', parkName: 'Swift Creek', distanceM: 5000 }),
			course({ slug: 'poca-b', courseName: 'B loop' }),
			course({ slug: 'poca-a', courseName: 'A loop' }),
		],
		id,
		null,
	);
	assert.deepEqual(slugs(rows), ['poca-a', 'poca-b', 'swift-5k', 'swift-10k', 'wv']);
	assert.ok(rows.every((r) => r.awayM === null));
});

test('orderAnyTimeCourses: with an origin, nearest start first, with its distance', () => {
	const origin = { lat: 37.5, lng: -77.5 };
	const rows = orderAnyTimeCourses(
		[
			course({ slug: 'far', start: { lat: 38.5, lng: -77.5 } }),
			course({ slug: 'near', start: { lat: 37.51, lng: -77.5 } }),
			course({ slug: 'mid', start: { lat: 37.6, lng: -77.5 } }),
		],
		id,
		origin,
	);
	assert.deepEqual(slugs(rows), ['near', 'mid', 'far']);
	// 0.01 degrees of latitude is about 1.11 km.
	assert.ok(Math.abs(rows[0].awayM! - 1112) < 5, `near is ${rows[0].awayM} m away`);
});

test('orderAnyTimeCourses: a course with no start follows every measured one, in stable order', () => {
	const rows = orderAnyTimeCourses(
		[
			course({ slug: 'unknown-b', courseName: 'B' }),
			course({ slug: 'measured', start: { lat: 40, lng: -77 } }),
			course({ slug: 'unknown-a', courseName: 'A' }),
		],
		id,
		{ lat: 37, lng: -77 },
	);
	assert.deepEqual(slugs(rows), ['measured', 'unknown-a', 'unknown-b']);
	assert.equal(rows[1].awayM, null);
});

test('orderAnyTimeCourses: a closed course sinks below every runnable one, with or without an origin', () => {
	const courses = [
		course({ slug: 'closed-near', status: 'closed', start: { lat: 37.5, lng: -77.5 }, courseName: 'A' }),
		course({ slug: 'seasonal-far', status: 'seasonal', start: { lat: 39, lng: -77.5 }, courseName: 'B' }),
		course({ slug: 'open-far', start: { lat: 40, lng: -77.5 }, courseName: 'C' }),
	];
	assert.deepEqual(slugs(orderAnyTimeCourses(courses, id, { lat: 37.5, lng: -77.5 })), [
		'seasonal-far',
		'open-far',
		'closed-near',
	]);
	assert.deepEqual(slugs(orderAnyTimeCourses(courses, id, null)), ['seasonal-far', 'open-far', 'closed-near']);
});

test('orderAnyTimeCourses: does not reorder its input', () => {
	const input = [course({ slug: 'b', courseName: 'B' }), course({ slug: 'a', courseName: 'A' })];
	orderAnyTimeCourses(input, id, null);
	assert.deepEqual(input.map((c) => c.slug), ['b', 'a']);
});

test('parkSearchTerms: folded words, blanks dropped', () => {
	assert.deepEqual(parkSearchTerms('  Swift   CRÉEK '), ['swift', 'creek']);
	assert.deepEqual(parkSearchTerms(''), []);
	assert.deepEqual(parkSearchTerms('   '), []);
});

test('parkSearchMatches: every word in the course, its park or its place', () => {
	const beaver = { courseName: 'Beaver Lake Trail', parkName: 'Pocahontas', regionCode: 'US-VA' };
	assert.equal(parkSearchMatches(parkSearchTerms('pocahontas beaver'), beaver), true);
	assert.equal(parkSearchMatches(parkSearchTerms('Virginia lake'), beaver), true);
	assert.equal(parkSearchMatches(parkSearchTerms('us-va'), beaver), true);
	assert.equal(parkSearchMatches(parkSearchTerms('beaver swift'), beaver), false);
	assert.equal(parkSearchMatches(parkSearchTerms('maryland'), beaver), false);
});

test('parkSearchMatches: no words match everything; a park alone is asked by its name and place', () => {
	const park = { parkName: 'Pocahontas', regionCode: 'US-VA' };
	assert.equal(parkSearchMatches([], park), true);
	assert.equal(parkSearchMatches(parkSearchTerms('poca'), park), true);
	assert.equal(parkSearchMatches(parkSearchTerms('virginia'), park), true);
	assert.equal(parkSearchMatches(parkSearchTerms('beaver'), park), false);
});

function park(over: Partial<AnyTimeParkKey> & { slug: string }): AnyTimeParkKey {
	return { regionCode: 'US-VA', parkName: over.slug, allClosed: false, starts: [], location: null, ...over };
}

const parkSlugs = (rows: { park: AnyTimeParkKey }[]) => rows.map((r) => r.park.slug);
const pid = (p: AnyTimeParkKey) => p;

test('orderAnyTimeParks: without an origin, region then name', () => {
	const rows = orderAnyTimeParks(
		[park({ slug: 'wv', regionCode: 'US-WV', parkName: 'A' }), park({ slug: 'swift', parkName: 'Swift Creek' }), park({ slug: 'poca', parkName: 'Pocahontas' })],
		pid,
		null,
	);
	assert.deepEqual(parkSlugs(rows), ['poca', 'swift', 'wv']);
	assert.ok(rows.every((r) => r.awayM === null));
});

test('orderAnyTimeParks: with an origin, by the nearest course start, falling back to the park location', () => {
	const rows = orderAnyTimeParks(
		[
			park({ slug: 'far-starts', starts: [{ lat: 38.5, lng: -77.5 }, { lat: 39, lng: -77.5 }] }),
			park({ slug: 'one-near-start', starts: [{ lat: 40, lng: -77.5 }, { lat: 37.51, lng: -77.5 }] }),
			park({ slug: 'located', location: { lat: 37.6, lng: -77.5 } }),
			park({ slug: 'nowhere' }),
		],
		pid,
		{ lat: 37.5, lng: -77.5 },
	);
	assert.deepEqual(parkSlugs(rows), ['one-near-start', 'located', 'far-starts', 'nowhere']);
	assert.ok(Math.abs(rows[0].awayM! - 1112) < 5, `nearest is ${rows[0].awayM} m away`);
	assert.equal(rows[3].awayM, null);
});

test('orderAnyTimeParks: a course start outranks the park location', () => {
	const rows = orderAnyTimeParks(
		[park({ slug: 'p', location: { lat: 37.5, lng: -77.5 }, starts: [{ lat: 38.5, lng: -77.5 }] })],
		pid,
		{ lat: 37.5, lng: -77.5 },
	);
	assert.ok(rows[0].awayM! > 100_000);
});

test('orderAnyTimeParks: a park with every course closed sinks, with or without an origin', () => {
	const parks = [
		park({ slug: 'closed-near', parkName: 'A', allClosed: true, starts: [{ lat: 37.5, lng: -77.5 }] }),
		park({ slug: 'open-far', parkName: 'B', starts: [{ lat: 40, lng: -77.5 }] }),
	];
	assert.deepEqual(parkSlugs(orderAnyTimeParks(parks, pid, { lat: 37.5, lng: -77.5 })), ['open-far', 'closed-near']);
	assert.deepEqual(parkSlugs(orderAnyTimeParks(parks, pid, null)), ['open-far', 'closed-near']);
});

const hitCourses: AnyTimeSearchView[] = [
	{ parkId: 'poca', courseName: 'Beaver Lake Trail', parkName: 'Pocahontas', regionCode: 'US-VA' },
	{ parkId: 'poca', courseName: 'Lake Trail 5k', parkName: 'Pocahontas', regionCode: 'US-VA' },
	{ parkId: 'swift', courseName: 'Creekside Loop', parkName: 'Swift Creek', regionCode: 'US-VA' },
];
const view = (c: AnyTimeSearchView) => c;

test('anyTimeSearchHits: no words lists every park once and no course on its own', () => {
	const hits = anyTimeSearchHits(hitCourses, view, []);
	assert.deepEqual(hits.parkIds, ['poca', 'swift']);
	assert.deepEqual(hits.courses, []);
});

test('anyTimeSearchHits: a park matched by name or place lists the park, not its courses', () => {
	assert.deepEqual(anyTimeSearchHits(hitCourses, view, parkSearchTerms('pocahontas')), { parkIds: ['poca'], courses: [] });
	assert.deepEqual(anyTimeSearchHits(hitCourses, view, parkSearchTerms('virginia')), { parkIds: ['poca', 'swift'], courses: [] });
});

test('anyTimeSearchHits: a course matched by its own name is listed on its own', () => {
	const hits = anyTimeSearchHits(hitCourses, view, parkSearchTerms('beaver'));
	assert.deepEqual(hits.parkIds, []);
	assert.deepEqual(hits.courses.map((c) => c.courseName), ['Beaver Lake Trail']);
	const lake = anyTimeSearchHits(hitCourses, view, parkSearchTerms('pocahontas lake'));
	assert.deepEqual(lake.courses.map((c) => c.courseName), ['Beaver Lake Trail', 'Lake Trail 5k']);
	// "creek" names the Swift Creek park, so its loop is not listed again.
	assert.deepEqual(anyTimeSearchHits(hitCourses, view, parkSearchTerms('creek')), { parkIds: ['swift'], courses: [] });
});

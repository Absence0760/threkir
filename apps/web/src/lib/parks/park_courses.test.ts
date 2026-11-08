import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	COURSE_SHAPES,
	courseIsCountable,
	groupParksByRegion,
	MAX_COURSE_CHECKPOINTS,
	parseCourseCheckpoints,
	regionCodeFromSlug,
	regionName,
	regionSlug,
} from './park_courses';

test('parseCourseCheckpoints: reads an ordered list of points', () => {
	assert.deepEqual(
		parseCourseCheckpoints([
			{ lat: 37.5, lng: -77.4 },
			{ lat: 37.6, lng: -77.3 },
		]),
		[
			{ lat: 37.5, lng: -77.4 },
			{ lat: 37.6, lng: -77.3 },
		],
	);
});

test('parseCourseCheckpoints: an empty list is a course with no checkpoints', () => {
	assert.deepEqual(parseCourseCheckpoints([]), []);
});

test('parseCourseCheckpoints: a non-list refuses the course', () => {
	assert.equal(parseCourseCheckpoints({ lat: 1, lng: 2 }), null);
	assert.equal(parseCourseCheckpoints(null), null);
	assert.equal(parseCourseCheckpoints('[]'), null);
});

test('parseCourseCheckpoints: one bad entry refuses the whole list, never a shorter one', () => {
	assert.equal(
		parseCourseCheckpoints([
			{ lat: 37.5, lng: -77.4 },
			{ lat: '37.6', lng: -77.3 },
		]),
		null,
	);
	assert.equal(parseCourseCheckpoints([{ lat: 37.5 }]), null);
	assert.equal(parseCourseCheckpoints([[37.5, -77.4]]), null);
});

test('parseCourseCheckpoints: out-of-range coordinates refuse the list', () => {
	assert.equal(parseCourseCheckpoints([{ lat: 91, lng: 0 }]), null);
	assert.equal(parseCourseCheckpoints([{ lat: 0, lng: -181 }]), null);
});

test('parseCourseCheckpoints: more than the cap refuses the list', () => {
	const many = Array.from({ length: MAX_COURSE_CHECKPOINTS + 1 }, () => ({ lat: 1, lng: 1 }));
	assert.equal(parseCourseCheckpoints(many), null);
	assert.equal(parseCourseCheckpoints(many.slice(1))?.length, MAX_COURSE_CHECKPOINTS);
});

test('regionSlug / regionCodeFromSlug round-trip an ISO 3166-2 code', () => {
	assert.equal(regionSlug('US-VA'), 'us-va');
	assert.equal(regionCodeFromSlug('us-va'), 'US-VA');
	assert.equal(regionCodeFromSlug('virginia'), null);
	assert.equal(regionCodeFromSlug('us-va/../x'), null);
});

test('regionName names a US state and falls back to the code', () => {
	assert.equal(regionName('US-VA'), 'Virginia');
	assert.equal(regionName('GB-ENG'), 'GB-ENG');
});

test('courseIsCountable: a closed course drops out of counts, a seasonal one stays', () => {
	assert.equal(courseIsCountable('open'), true);
	assert.equal(courseIsCountable('seasonal'), true);
	assert.equal(courseIsCountable('closed'), false);
});

test('groupParksByRegion: regions in code order, parks by name within each', () => {
	const groups = groupParksByRegion([
		{ region_code: 'US-VA', name: 'Pocahontas' },
		{ region_code: 'US-NC', name: 'Umstead' },
		{ region_code: 'US-VA', name: 'Douthat' },
	]);
	assert.deepEqual(
		groups.map((g) => [g.regionCode, g.parks.map((p) => p.name)]),
		[
			['US-NC', ['Umstead']],
			['US-VA', ['Douthat', 'Pocahontas']],
		],
	);
});

test('COURSE_SHAPES matches the course_shape CHECK', () => {
	assert.deepEqual([...COURSE_SHAPES], ['loop', 'out_and_back', 'point_to_point']);
});

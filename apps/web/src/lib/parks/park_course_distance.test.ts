import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	courseDistanceLabel,
	courseDistanceParts,
	courseDistanceRange,
	courseLapsChip,
	courseShapeShown,
	sortParkCourses,
	type ParkCourseSortKey,
} from './park_course_distance';

test('courseDistanceLabel: whole kilometres read without decimals', () => {
	assert.equal(courseDistanceLabel(5000, 'km', 'en'), '5 km');
	assert.equal(courseDistanceLabel(10000, 'km', 'en'), '10 km');
	assert.equal(courseDistanceLabel(50000, 'km', 'en'), '50 km');
	assert.equal(courseDistanceLabel(0, 'km', 'en'), '0 km');
});

test('courseDistanceLabel: anything else reads with one decimal, never two', () => {
	assert.equal(courseDistanceLabel(21100, 'km', 'en'), '21.1 km');
	assert.equal(courseDistanceLabel(42200, 'km', 'en'), '42.2 km');
	assert.equal(courseDistanceLabel(21097.5, 'km', 'en'), '21.1 km');
	assert.equal(courseDistanceLabel(500, 'km', 'en'), '0.5 km');
	assert.equal(courseDistanceLabel(4940, 'km', 'en'), '4.9 km');
});

test('courseDistanceLabel: within 0.05 of a whole number reads whole', () => {
	assert.equal(courseDistanceLabel(4960, 'km', 'en'), '5 km');
	assert.equal(courseDistanceLabel(5040, 'km', 'en'), '5 km');
	assert.equal(courseDistanceLabel(5060, 'km', 'en'), '5.1 km');
});

test('courseDistanceLabel: miles', () => {
	assert.equal(courseDistanceLabel(5000, 'mi', 'en'), '3.1 mi');
	assert.equal(courseDistanceLabel(42195, 'mi', 'en'), '26.2 mi');
	assert.equal(courseDistanceLabel(1609.344, 'mi', 'en'), '1 mi');
	assert.equal(courseDistanceLabel(50000, 'mi', 'en'), '31.1 mi');
});

test('courseDistanceLabel: the decimal separator follows the locale', () => {
	assert.equal(courseDistanceLabel(21100, 'km', 'de'), '21,1 km');
	assert.equal(courseDistanceLabel(5000, 'km', 'de'), '5 km');
});

test('courseDistanceLabel: an unreadable distance has no label', () => {
	assert.equal(courseDistanceLabel(Number.NaN, 'km', 'en'), null);
	assert.equal(courseDistanceLabel(-1, 'km', 'en'), null);
	assert.equal(courseDistanceLabel(Number.POSITIVE_INFINITY, 'mi', 'en'), null);
});

test('courseDistanceParts: the value is rounded to the digits it reads with', () => {
	assert.deepEqual(courseDistanceParts(21097.5, 'km'), { value: 21.1, fractionDigits: 1, unit: 'km' });
	assert.deepEqual(courseDistanceParts(4960, 'km'), { value: 5, fractionDigits: 0, unit: 'km' });
});

test('courseDistanceRange: shortest to longest, in any input order', () => {
	assert.equal(courseDistanceRange([21100, 5000, 50000, 10000], 'km', 'en'), '5–50 km');
	assert.equal(courseDistanceRange([5000, 50000], 'mi', 'en'), '3.1–31.1 mi');
});

test('courseDistanceRange: one label when every course reads the same', () => {
	assert.equal(courseDistanceRange([5000], 'km', 'en'), '5 km');
	assert.equal(courseDistanceRange([5000, 4980], 'km', 'en'), '5 km');
});

test('courseDistanceRange: unreadable distances are skipped, and none left is null', () => {
	assert.equal(courseDistanceRange([5000, Number.NaN, 21100], 'km', 'en'), '5–21.1 km');
	assert.equal(courseDistanceRange([], 'km', 'en'), null);
	assert.equal(courseDistanceRange([Number.NaN, -5], 'km', 'en'), null);
});

function key(over: Partial<ParkCourseSortKey> & { slug: string }): ParkCourseSortKey {
	return { distanceM: 5000, name: over.slug, status: 'open', ...over };
}

test('sortParkCourses: shortest first, not by name', () => {
	const courses = [
		key({ slug: 'beaver-lake', name: 'Beaver Lake Trail', distanceM: 4000 }),
		key({ slug: '10k', name: '10K', distanceM: 10000 }),
		key({ slug: '50k', name: '50K', distanceM: 50000 }),
		key({ slug: '5k', name: '5K', distanceM: 5000 }),
		key({ slug: 'half', name: 'Half marathon', distanceM: 21100 }),
		key({ slug: 'marathon', name: 'Marathon', distanceM: 42200 }),
	];
	assert.deepEqual(
		sortParkCourses(courses, (c) => c).map((c) => c.slug),
		['beaver-lake', '5k', '10k', 'half', 'marathon', '50k'],
	);
});

test('sortParkCourses: closed courses come last, still shortest first among themselves', () => {
	const courses = [
		key({ slug: 'a', distanceM: 3000, status: 'closed' }),
		key({ slug: 'b', distanceM: 9000, status: 'seasonal' }),
		key({ slug: 'c', distanceM: 1000, status: 'closed' }),
		key({ slug: 'd', distanceM: 6000 }),
	];
	assert.deepEqual(
		sortParkCourses(courses, (c) => c).map((c) => c.slug),
		['d', 'b', 'c', 'a'],
	);
});

test('sortParkCourses: equal distances order by name, then slug', () => {
	const courses = [
		key({ slug: 'z', name: 'Lake' }),
		key({ slug: 'y', name: 'Lake' }),
		key({ slug: 'x', name: 'Fire road' }),
	];
	assert.deepEqual(
		sortParkCourses(courses, (c) => c).map((c) => c.slug),
		['x', 'y', 'z'],
	);
});

test('sortParkCourses: returns a new array and leaves the input alone', () => {
	const courses = [key({ slug: 'b', distanceM: 2 }), key({ slug: 'a', distanceM: 1 })];
	const sorted = sortParkCourses(courses, (c) => c);
	assert.notEqual(sorted, courses);
	assert.deepEqual(courses.map((c) => c.slug), ['b', 'a']);
});

test('courseShapeShown: a loop goes unlabelled, the other shapes do not', () => {
	assert.equal(courseShapeShown('loop'), false);
	assert.equal(courseShapeShown('out_and_back'), true);
	assert.equal(courseShapeShown('point_to_point'), true);
	assert.equal(courseShapeShown(null), false);
	assert.equal(courseShapeShown('spiral'), false);
});

test('courseLapsChip: a chip only for two laps or more', () => {
	assert.equal(courseLapsChip(null), null);
	assert.equal(courseLapsChip(undefined), null);
	assert.equal(courseLapsChip(0), null);
	assert.equal(courseLapsChip(1), null);
	assert.equal(courseLapsChip(2), 2);
	assert.equal(courseLapsChip(4), 4);
	assert.equal(courseLapsChip(2.5), null);
});

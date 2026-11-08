import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	COURSE_SHAPES,
	courseAttribution,
	courseIsCountable,
	groupParksByRegion,
	MAX_COURSE_CHECKPOINTS,
	parkCourseGpx,
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

const PARK = { name: 'Fixture State Park', websiteUrl: 'https://example.gov/fixture' };

test('courseAttribution: osm names the ODbL and links the OpenStreetMap copyright page', () => {
	const a = courseAttribution('osm', PARK);
	assert.equal(a?.author, 'OpenStreetMap contributors');
	assert.equal(a?.licenseUrl, 'https://opendatacommons.org/licenses/odbl/1-0/');
	assert.equal(a?.linkHref, 'https://www.openstreetmap.org/copyright');
	assert.equal(a?.linkText, '© OpenStreetMap contributors');
	assert.match(a?.notice ?? '', /© OpenStreetMap contributors/);
});

test('courseAttribution: nps credits the National Park Service with no licence claim', () => {
	const a = courseAttribution('nps', PARK);
	assert.equal(a?.author, 'National Park Service');
	assert.equal(a?.licenseUrl, null);
	assert.equal(a?.linkHref, 'https://www.nps.gov/');
	assert.equal(a?.notice, 'Course line from National Park Service trail data.');
});

test('courseAttribution: agency credits the park and links its site only over https', () => {
	const a = courseAttribution('agency', PARK);
	assert.equal(a?.author, 'Fixture State Park');
	assert.equal(a?.linkHref, 'https://example.gov/fixture');
	assert.equal(a?.notice, 'Course line from trail data published by Fixture State Park.');
	assert.equal(courseAttribution('agency', { name: 'P', websiteUrl: 'http://x.test' })?.linkHref, null);
	assert.equal(courseAttribution('agency', { name: 'P', websiteUrl: null })?.linkHref, null);
});

test('courseAttribution: a park the reader cannot see still yields an unnamed credit', () => {
	assert.equal(courseAttribution('osm', null)?.author, 'OpenStreetMap contributors');
	const a = courseAttribution('agency', null);
	assert.equal(a?.author, null);
	assert.equal(a?.linkHref, null);
	assert.equal(a?.notice, 'Course line from trail data published by the park.');
});

test('courseAttribution: traced names no rights holder', () => {
	const a = courseAttribution('traced', PARK);
	assert.equal(a?.author, null);
	assert.equal(a?.notice, 'Course line traced against the published trail map of Fixture State Park.');
});

test('courseAttribution: a value outside the vocabulary, or none, has no attribution', () => {
	assert.equal(courseAttribution('strava', PARK), null);
	assert.equal(courseAttribution(null, PARK), null);
	assert.equal(courseAttribution(undefined, PARK), null);
});

test('parkCourseGpx: the line, one waypoint per checkpoint in order, and the credit', () => {
	const xml = parkCourseGpx({
		name: 'Lake Loop',
		waypoints: [
			{ lat: 37.1, lng: -77.5, ele: 50 },
			{ lat: 37.2, lng: -77.6 },
		],
		checkpoints: [
			{ lat: 37.11, lng: -77.51 },
			{ lat: 37.15, lng: -77.55 },
		],
		attribution: courseAttribution('osm', PARK),
	});
	assert.ok(xml.includes('<trkpt lat="37.1" lon="-77.5"><ele>50</ele></trkpt>'));
	assert.ok(xml.includes('<trkpt lat="37.2" lon="-77.6"><ele>0</ele></trkpt>'));
	const first = xml.indexOf('<name>Checkpoint 1</name>');
	const second = xml.indexOf('<name>Checkpoint 2</name>');
	assert.ok(first > 0 && second > first);
	assert.ok(xml.includes('<wpt lat="37.11" lon="-77.51"><name>Checkpoint 1</name><type>checkpoint</type></wpt>'));
	assert.ok(xml.includes('<copyright author="OpenStreetMap contributors">'));
});

test('parkCourseGpx: an unreadable checkpoint list writes no waypoints, never a partial set', () => {
	const xml = parkCourseGpx({
		name: 'Lake Loop',
		waypoints: [{ lat: 37.1, lng: -77.5 }],
		checkpoints: null,
		attribution: null,
	});
	assert.doesNotMatch(xml, /<wpt/);
	assert.doesNotMatch(xml, /<desc>/);
});

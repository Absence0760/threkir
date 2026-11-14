import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { parseRouteGuide } from './route_guide';
import {
	COURSE_SHAPES,
	courseAttribution,
	courseIsCountable,
	courseOffersWayfinding,
	groupParksByRegion,
	isLongCourse,
	LONG_COURSE_THRESHOLD_M,
	MAX_COURSE_CHECKPOINTS,
	parkCourseGpx,
	parseCourseCheckpoints,
	parseSharedUse,
	SHARED_USES,
	regionCodeFromSlug,
	regionName,
	regionSlug,
	pickShareCourse,
	recapParkSummary,
	shareCoursePlaces,
	parseBoardPeriod,
	boardPeriodParam,
	boardPeriodArgs,
	stepBoardMonth,
	SHARE_COURSE_YEAR_PLACE_MAX,
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

test('courseOffersWayfinding: a closed course offers no Navigate, GPX or route guide', () => {
	assert.equal(courseOffersWayfinding('open'), true);
	assert.equal(courseOffersWayfinding('seasonal'), true);
	assert.equal(courseOffersWayfinding('closed'), false);
});

test('isLongCourse: only a course over 15 km carries the long-course notice', () => {
	assert.equal(LONG_COURSE_THRESHOLD_M, 15000);
	assert.equal(isLongCourse(5000), false);
	assert.equal(isLongCourse(15000), false);
	assert.equal(isLongCourse(15001), true);
	assert.equal(isLongCourse(50000), true);
	assert.equal(isLongCourse(Number.NaN), false);
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

test('parkCourseGpx: the route guide is the track desc, in English, led by its ground-check status', () => {
	const guide = parseRouteGuide({
		version: 1,
		lang: 'en',
		getting_there: 'Park by the boathouse.',
		steps: [
			{ kind: 'start', at_m: 0, name: 'Lake Trail' },
			{ kind: 'junction', at_m: 400, turn: 'left', name: 'Ridge Trail' },
			{ kind: 'finish', at_m: 1990 },
		],
	});
	assert.ok(guide);
	const xml = parkCourseGpx({
		name: 'Lake Loop',
		waypoints: [{ lat: 37.1, lng: -77.5 }],
		checkpoints: [],
		attribution: null,
		guide: { guide, checkedAt: null },
	});
	assert.ok(
		xml.includes(
			'<desc>Drafted from map data, not yet checked on the ground.\nPark by the boathouse.\nStart on Lake Trail.\n' +
				'400 m: turn left onto Ridge Trail.\n2.0 km: finish.</desc>',
		),
	);
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

test('recapParkSummary: nothing run is nothing to say', () => {
	assert.deepEqual(recapParkSummary([]), { courseCount: 0, parkCount: 0, parks: [] });
});

test('recapParkSummary: a course run twice counts once, per park and overall', () => {
	const s = recapParkSummary([
		{ parkId: 'p1', parkName: 'Pocahontas', regionCode: 'US-VA', courseId: 'c1' },
		{ parkId: 'p1', parkName: 'Pocahontas', regionCode: 'US-VA', courseId: 'c1' },
		{ parkId: 'p1', parkName: 'Pocahontas', regionCode: 'US-VA', courseId: 'c2' },
		{ parkId: 'p2', parkName: 'Hungry Mother', regionCode: 'US-VA', courseId: 'c3' },
	]);
	assert.equal(s.courseCount, 3);
	assert.equal(s.parkCount, 2);
	assert.deepEqual(
		s.parks.map((p) => [p.parkId, p.courseCount]),
		[
			['p1', 2],
			['p2', 1],
		],
	);
});

test('recapParkSummary: parks with equal counts sort by name', () => {
	const s = recapParkSummary([
		{ parkId: 'b', parkName: 'Shenandoah', regionCode: 'US-VA', courseId: 'c1' },
		{ parkId: 'a', parkName: 'Great Falls', regionCode: 'US-VA', courseId: 'c2' },
	]);
	assert.deepEqual(
		s.parks.map((p) => p.name),
		['Great Falls', 'Shenandoah'],
	);
});

const TIME = {
	effort_id: 'e1',
	course_name: 'Lake Loop',
	course_slug: 'lake-loop',
	park_name: 'Pocahontas',
	park_slug: 'pocahontas',
	region_code: 'US-VA',
	time_seconds: 900,
	season: 2027,
	month: 11,
	season_rank: null,
};

test('pickShareCourse: no park course, no sticker', () => {
	assert.equal(pickShareCourse([]), null);
});

test('pickShareCourse: the best month place wins', () => {
	const rows = [
		{ ...TIME, course_name: 'A', month_rank: 7, season_rank: 1 },
		{ ...TIME, course_name: 'B', month_rank: 2, season_rank: 40 },
		{ ...TIME, course_name: 'C', month_rank: null },
	];
	assert.equal(pickShareCourse(rows)?.course_name, 'B');
});

test('pickShareCourse: a tied month place goes to the better year place', () => {
	const rows = [
		{ ...TIME, course_name: 'A', month_rank: 1, season_rank: null },
		{ ...TIME, course_name: 'B', month_rank: 1, season_rank: 12 },
		{ ...TIME, course_name: 'C', month_rank: 1, season_rank: 3 },
	];
	assert.equal(pickShareCourse(rows)?.course_name, 'C');
});

test('pickShareCourse: with nothing placed, the first time', () => {
	const rows = [
		{ ...TIME, course_name: 'A', month_rank: null },
		{ ...TIME, course_name: 'B', month_rank: null },
	];
	assert.equal(pickShareCourse(rows)?.course_name, 'A');
});

test('shareCoursePlaces: the year place only when it is in the top 10', () => {
	assert.equal(SHARE_COURSE_YEAR_PLACE_MAX, 10);
	assert.deepEqual(shareCoursePlaces({ month_rank: 2, season_rank: 9 }), { monthRank: 2, seasonRank: 9 });
	assert.deepEqual(shareCoursePlaces({ month_rank: 2, season_rank: 10 }), { monthRank: 2, seasonRank: 10 });
	assert.deepEqual(shareCoursePlaces({ month_rank: 4, season_rank: 11 }), { monthRank: 4, seasonRank: null });
	assert.deepEqual(shareCoursePlaces({ month_rank: null, season_rank: null }), { monthRank: null, seasonRank: null });
});

const NOW = { season: 2026, month: 11 };

test('parseBoardPeriod: a month and all time', () => {
	assert.deepEqual(parseBoardPeriod('2026-11', NOW), { kind: 'month', season: 2026, month: 11 });
	assert.deepEqual(parseBoardPeriod('2025-01', NOW), { kind: 'month', season: 2025, month: 1 });
	assert.deepEqual(parseBoardPeriod('2000-01', NOW), { kind: 'month', season: 2000, month: 1 });
	assert.deepEqual(parseBoardPeriod('all', NOW), { kind: 'all' });
});

test('parseBoardPeriod: anything else, an impossible month or a month still to come is null', () => {
	for (const raw of [null, undefined, '', '2026', '2026-1', '2026-001', '26-11', '2026-00', '2026-13', '1999-12', '2026-12', '2027-01', 'ALL', ' 2026-11', '2026-11 ']) {
		assert.equal(parseBoardPeriod(raw, NOW), null, String(raw));
	}
});

test('boardPeriodParam: a month is zero-padded, all time is all, the year has none', () => {
	assert.equal(boardPeriodParam({ kind: 'month', season: 2026, month: 3 }), '2026-03');
	assert.equal(boardPeriodParam({ kind: 'month', season: 2026, month: 11 }), '2026-11');
	assert.equal(boardPeriodParam({ kind: 'all' }), 'all');
	assert.equal(boardPeriodParam({ kind: 'year', season: 2026 }), null);
	assert.deepEqual(parseBoardPeriod(boardPeriodParam({ kind: 'month', season: 2026, month: 3 }), NOW), {
		kind: 'month',
		season: 2026,
		month: 3,
	});
});

test('boardPeriodArgs: the season and month each board call passes', () => {
	assert.deepEqual(boardPeriodArgs({ kind: 'month', season: 2026, month: 10 }), { season: 2026, month: 10 });
	assert.deepEqual(boardPeriodArgs({ kind: 'year', season: 2026 }), { season: 2026, month: null });
	assert.deepEqual(boardPeriodArgs({ kind: 'all' }), { season: null, month: null });
});

test('stepBoardMonth: steps across a year in both directions', () => {
	assert.deepEqual(stepBoardMonth({ kind: 'month', season: 2026, month: 1 }, -1, NOW), { kind: 'month', season: 2025, month: 12 });
	assert.deepEqual(stepBoardMonth({ kind: 'month', season: 2025, month: 12 }, 1, NOW), { kind: 'month', season: 2026, month: 1 });
	assert.deepEqual(stepBoardMonth({ kind: 'month', season: 2026, month: 10 }, 1, NOW), { kind: 'month', season: 2026, month: 11 });
});

test('stepBoardMonth: never past the park\'s month, nor before 2000, and only from a month', () => {
	assert.equal(stepBoardMonth({ kind: 'month', season: 2026, month: 11 }, 1, NOW), null);
	assert.equal(stepBoardMonth({ kind: 'month', season: 2000, month: 1 }, -1, NOW), null);
	assert.equal(stepBoardMonth({ kind: 'year', season: 2026 }, -1, NOW), null);
	assert.equal(stepBoardMonth({ kind: 'all' }, 1, NOW), null);
});

test('parseSharedUse: reads a known key and nothing else', () => {
	assert.deepEqual([...SHARED_USES], ['saturday_morning_group']);
	assert.equal(parseSharedUse('saturday_morning_group'), 'saturday_morning_group');
	for (const raw of [null, undefined, '', 'Saturday group', 'SATURDAY_MORNING_GROUP', 1, {}]) {
		assert.equal(parseSharedUse(raw), null, String(raw));
	}
});

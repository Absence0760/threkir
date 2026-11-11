import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	buildCourseGuideText,
	buildCourseJsonLd,
	buildCourseShareCanonical,
	buildCourseShareDescription,
	buildCourseShareTitle,
	buildShareCourseHead,
	renderShareCourseHeadTags,
} from './share_course_meta';
import { courseShareKey, parseCourseKey, type SharedCourse } from './share_course_lookup';
import { parseRouteGuide } from '../parks/route_guide';

const GUIDE = parseRouteGuide({
	version: 1,
	lang: 'en',
	steps: [
		{ kind: 'start', at_m: 0, name: 'Lake Trail' },
		{ kind: 'direction', at_m: 0, rotation: 'clockwise' },
		{ kind: 'finish', at_m: 5120 },
	],
});

function c(over: Partial<SharedCourse> = {}): SharedCourse {
	return {
		slug: 'lake-loop',
		course_shape: 'loop',
		status: 'open',
		status_note: null,
		geometry_source: 'osm',
		difficulty: 'moderate',
		laps: 1,
		attribution: '© OpenStreetMap contributors (ODbL)',
		route_guide: null,
		route_guide_checked_at: null,
		shared_use: null,
		segment: {
			name: 'Lake Loop',
			description: 'Around the lake.',
			distance_m: 5120,
			elevation_m: 40,
			surface: 'trail',
			waypoints: [
				{ lat: 37.1, lng: -77.5, ele: null },
				{ lat: 37.2, lng: -77.6, ele: 12 },
			],
		},
		park: {
			slug: 'fixture-state-park',
			name: 'Fixture State Park',
			region_code: 'US-VA',
			country_code: 'US',
			agency: 'state',
			website_url: 'https://example.gov/fixture',
		},
		...over,
	};
}

const SITE = 'https://threkir.com';
const KEY = 'us-va/fixture-state-park/lake-loop';

test('buildCourseShareTitle — course at park, generic fallback', () => {
	assert.equal(buildCourseShareTitle(c()), 'Lake Loop at Fixture State Park — Threkir');
	assert.equal(buildCourseShareTitle(null), 'Park course — Threkir');
});

test('buildCourseShareDescription — distance, shape, park and region; says time trial, never race', () => {
	const d = buildCourseShareDescription(c());
	assert.equal(
		d,
		'5.1 km loop course at Fixture State Park, Virginia. Run it any time: every run that covers it is timed on a yearly leaderboard.',
	);
	assert.doesNotMatch(d, /\brace\b/i);
	assert.match(
		buildCourseShareDescription(c({ course_shape: 'out_and_back' })),
		/^5\.1 km out-and-back course/,
	);
});

test('buildCourseShareDescription — a closed course says so instead of inviting a run', () => {
	assert.equal(
		buildCourseShareDescription(c({ status: 'closed' })),
		'5.1 km loop course at Fixture State Park, Virginia. Currently closed.',
	);
});

test('buildCourseShareCanonical — the three slugs under /share/course, one slash at the join', () => {
	assert.equal(buildCourseShareCanonical(`${SITE}/`, KEY), `${SITE}/share/course/${KEY}`);
});

test('courseShareKey / parseCourseKey — round-trip, and a malformed key is refused', () => {
	assert.equal(courseShareKey('US-VA', 'fixture-state-park', 'lake-loop'), KEY);
	assert.deepEqual(parseCourseKey(KEY), {
		regionCode: 'US-VA',
		region: 'us-va',
		park: 'fixture-state-park',
		course: 'lake-loop',
	});
	for (const bad of [
		'us-va/fixture-state-park',
		'us-va/fixture-state-park/lake-loop/extra',
		'US-VA/fixture-state-park/lake-loop',
		'virginia/fixture-state-park/lake-loop',
		'us-va/Fixture/lake-loop',
		"us-va/fixture/lake'loop",
		'us-va//lake-loop',
	]) {
		assert.equal(parseCourseKey(bad), null, bad);
	}
});

test('buildCourseJsonLd — SportsActivityLocation at the start, contained in its Park', () => {
	const ld = JSON.parse(buildCourseJsonLd(c(), { key: KEY, base: SITE }));
	assert.equal(ld['@type'], 'SportsActivityLocation');
	assert.equal(ld.name, 'Lake Loop');
	assert.equal(ld.url, `${SITE}/share/course/${KEY}`);
	assert.deepEqual(ld.geo, { '@type': 'GeoCoordinates', latitude: 37.1, longitude: -77.5 });
	assert.equal(ld.containedInPlace['@type'], 'Park');
	assert.equal(ld.containedInPlace.name, 'Fixture State Park');
	assert.equal(ld.containedInPlace.sameAs, 'https://example.gov/fixture');
	assert.deepEqual(ld.containedInPlace.address, {
		'@type': 'PostalAddress',
		addressRegion: 'US-VA',
		addressCountry: 'US',
	});
});

test('buildCourseJsonLd — no geometry means no geo; a non-https park site is not linked', () => {
	const course = c();
	const ld = JSON.parse(
		buildCourseJsonLd(
			{
				...course,
				segment: { ...course.segment, waypoints: [] },
				park: { ...course.park, website_url: 'http://example.gov' },
			},
			{ key: KEY, base: SITE },
		),
	);
	assert.equal(ld.geo, undefined);
	assert.equal(ld.containedInPlace.sameAs, undefined);
});

test('buildShareCourseHead — canonical comes from the row, and the head names no runner', () => {
	const head = buildShareCourseHead({ key: 'us-va/fixture-state-park/lake-loop/', course: c(), siteUrl: SITE });
	assert.equal(head.canonical, `${SITE}/share/course/${KEY}`);
	assert.equal(head.ogImageUrl, `${SITE}/og-default.png`);
	const tags = renderShareCourseHeadTags(head);
	assert.match(tags, /<link rel="canonical" href="https:\/\/threkir\.com\/share\/course\/us-va\/fixture-state-park\/lake-loop">/);
	assert.match(tags, /<script type="application\/ld\+json">/);
	assert.doesNotMatch(tags, /leaderboard entry|display_name|athlete/i);
});

test('a draft route guide says so in the description, a checked one does not', () => {
	assert.match(
		buildCourseShareDescription(c({ route_guide: GUIDE })),
		/ Route guide: drafted from map data, not yet checked on the ground\.$/,
	);
	assert.doesNotMatch(
		buildCourseShareDescription(c({ route_guide: GUIDE, route_guide_checked_at: '2026-12-01' })),
		/Route guide/,
	);
	assert.doesNotMatch(buildCourseShareDescription(c()), /Route guide/);
});

test('the route guide is the JSON-LD description\'s indexable text, in English', () => {
	assert.equal(buildCourseGuideText(c()), '');
	assert.equal(
		buildCourseGuideText(c({ route_guide: GUIDE })),
		'Drafted from map data, not yet checked on the ground. Start on Lake Trail. Run the loop clockwise. 5.1 km: finish.',
	);
	const ld = JSON.parse(buildCourseJsonLd(c({ route_guide: GUIDE }), { key: KEY, base: SITE }));
	assert.match(ld.description, /Start on Lake Trail\. Run the loop clockwise\./);
});

test('a closed course gives its route guide to no description, JSON-LD included', () => {
	const closed = c({ status: 'closed', route_guide: GUIDE });
	assert.equal(buildCourseGuideText(closed), '');
	assert.doesNotMatch(buildCourseShareDescription(closed), /Route guide/);
	const ld = JSON.parse(buildCourseJsonLd(closed, { key: KEY, base: SITE }));
	assert.equal(ld.description, '5.1 km loop course at Fixture State Park, Virginia. Currently closed.');
});

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { boundsOf, courseSearch, selectedCourseSlug, startSentence } from './course_preview';
import type { GuideFormat, RouteGuide } from './route_guide';

const SLUGS = ['5k', '10k', 'beaver-lake'];

test('selectedCourseSlug: only a slug the park has', () => {
	assert.equal(selectedCourseSlug('?course=10k', SLUGS), '10k');
	assert.equal(selectedCourseSlug('course=beaver-lake&x=1', SLUGS), 'beaver-lake');
	assert.equal(selectedCourseSlug('?course=gone', SLUGS), null);
	assert.equal(selectedCourseSlug('?course=', SLUGS), null);
	assert.equal(selectedCourseSlug('', SLUGS), null);
});

test('courseSearch: sets or clears course and keeps the rest', () => {
	assert.equal(courseSearch('', '5k'), '?course=5k');
	assert.equal(courseSearch('?course=5k', '10k'), '?course=10k');
	assert.equal(courseSearch('?course=5k', null), '');
	assert.equal(courseSearch('?period=2026&course=5k', null), '?period=2026');
	assert.equal(courseSearch('?period=2026', 'a b'), '?period=2026&course=a+b');
});

test('boundsOf: frames every real point and skips the rest', () => {
	assert.deepEqual(
		boundsOf([
			[{ lat: 37.38, lng: -77.59 }, { lat: 37.4, lng: -77.53 }],
			[{ lat: 37.36, lng: -77.6 }],
		]),
		[[-77.6, 37.36], [-77.53, 37.4]],
	);
	assert.deepEqual(
		boundsOf([[{ lat: 0, lng: 0 }, { lat: Number.NaN, lng: 1 }, { lat: 95, lng: 0 }, { lat: 37.4, lng: -77.5 }]]),
		[[-77.5, 37.4], [-77.5, 37.4]],
	);
	assert.equal(boundsOf([]), null);
	assert.equal(boundsOf([[{ lat: 0, lng: 0 }]]), null);
});

const FMT: GuideFormat = {
	message: (key, params) => `${key}${params.name ? `:${params.name}` : ''}`,
	distance: (m) => `${m} m`,
	short: (m) => `${m} m`,
};

const guide = (gettingThere: string | null): RouteGuide => ({
	lang: 'en',
	gettingThere,
	steps: [
		{ kind: 'start', at_m: 0, name: 'Lake Trail' },
		{ kind: 'finish', at_m: 5000 },
	],
});

test('startSentence: the getting-there note first, in its own language', () => {
	assert.deepEqual(startSentence(guide('Start at the boat-ramp lot.'), FMT), {
		text: 'Start at the boat-ramp lot.',
		lang: 'en',
	});
});

test('startSentence: else the guide first line, in the reader language; nothing without a guide', () => {
	assert.deepEqual(startSentence(guide(null), FMT), { text: 'startNamed:Lake Trail', lang: null });
	assert.equal(startSentence(null, FMT), null);
});

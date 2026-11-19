import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	PLACE_REACH_M,
	catalogueCentre,
	coursePlaceBias,
	placeLabel,
	placeSearchCountries,
	placesNearCourses,
} from './course_place_search';

const BELLE_ISLE_SP = { lat: 37.778, lng: -76.596 };
const POCAHONTAS_SP = { lat: 37.37, lng: -77.58 };

test('placeSearchCountries: the catalogue countries plus the reader region, sorted and unique', () => {
	assert.deepEqual(placeSearchCountries(['US-VA', 'US-MD', 'CA-ON'], 'en-GB'), ['ca', 'gb', 'us']);
	assert.deepEqual(placeSearchCountries(['US-VA'], 'en-US'), ['us']);
	// A bare language is maximized to its likely region.
	assert.deepEqual(placeSearchCountries(['US-VA'], 'ja'), ['jp', 'us']);
	assert.deepEqual(placeSearchCountries([], null), []);
	assert.deepEqual(placeSearchCountries(['not a code', 'X'], 'not-a-locale-!!'), []);
});

test('catalogueCentre: the mean point, or null with none', () => {
	assert.equal(catalogueCentre([]), null);
	assert.deepEqual(catalogueCentre([{ lat: 10, lng: 20 }, { lat: 20, lng: 40 }]), { lat: 15, lng: 30 });
});

test('coursePlaceBias: countries and proximity when there are any, an empty bias when not', () => {
	assert.deepEqual(coursePlaceBias(['US-VA'], [BELLE_ISLE_SP], 'en-US'), {
		countries: ['us'],
		proximity: BELLE_ISLE_SP,
	});
	assert.deepEqual(coursePlaceBias([], [], null), {});
});

test('placesNearCourses: a namesake far from every course is not offered', () => {
	const places = [
		{ name: 'Belle, Missouri, United States', lat: 38.286, lng: -91.72 },
		{ name: 'Belle Isle, Virginia, United States', lat: 37.78, lng: -76.6 },
		{ name: 'Belle-Île, France', lat: 47.33, lng: -3.18 },
	];
	const offered = placesNearCourses(places, [BELLE_ISLE_SP, POCAHONTAS_SP]);
	assert.deepEqual(
		offered.map((p) => p.name),
		['Belle Isle, Virginia, United States'],
	);
});

test('placesNearCourses: provider order kept, one per name, capped', () => {
	const near = (name: string, dLat: number) => ({ name, lat: POCAHONTAS_SP.lat + dLat, lng: POCAHONTAS_SP.lng });
	const offered = placesNearCourses(
		[near('Richmond, VA', 0.1), near('richmond, va', 0.2), near('Petersburg, VA', 0.3), near('Ashland, VA', 0.4), near('Hopewell, VA', 0.5)],
		[POCAHONTAS_SP],
	);
	assert.deepEqual(
		offered.map((p) => p.name),
		['Richmond, VA', 'Petersburg, VA', 'Ashland, VA'],
	);
});

test('placesNearCourses: with no course points nothing is offered; the reach is inclusive', () => {
	assert.deepEqual(placesNearCourses([{ name: 'Richmond', ...POCAHONTAS_SP }], []), []);
	assert.equal(PLACE_REACH_M, 1_000_000);
	assert.equal(placesNearCourses([{ name: 'Here', ...POCAHONTAS_SP }], [POCAHONTAS_SP], 0).length, 1);
});

test('placeLabel: the first two parts of a long name, a short one whole', () => {
	assert.equal(placeLabel('Belle Isle, Lancaster County, Virginia, United States'), 'Belle Isle, Lancaster County');
	assert.equal(placeLabel('Richmond, VA'), 'Richmond, VA');
	assert.equal(placeLabel('  Richmond '), 'Richmond');
	assert.equal(placeLabel(' , '), '');
});

// What an imported route is called, and what one malformed entry may cost the
// rest of the file. Mirrors packages/gpx_parser's route_parser.dart, whose
// `_elementName` / `_geoJsonName` read direct children and non-blank strings
// only, and whose GeoJSON walk skips a feature that is not an object.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { childName, geoJsonName, parseRouteFile } from './import';

type Node = { localName: string; textContent: string | null; children?: Node[] };
const el = (children: Node[]) => ({ children });
const name = (text: string | null): Node => ({ localName: 'name', textContent: text });

function geojson(body: unknown): File {
	return new File([JSON.stringify(body)], 'route.geojson');
}
const LINE = { type: 'LineString', coordinates: [[-0.1, 51.5], [-0.11, 51.51]] };

test('childName — reads the element’s own <name>, trimmed', () => {
	assert.equal(childName(el([name('  Ridge loop  ')]), 'fallback'), 'Ridge loop');
});

test('childName — a blank or empty <name/> falls back instead of naming the route ""', () => {
	for (const text of ['', '   ', null]) {
		assert.equal(childName(el([name(text)]), 'Imported Route'), 'Imported Route', JSON.stringify(text));
	}
});

test('childName — a descendant’s name is not the element’s', () => {
	// A <trk> with no <name> whose first <trkpt> carries one: querySelector
	// found the waypoint's name; only a direct child counts.
	const trkpt: Node = { localName: 'trkpt', textContent: 'Water stop', children: [name('Water stop')] };
	assert.equal(childName(el([trkpt]), 'Imported Route'), 'Imported Route');
});

test('geoJsonName — only a non-blank string names a route', () => {
	assert.equal(geoJsonName(' Canal path ', 'x'), 'Canal path');
	for (const v of [42, '', '  ', null, undefined, { en: 'Canal' }, ['Canal']]) {
		assert.equal(geoJsonName(v, 'Imported Route'), 'Imported Route', JSON.stringify(v));
	}
});

test('a GeoJSON feature with a numeric or blank name imports under the fallback name', async () => {
	const routes = await parseRouteFile(
		geojson({
			type: 'FeatureCollection',
			name: 'Club routes',
			features: [
				{ type: 'Feature', properties: { name: 42 }, geometry: LINE },
				{ type: 'Feature', properties: { name: '' }, geometry: LINE }
			]
		})
	);
	assert.deepEqual(
		routes.map((r) => r.name),
		['Club routes', 'Club routes']
	);
});

test('a null feature is skipped; the routes beside it still import', async () => {
	const routes = await parseRouteFile(
		geojson({
			type: 'FeatureCollection',
			features: [null, 7, { type: 'Feature', properties: { name: 'Kept' }, geometry: LINE }]
		})
	);
	assert.deepEqual(
		routes.map((r) => r.name),
		['Kept']
	);
});

test('a GeoJSON document that is not an object is refused by name, not with a TypeError', async () => {
	for (const body of [null, 42, 'LineString']) {
		await assert.rejects(parseRouteFile(geojson(body)), /no line-based routes/, JSON.stringify(body));
	}
});

test('an elevation pair whose climb overflows adds nothing, not Infinity', async () => {
	const [route] = await parseRouteFile(
		geojson({
			type: 'Feature',
			properties: { name: 'Overflow' },
			geometry: {
				type: 'LineString',
				coordinates: [
					[0, 0, -1e308],
					[0, 0.001, 1e308]
				]
			}
		})
	);
	assert.equal(route.elevation_m, null);
});

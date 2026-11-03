import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { videoBasemapPermitted, videoMaptilerKey } from './flyover_video_source.ts';
import { resolveTerrainSource, AWS_TERRAIN_SOURCE } from './terrain_source.ts';
import { OSM_FALLBACK_STYLE_URL, styleUrlForSlug } from './map-style-url.ts';

test('the video export uses no MapTiler key until the operator flag is set', () => {
	for (const flag of [undefined, null, '', '0', 'false', 'no', ' off ']) {
		assert.equal(videoMaptilerKey('abc123', flag), '', String(flag));
	}
	assert.equal(videoMaptilerKey(' abc123 ', 'true'), 'abc123');
	assert.equal(videoMaptilerKey('abc123', '1'), 'abc123');
});

test('with the flag unset and no override, the export has no basemap it may record', () => {
	const key = videoMaptilerKey('abc123', undefined);
	assert.equal(styleUrlForSlug('streets-v2', key, ''), OSM_FALLBACK_STYLE_URL);
	assert.equal(videoBasemapPermitted(key, ''), false);
	assert.equal(videoBasemapPermitted(key, undefined), false);
	assert.equal(videoBasemapPermitted(key, '   '), false);
});

test('the export is offered on MapTiler with the flag set, or on a local tile-style override', () => {
	const allowed = videoMaptilerKey('abc123', 'true');
	assert.equal(videoBasemapPermitted(allowed, ''), true);
	assert.notEqual(styleUrlForSlug('streets-v2', allowed, ''), OSM_FALLBACK_STYLE_URL);

	const local = 'http://localhost:8080/styles/basic/style.json';
	assert.equal(videoBasemapPermitted(videoMaptilerKey('abc123', undefined), local), true);
	assert.equal(styleUrlForSlug('streets-v2', '', local), local);
});

test('with a style override but no video key, terrain still takes the disclosed keyless rung', () => {
	const key = videoMaptilerKey('abc123', undefined);
	assert.deepEqual(resolveTerrainSource({ maptilerKey: key, override: '' }), AWS_TERRAIN_SOURCE);
});

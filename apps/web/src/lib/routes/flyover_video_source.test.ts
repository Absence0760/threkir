import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { videoMaptilerKey } from './flyover_video_source.ts';
import { resolveTerrainSource, AWS_TERRAIN_SOURCE } from './terrain_source.ts';
import { OSM_FALLBACK_STYLE_URL, styleUrlForSlug } from './map-style-url.ts';

test('the video export uses no MapTiler key until the operator flag is set', () => {
	for (const flag of [undefined, null, '', '0', 'false', 'no', ' off ']) {
		assert.equal(videoMaptilerKey('abc123', flag), '', String(flag));
	}
	assert.equal(videoMaptilerKey(' abc123 ', 'true'), 'abc123');
	assert.equal(videoMaptilerKey('abc123', '1'), 'abc123');
});

test('with the flag unset, the keyless rungs are what the export resolves to', () => {
	const key = videoMaptilerKey('abc123', undefined);
	assert.deepEqual(resolveTerrainSource({ maptilerKey: key, override: '' }), AWS_TERRAIN_SOURCE);
	assert.equal(styleUrlForSlug('streets-v2', key, ''), OSM_FALLBACK_STYLE_URL);
});

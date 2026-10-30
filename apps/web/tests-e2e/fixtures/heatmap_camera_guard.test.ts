import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

import { stripComments } from '../../src/lib/core/strip_comments';

// Reason: a spec that moves the heatmap camera itself races the page's own initial
// framing (see fixtures/heatmap.ts). Every camera move goes through that
// fixture, which waits on `__heatmapPinsSettled` first.

const HERE = dirname(fileURLToPath(import.meta.url));
const E2E_ROOT = join(HERE, '..');
const FIXTURE = join(HERE, 'heatmap.ts');
const COMPONENT = join(HERE, '..', '..', 'src', 'lib', 'components', 'RouteHeatmap.svelte');

const CAMERA_MOVE = /\.(flyTo|easeTo|jumpTo|fitBounds|panTo|zoomTo|setCenter|setZoom)\s*\(|['"]moveend['"]/;

function specs(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir)) {
		if (entry === 'node_modules' || entry === '.auth') continue;
		const full = join(dir, entry);
		if (statSync(full).isDirectory()) specs(full, out);
		else if (full.endsWith('.ts') && !full.endsWith('.test.ts') && full !== FIXTURE) out.push(full);
	}
	return out;
}

test('no e2e file but the heatmap fixture moves the heatmap camera', () => {
	const offenders: string[] = [];
	for (const file of specs(E2E_ROOT)) {
		const source = stripComments(readFileSync(file, 'utf8'));
		if (!source.includes('__heatmapMap')) continue;
		source.split('\n').forEach((line, i) => {
			if (CAMERA_MOVE.test(line)) offenders.push(`${relative(E2E_ROOT, file)}:${i + 1}`);
		});
	}
	assert.deepEqual(
		offenders,
		[],
		'move the /routes/heatmap camera with jumpAndSettle / settleOnFeature from fixtures/heatmap.ts',
	);
});

test('the fixture waits on the settled hook the component still exposes', () => {
	const fixture = stripComments(readFileSync(FIXTURE, 'utf8'));
	assert.match(fixture, /__heatmapPinsSettled\?\.\(\)/);
	assert.match(readFileSync(COMPONENT, 'utf8'), /__heatmapPinsSettled\s*=/);
});

test('the camera-move pattern catches the shape that raced', () => {
	assert.ok(CAMERA_MOVE.test("m.once('moveend', () => r());"));
	assert.ok(CAMERA_MOVE.test('m.flyTo({ center: [lng, lat], zoom: 13 });'));
	assert.ok(!CAMERA_MOVE.test('await jumpToVA(page);'));
});

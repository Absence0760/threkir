// Invocation: npx tsx --test src/lib/core/zip_archive.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import JSZip from 'jszip';

import { openZip } from './zip_archive';

async function fixture(): Promise<Uint8Array> {
	const inner = new JSZip();
	inner.file('activity.fit', new Uint8Array([14, 16, 1, 2]));
	const zip = new JSZip();
	zip.folder('activities');
	zip.file('activities.csv', 'Activity ID,Activity Name\n1,Morning Run — café\n');
	zip.file('activities/1.gpx', '<gpx/>');
	zip.file('activities/2.zip', await inner.generateAsync({ type: 'uint8array' }));
	return zip.generateAsync({ type: 'uint8array', compression: 'DEFLATE' });
}

test('lists file members only, and reads them as text, bytes and a blob', async () => {
	const zip = await openZip(await fixture());
	assert.deepEqual([...zip.paths].sort(), ['activities.csv', 'activities/1.gpx', 'activities/2.zip']);
	assert.equal(zip.has('activities/'), false, 'a directory entry is not a member');
	assert.equal(await zip.text('activities.csv'), 'Activity ID,Activity Name\n1,Morning Run — café\n');
	assert.equal(await (await zip.blob('activities/1.gpx'))!.text(), '<gpx/>');
	const inner = await openZip((await zip.blob('activities/2.zip'))!);
	assert.deepEqual(await inner.bytes('activity.fit'), new Uint8Array([14, 16, 1, 2]));
});

test('reads the same archive from a Blob and an ArrayBuffer', async () => {
	const bytes = await fixture();
	const copy = new Uint8Array(bytes);
	for (const input of [new Blob([copy]), copy.buffer]) {
		assert.equal((await (await openZip(input)).text('activities/1.gpx')), '<gpx/>');
	}
});

test('a missing member reads as null in every form', async () => {
	const zip = await openZip(await fixture());
	assert.equal(zip.has('nope.json'), false);
	assert.equal(await zip.text('nope.json'), null);
	assert.equal(await zip.bytes('nope.json'), null);
	assert.equal(await zip.blob('nope.json'), null);
});

test('input that is not a zip rejects', async () => {
	await assert.rejects(openZip(new TextEncoder().encode('not a zip at all')));
});

test('no shipped module imports JSZip: zip reads go through openZip', () => {
	const src = resolve(import.meta.dirname, '../..');
	const offenders = (readdirSync(src, { recursive: true }) as string[])
		.filter((f) => /\.(ts|svelte)$/.test(f) && !/\.test\.ts$/.test(f))
		.filter((f) => /from ['"]jszip['"]|import\(['"]jszip['"]\)/.test(readFileSync(resolve(src, f), 'utf-8')));
	assert.deepEqual(offenders, [], 'read zips with openZip (core/zip_archive.ts)');
	const pkg = JSON.parse(readFileSync(resolve(src, '../package.json'), 'utf-8'));
	assert.equal(pkg.dependencies.jszip, undefined, 'jszip is a test-fixture devDependency only');
});

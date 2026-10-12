// A backup archive is a file the runner picks from disk, so every JSON entry
// in it can hold any shape at all. These pin what the reader does when an
// entry is the wrong KIND of JSON — the case a hand-edited or truncated
// archive produces — rather than a well-formed one.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import JSZip from 'jszip';

import { parseBackupArchive } from './backup_reader';
import { restoreOrchestrate, type RestoreBackend } from './restore_orchestrator';
import { BACKUP_FORMAT, BACKUP_VERSION } from './backup_writer';
import type { ParsedBackup } from './backup_reader';
import type { JsonObject } from '../types';

async function archiveWith(entries: Record<string, string>): Promise<Uint8Array> {
	const zip = new JSZip();
	zip.file('manifest.json', JSON.stringify({ format: BACKUP_FORMAT, version: BACKUP_VERSION }));
	for (const [name, body] of Object.entries(entries)) zip.file(name, body);
	return zip.generateAsync({ type: 'uint8array' });
}

test('parseBackupArchive: a runs.json that is not a list is refused, not handed to restore', async () => {
	for (const body of ['{"id":"r1"}', 'null', '"runs"', '42']) {
		await assert.rejects(
			parseBackupArchive(await archiveWith({ 'runs.json': body })),
			/runs\.json/,
			body,
		);
	}
});

test('parseBackupArchive: a routes.json that is not a list is refused', async () => {
	for (const body of ['{}', 'null']) {
		await assert.rejects(
			parseBackupArchive(await archiveWith({ 'routes.json': body })),
			/routes\.json/,
			body,
		);
	}
});

test('parseBackupArchive: a manifest that is not an object is not a valid backup', async () => {
	const zip = new JSZip();
	zip.file('manifest.json', 'null');
	await assert.rejects(
		parseBackupArchive(await zip.generateAsync({ type: 'uint8array' })),
		/Not a valid backup|Unexpected format/,
	);
});

test('parseBackupArchive: an array profile or settings_prefs is not restored as one', async () => {
	const parsed = await parseBackupArchive(
		await archiveWith({
			'profile.json': JSON.stringify({ profile: ['display_name'], settings_prefs: ['dark'] }),
		}),
	);
	assert.equal(parsed.profile, null, 'an array is not a profile row');
	assert.deepEqual(parsed.settingsPrefs, {}, 'an array is not a prefs object');
});

function recordingBackend() {
	const runs: Record<string, unknown>[] = [];
	const routes: Record<string, unknown>[] = [];
	const backend: RestoreBackend = {
		async upsertProfile() {},
		async upsertSettings() {},
		async uploadTrack() {},
		async upsertRun(row) {
			runs.push(row);
		},
		async upsertRoute(row) {
			routes.push(row);
		},
		async fetchValidEventIds() {
			return new Set<string>();
		},
	};
	return { backend, runs, routes };
}

function parsedWith(runs: unknown[], routes: unknown[] = []): ParsedBackup {
	return {
		manifest: { format: BACKUP_FORMAT, version: BACKUP_VERSION },
		runs: runs as JsonObject[],
		routes: routes as JsonObject[],
		profile: null,
		settingsPrefs: {},
		async getTrackBytes() {
			return null;
		},
	};
}

test('restore: a run entry that is not an object is skipped with a warning and the rest still land', async () => {
	const { backend, runs, routes } = recordingBackend();
	const result = await restoreOrchestrate(
		parsedWith(
			[{ id: 'a', distance_m: 1000 }, null, 'run', [1, 2], { id: 'b', distance_m: 2000 }],
			[{ id: 'route-1', name: 'Loop' }],
		),
		'uid',
		backend,
	);
	assert.deepEqual(runs.map((r) => r.id), ['a', 'b']);
	assert.equal(result.runsImported, 2);
	assert.equal(routes.length, 1, 'a bad run row does not cost the routes section');
	assert.equal(result.warnings.filter((w) => w.startsWith('run ')).length, 3, result.warnings.join('\n'));
});

test('restore: a route entry that is not an object is skipped with a warning', async () => {
	const { backend, routes } = recordingBackend();
	const result = await restoreOrchestrate(
		parsedWith([], [null, { id: 'route-1', name: 'Loop' }, 7]),
		'uid',
		backend,
	);
	assert.deepEqual(routes.map((r) => r.id), ['route-1']);
	assert.equal(result.routesImported, 1);
	assert.equal(result.warnings.filter((w) => w.startsWith('route ')).length, 2, result.warnings.join('\n'));
});

// Unit tests for the streaming + parallel-download web backup writer.
// Invocation:
//   npx tsx --test src/lib/backup/backup.test.ts
//
// The writer is pulled out of `createBackup` as `buildBackupZip` so the
// streaming contract is testable without booting supabase-js. The
// fetcher seam lets us count concurrent calls + simulate partial
// failures.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import JSZip from 'jszip';

import {
	buildBackupZip,
	BACKUP_FORMAT,
	BACKUP_VERSION
} from './backup_writer';

function gzipOf(_payload: object): Uint8Array {
	// Tests don't actually need real gzip — the writer treats track
	// bytes as opaque (level: 0 = STORE). Any bytes round-trip.
	return new TextEncoder().encode(JSON.stringify(_payload));
}

test('buildBackupZip: writes a valid archive with all four metadata files', async () => {
	const archive = await buildBackupZip({
		runsOut: [{ id: 'r-1', distance_m: 5000 }],
		routesOut: [{ id: 'rt-1', name: 'Park loop' }],
		profile: { username: 'tester' },
		settingsPrefs: { unit: 'km' },
		userId: 'uid',
		exportedFrom: 'test',
		runsWithTracks: [{ id: 'r-1', track_url: 'uid/r-1.json.gz' }],
		fetchTrackBytes: async () => gzipOf([{ lat: 0.0, lng: 0.0 }])
	});

	// Round-trip via JSZip (the existing restore path uses it; pinning
	// this proves the new writer hasn't drifted from what restore reads).
	const buf = new Uint8Array(await archive.blob.arrayBuffer());
	const zip = await JSZip.loadAsync(buf);

	const manifestRaw = await zip.file('manifest.json')!.async('string');
	const manifest = JSON.parse(manifestRaw);
	assert.equal(manifest.format, BACKUP_FORMAT);
	assert.equal(manifest.version, BACKUP_VERSION);
	assert.equal(manifest.exported_by_user_id, 'uid');
	assert.equal(manifest.counts.runs, 1);
	assert.equal(manifest.counts.routes, 1);
	assert.equal(manifest.counts.tracks, 1);

	const runs = JSON.parse(await zip.file('runs.json')!.async('string'));
	assert.equal(runs[0].id, 'r-1');

	const routes = JSON.parse(await zip.file('routes.json')!.async('string'));
	assert.equal(routes[0].name, 'Park loop');

	const profile = JSON.parse(await zip.file('profile.json')!.async('string'));
	assert.equal(profile.profile.username, 'tester');
	assert.equal(profile.settings_prefs.unit, 'km');

	const trackEntry = zip.file('tracks/r-1.json.gz');
	assert.ok(trackEntry, 'tracks/r-1.json.gz must be present');
});

test('buildBackupZip: downloads tracks in bounded-concurrency batches', async () => {
	let inFlight = 0;
	let peakInFlight = 0;
	let totalCalls = 0;

	const fetcher = async (path: string): Promise<Uint8Array> => {
		totalCalls++;
		inFlight++;
		if (inFlight > peakInFlight) peakInFlight = inFlight;
		// Yield so concurrent calls observably overlap rather than
		// running to completion synchronously and resetting peak to 1.
		await new Promise((r) => setTimeout(r, 5));
		inFlight--;
		return gzipOf({ path });
	};

	const runsWithTracks = Array.from({ length: 20 }, (_, i) => ({
		id: `r-${i}`,
		track_url: `uid/r-${i}.json.gz`
	}));

	await buildBackupZip({
		runsOut: runsWithTracks,
		routesOut: [],
		profile: null,
		settingsPrefs: {},
		userId: 'uid',
		exportedFrom: 'test',
		runsWithTracks,
		fetchTrackBytes: fetcher,
		concurrency: 4
	});

	assert.equal(totalCalls, 20);
	assert.ok(peakInFlight <= 4, `concurrency: 4 must cap simultaneous downloads, peak=${peakInFlight}`);
	assert.ok(
		peakInFlight >= 2,
		`with 20 tasks + 5ms-each fetcher we should observe parallelism, peak=${peakInFlight}`
	);
});

test('buildBackupZip: a single download failure does not sink the rest', async () => {
	const fetcher = async (path: string): Promise<Uint8Array> => {
		if (path === 'uid/r-bad.json.gz') {
			throw new Error('synthetic download error');
		}
		return gzipOf({ path });
	};

	const runs = [
		{ id: 'r-good-1', track_url: 'uid/r-good-1.json.gz' },
		{ id: 'r-bad', track_url: 'uid/r-bad.json.gz' },
		{ id: 'r-good-2', track_url: 'uid/r-good-2.json.gz' }
	];

	const archive = await buildBackupZip({
		runsOut: runs,
		routesOut: [],
		profile: null,
		settingsPrefs: {},
		userId: 'uid',
		exportedFrom: 'test',
		runsWithTracks: runs,
		fetchTrackBytes: fetcher,
		concurrency: 4
	});

	const buf = new Uint8Array(await archive.blob.arrayBuffer());
	const zip = await JSZip.loadAsync(buf);
	// Healthy runs land in the archive; the bad one is absent.
	assert.ok(zip.file('tracks/r-good-1.json.gz'), 'r-good-1 track must be present');
	assert.ok(zip.file('tracks/r-good-2.json.gz'), 'r-good-2 track must be present');
	assert.equal(zip.file('tracks/r-bad.json.gz'), null);

	// Manifest counts reflect only the tracks actually added — and, since
	// the skip is the ONLY way this file can be short of the account, the
	// manifest says outright that it is.
	const manifest = JSON.parse(await zip.file('manifest.json')!.async('string'));
	assert.equal(manifest.counts.tracks, 2);
	assert.equal(manifest.complete, false);
	assert.deepEqual(manifest.incomplete, ['tracks']);

	// The same verdict reaches the caller, which is what the download
	// surface discloses without re-reading the zip it just built.
	assert.equal(archive.incomplete.length, 1);
	assert.equal(archive.blobsWanted, 3);
	assert.equal(archive.blobsWritten, 2);
});

test('buildBackupZip: a whole archive declares itself complete', async () => {
	const runs = [
		{ id: 'r-1', track_url: 'uid/r-1.json.gz' },
		{ id: 'r-2', track_url: 'uid/r-2.json.gz' }
	];
	const archive = await buildBackupZip({
		runsOut: runs,
		routesOut: [],
		profile: null,
		settingsPrefs: {},
		userId: 'uid',
		exportedFrom: 'test',
		runsWithTracks: runs,
		fetchTrackBytes: async () => gzipOf([])
	});

	const zip = await JSZip.loadAsync(new Uint8Array(await archive.blob.arrayBuffer()));
	const manifest = JSON.parse(await zip.file('manifest.json')!.async('string'));
	// Both halves are emitted on the happy path too: a reader must be able
	// to tell "this writer says it is whole" from "this writer says
	// nothing", which is what an older archive does.
	assert.equal(manifest.complete, true);
	assert.deepEqual(manifest.incomplete, []);
	assert.deepEqual(archive.incomplete, []);
	assert.equal(archive.blobsWanted, 2);
	assert.equal(archive.blobsWritten, 2);
});

test('buildBackupZip: empty runsWithTracks produces a valid manifest-only archive', async () => {
	let calls = 0;
	const fetcher = async (): Promise<Uint8Array> => {
		calls++;
		return gzipOf([]);
	};

	const archive = await buildBackupZip({
		runsOut: [],
		routesOut: [],
		profile: null,
		settingsPrefs: {},
		userId: 'uid',
		exportedFrom: 'test',
		runsWithTracks: [],
		fetchTrackBytes: fetcher
	});

	assert.equal(calls, 0, 'no tracks → no fetcher calls');
	const buf = new Uint8Array(await archive.blob.arrayBuffer());
	const zip = await JSZip.loadAsync(buf);
	const manifest = JSON.parse(await zip.file('manifest.json')!.async('string'));
	assert.equal(manifest.counts.tracks, 0);
	// An account with nothing to download is whole, not short.
	assert.equal(manifest.complete, true);
	assert.deepEqual(manifest.incomplete, []);
});

test('buildBackupZip: rejects concurrency < 1', async () => {
	await assert.rejects(
		() =>
			buildBackupZip({
				runsOut: [],
				routesOut: [],
				profile: null,
				settingsPrefs: {},
				userId: 'uid',
				exportedFrom: 'test',
				runsWithTracks: [],
				fetchTrackBytes: async () => new Uint8Array(),
				concurrency: 0
			}),
		/concurrency must be >= 1/
	);
});

test('buildBackupZip: emits stage + tracks + done progress events in order', async () => {
	const stages: string[] = [];
	await buildBackupZip({
		runsOut: [{ id: 'r-1' }],
		routesOut: [],
		profile: null,
		settingsPrefs: {},
		userId: 'uid',
		exportedFrom: 'test',
		runsWithTracks: [{ id: 'r-1', track_url: 'uid/r-1.json.gz' }],
		fetchTrackBytes: async () => gzipOf([]),
		onProgress: (p) => stages.push(p.stage)
	});

	assert.ok(stages.includes('tracks'));
	assert.ok(stages.includes('writing'));
	assert.equal(stages[stages.length - 1], 'done');
});

test('buildBackupZip: profile id field is stripped to keep the archive re-homeable', async () => {
	const archive = await buildBackupZip({
		runsOut: [],
		routesOut: [],
		profile: { id: 'old-user-uuid', username: 'tester' },
		settingsPrefs: {},
		userId: 'new-user-uuid',
		exportedFrom: 'test',
		runsWithTracks: [],
		fetchTrackBytes: async () => new Uint8Array()
	});
	const buf = new Uint8Array(await archive.blob.arrayBuffer());
	const zip = await JSZip.loadAsync(buf);
	const profile = JSON.parse(await zip.file('profile.json')!.async('string'));
	assert.equal(profile.profile.username, 'tester');
	assert.equal(profile.profile.id, undefined, 'id must be stripped');
});

// ─────────────────── the row reads ───────────────────
//
// PostgREST answers an unranged SELECT with 200 and a silently clamped
// 1000 rows, so the reads behind a backup walk the table (decisions
// § 668 found it on mobile, § 675 on web). They walk it by keyset
// cursor: an OFFSET walk over a history that a sync or a delete changes
// mid-read archives one run twice and drops another under a manifest
// saying `complete` (§ 1927). The walk itself — paging, stop rule, a
// mid-walk delete or insert — is pinned in `core/keyset_page.test.ts`.

test('createBackup: the runs and routes reads are keyset walks over a total order, never offsets', () => {
	const source = readFileSync(resolve('src/lib/backup/backup.ts'), 'utf-8');
	const body = source.slice(
		source.indexOf('export async function createBackup'),
		source.indexOf('async function defaultTrackFetcher'),
	);
	assert.ok(body.length > 0, 'createBackup body not found — did the file move?');
	assert.doesNotMatch(body, /\.range\(/, 'a backup read must not walk by offset');
	for (const order of ['BACKUP_RUN_ORDER', 'BACKUP_ROUTE_ORDER']) {
		assert.match(body, new RegExp(`walkKeyset\\b[^(]*\\(${order},`), `${order} must drive a walk`);
		assert.match(
			body,
			new RegExp(`for \\(const k of ${order}\\)[\\s\\S]*?\\.order\\(k\\.column`),
			`the ${order} walk must sort by the order its cursor is taken in`,
		);
	}
	const run = /const BACKUP_RUN_ORDER[^=]*= \[([^\]]*)\]/.exec(source);
	const route = /const BACKUP_ROUTE_ORDER[^=]*= \[([^\]]*)\]/.exec(source);
	assert.ok(run && route, 'the order constants moved — re-anchor');
	const columns = (m: RegExpExecArray) => [...m[1].matchAll(/column: '(\w+)'/g)].map((c) => c[1]);
	assert.deepEqual(columns(run), ['started_at', 'id'], 'runs end on the primary key');
	assert.deepEqual(columns(route), ['id'], 'routes order on the primary key');
});

test('createBackup: a walk that came up short names its section in the manifest', () => {
	const source = readFileSync(resolve('src/lib/backup/backup.ts'), 'utf-8');
	assert.match(source, /runsRead\.complete \? \[\] : \['runs'\]/);
	assert.match(source, /routesRead\.complete \? \[\] : \['routes'\]/);
	assert.match(
		source,
		/if \(runsRead\.error && runsRead\.rows\.length === 0\) throw dbError\(runsRead\.error\)/,
		'a runs read that returned nothing is a failed backup, not an empty one',
	);
});

test("buildBackupZip: a caller-reported short read joins the writer's own in the manifest", async () => {
	const runs = [{ id: 'r-1', track_url: 'uid/r-1.json.gz' }];
	const archive = await buildBackupZip({
		runsOut: runs,
		routesOut: [],
		profile: null,
		settingsPrefs: {},
		userId: 'uid',
		exportedFrom: 'test',
		runsWithTracks: runs,
		fetchTrackBytes: async () => {
			throw new Error('storage offline');
		},
		incompleteSections: ['runs']
	});

	const zip = await JSZip.loadAsync(new Uint8Array(await archive.blob.arrayBuffer()));
	const manifest = JSON.parse(await zip.file('manifest.json')!.async('string'));
	assert.equal(manifest.complete, false);
	// Sorted + de-duplicated, matching the Go writer's manifest.
	assert.deepEqual(manifest.incomplete, ['runs', 'tracks']);
	assert.deepEqual(archive.incomplete, ['runs', 'tracks']);
});

// `createBackup` itself needs supabase-js (and therefore SvelteKit's
// `$app/env` virtual module), so its read-grading is pinned at the source
// level. The claim under test is the whole point of decisions § 675/§ 676:
// an archive may only say `complete: true` when every read behind it
// answered in full. The runs + routes reads were fixed there; the profile
// RPC and the user_settings read went on discarding their error, so a
// failed read shipped a null profile under a manifest claiming whole.
test('createBackup: every read behind the archive grades its error', () => {
	const source = readFileSync(resolve('src/lib/backup/backup.ts'), 'utf-8');
	const body = source.slice(
		source.indexOf('export async function createBackup'),
		source.indexOf('async function defaultTrackFetcher'),
	);
	assert.ok(body.length > 0, 'createBackup body not found — did the file move?');

	// A destructure of `data` with no `error` beside it is a discarded read.
	const reads = [...body.matchAll(/const \{([^}]*)\}\s*=\s*await supabase/g)];
	assert.ok(reads.length >= 2, 'expected the profile + settings reads');
	for (const [, bindings] of reads) {
		assert.match(
			bindings,
			/\berror\b/,
			`a supabase read in createBackup discards its error: {${bindings.trim()}}`,
		);
	}

	// And the graded errors have to reach the manifest, not merely be bound.
	assert.match(
		body,
		/profileErr\s*\?\s*\['profile'\]/,
		'a failed profile read must name its section in incompleteSections',
	);
	assert.match(
		body,
		/settingsErr\s*\?\s*\['settings_prefs'\]/,
		'a failed settings read must name its section in incompleteSections',
	);
});

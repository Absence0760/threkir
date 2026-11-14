import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { generateKeyPairSync, verify } from 'node:crypto';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
	API,
	NOTES_MAX,
	PUBLISHED,
	RAMP,
	SCOPE,
	TOKEN_LIFETIME_S,
	TOKEN_URI,
	UPLOAD_API,
	advance,
	buildAssertion,
	describeError,
	extractPlayNotes,
	isUploaded,
	main,
	makeApi,
	nextFraction,
	promote,
	readServiceAccount,
	uploadToFormFactor,
} from './play_release.mjs';

/**
 * No network and no real credential: the service account key is generated
 * here, and Google Play is an in-memory fake of the Edits API that answers
 * the endpoints the script calls in the shapes the Android Publisher v3
 * reference gives, and refuses what that reference says Play refuses (a
 * userFraction outside (0, 1) on a staged release, one on a completed release,
 * a status outside the enum, a stale edit). Every request is recorded.
 */

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const ANDROID = readFileSync(resolve(root, '.github/workflows/release-android.yml'), 'utf8');
const ROLLOUT = readFileSync(resolve(root, '.github/workflows/play-rollout.yml'), 'utf8');
const WEAR = readFileSync(resolve(root, '.github/workflows/release-watch-wear.yml'), 'utf8');

const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const PEM = /** @type {string} */ (privateKey.export({ type: 'pkcs8', format: 'pem' }));
const EMAIL = 'release@threkir-play.iam.gserviceaccount.com';
const ACCOUNT_JSON = JSON.stringify({ type: 'service_account', client_email: EMAIL, private_key: PEM, private_key_id: 'abc' });
const TOKEN = 'ya29.fake-access-token-never-printed';
const NOW = 1_800_000_000;
const PKG = 'com.threkir.app';

/** @typedef {import('./play_release.mjs').Release} Release */

/**
 * Form-factor tracks (`wear:qa`, ...) live beside production in `tracks`; a
 * media upload adds the version code `uploadReads` names to `bundles`.
 *
 * @param {{ bundles?: string[], releases?: Release[], states?: Record<string, string>, inReview?: boolean, commitStatus?: number,
 *   tracks?: Record<string, Release[]>, uploadReads?: string }} [seed]
 */
function fakePlay(seed = {}) {
	const state = {
		bundles: seed.bundles ?? ['5158'],
		/** @type {Release[]} */
		releases: structuredClone(seed.releases ?? []),
		states: seed.states ?? {},
		inReview: seed.inReview ?? false,
		commitStatus: seed.commitStatus ?? 0,
		/** @type {Record<string, Release[]>} */
		tracks: structuredClone(seed.tracks ?? {}),
		uploadReads: seed.uploadReads,
		/** @type {number[]} */
		uploads: [],
		/** @type {Array<{ method: string, path: string, body?: any }>} */
		requests: [],
		/** @type {string[]} */
		refused: [],
		/** @type {Map<string, Release[]>} */
		edits: new Map(),
		/** @type {Map<string, { tracks: Record<string, Release[]>, bundles: string[] }>} */
		editExtras: new Map(),
		nextEdit: 1,
		tokens: 0,
	};
	/** @param {number} status @param {unknown} [body] */
	const reply = (status, body) => ({ ok: status < 300, status, text: async () => (body === undefined ? '' : JSON.stringify(body)) });
	/** @param {number} status @param {string} message */
	const refuse = (status, message) => {
		state.refused.push(message);
		return reply(status, { error: { code: status, message, status: status === 404 ? 'NOT_FOUND' : 'INVALID_ARGUMENT' } });
	};

	/** @param {Release[]} releases @param {string[]} [bundles] */
	function invalid(releases, bundles = state.bundles) {
		for (const r of releases) {
			if (!['draft', 'inProgress', 'halted', 'completed'].includes(/** @type {string} */ (r.status))) return `status ${r.status} is not a Status`;
			if (!Array.isArray(r.versionCodes) || !r.versionCodes.every((c) => typeof c === 'string')) return 'versionCodes must be strings';
			if (!r.versionCodes.every((c) => bundles.includes(c))) return 'a version code has no bundle';
			if (r.status === 'inProgress' && !(typeof r.userFraction === 'number' && r.userFraction > 0 && r.userFraction < 1)) return 'a staged release needs 0 < userFraction < 1';
			if (r.status === 'completed' && r.userFraction !== undefined) return 'a completed release takes no userFraction';
			for (const n of r.releaseNotes ?? []) if ([...n.text].length > NOTES_MAX) return 'release notes over 500 characters';
		}
		return null;
	}

	/** @type {import('./play_release.mjs').Fetcher} */
	const fetcher = async (url, init) => {
		const body =
			init.body === undefined ? undefined : init.headers['Content-Type']?.includes('json') ? JSON.parse(/** @type {string} */ (init.body)) : init.body;
		if (url === TOKEN_URI) {
			state.requests.push({ method: init.method, path: 'token' });
			const form = new URLSearchParams(/** @type {string} */ (init.body));
			if (form.get('grant_type') !== 'urn:ietf:params:oauth:grant-type:jwt-bearer') return refuse(400, 'unsupported_grant_type');
			const [h, c, sig] = /** @type {string} */ (form.get('assertion')).split('.');
			if (!verify('sha256', Buffer.from(`${h}.${c}`), publicKey, Buffer.from(sig, 'base64url'))) {
				return { ok: false, status: 400, text: async () => JSON.stringify({ error: 'invalid_grant', error_description: 'Invalid JWT Signature.' }) };
			}
			state.tokens += 1;
			return reply(200, { access_token: TOKEN, token_type: 'Bearer', expires_in: 3600 });
		}
		const media = url.startsWith(UPLOAD_API);
		assert.ok(media || url.startsWith(API), `a request left the Android Publisher API: ${url}`);
		const [pathOnly, query = ''] = url.slice((media ? UPLOAD_API : API).length).split('?');
		state.requests.push({ method: init.method, path: pathOnly + (query ? `?${query}` : ''), body });
		if (init.headers.Authorization !== `Bearer ${TOKEN}`) return refuse(401, 'Request had invalid authentication credentials.');
		const app = `/applications/${PKG}`;
		if (!pathOnly.startsWith(app)) return refuse(404, 'Package not found.');
		const rest = pathOnly.slice(app.length);

		if (init.method === 'GET' && rest === '/tracks/production/releases') {
			return reply(200, {
				releases: state.releases
					.filter((r) => r.status !== 'draft')
					.map((r) => ({
						track: 'production',
						activeArtifacts: (r.versionCodes ?? []).map((v) => ({ versionCode: Number(v) })),
						releaseLifecycleState: state.states[(r.versionCodes ?? [])[0]] ?? PUBLISHED,
					})),
			});
		}
		if (init.method === 'POST' && rest === '/edits') {
			const id = `edit${state.nextEdit++}`;
			// Play keeps one open edit per user per app.
			state.edits.clear();
			state.editExtras.clear();
			state.edits.set(id, structuredClone(state.releases));
			state.editExtras.set(id, { tracks: structuredClone(state.tracks), bundles: [...state.bundles] });
			return reply(200, { id, expiryTimeSeconds: String(NOW + 3600) });
		}
		const m = /^\/edits\/([^/:]+)(.*)$/.exec(rest);
		if (!m) return refuse(404, `No such endpoint: ${init.method} ${rest}`);
		const [, editId, tail] = m;
		const staged = state.edits.get(editId);
		if (!staged) return refuse(404, 'This Edit has been deleted.');

		const extras = /** @type {{ tracks: Record<string, Release[]>, bundles: string[] }} */ (state.editExtras.get(editId));

		if (media) {
			if (init.method !== 'POST' || tail !== '/bundles' || query !== 'uploadType=media') return refuse(404, `No such upload endpoint: ${init.method} ${tail}?${query}`);
			if (init.headers['Content-Type'] !== 'application/octet-stream' || !(init.body instanceof Uint8Array)) return refuse(400, 'Media upload without an octet-stream body.');
			const code = /** @type {string} */ (state.uploadReads);
			if (extras.bundles.includes(code)) return refuse(403, 'APK specifies a version code that has already been used.');
			state.uploads.push(init.body.length);
			extras.bundles.push(code);
			return reply(200, { versionCode: Number(code), sha1: 'x', sha256: 'y' });
		}
		if (init.method === 'DELETE' && tail === '') {
			state.edits.delete(editId);
			state.editExtras.delete(editId);
			return reply(204);
		}
		if (init.method === 'GET' && tail === '/bundles') {
			return reply(200, { kind: 'androidpublisher#bundlesListResponse', bundles: extras.bundles.map((v) => ({ versionCode: Number(v), sha1: 'x', sha256: 'y' })) });
		}
		if (init.method === 'GET' && tail === '/tracks') {
			const names = ['production', 'beta', 'alpha', 'internal', ...Object.keys(extras.tracks)];
			return reply(200, { kind: 'androidpublisher#tracksListResponse', tracks: names.map((track) => ({ track })) });
		}
		const ff = /^\/tracks\/([a-z_]+:[a-z]+)$/.exec(tail);
		if (ff && ff[1] in extras.tracks) {
			const track = ff[1];
			if (init.method === 'GET') return reply(200, extras.tracks[track].length ? { track, releases: extras.tracks[track] } : { track });
			if (init.method === 'PUT') {
				if (body?.track !== track) return refuse(400, 'Track name in the body does not match the URL.');
				const problem = invalid(body.releases ?? [], extras.bundles);
				if (problem) return refuse(400, problem);
				extras.tracks[track] = structuredClone(body.releases);
				return reply(200, body);
			}
		}
		if (ff) return refuse(404, `Track not found: ${ff[1]}`);
		if (init.method === 'GET' && tail === '/tracks/production') {
			return reply(200, staged.length ? { track: 'production', releases: staged } : { track: 'production' });
		}
		if (init.method === 'PUT' && tail === '/tracks/production') {
			if (body?.track !== 'production') return refuse(400, 'Track name in the body does not match the URL.');
			const problem = invalid(body.releases ?? [], extras.bundles);
			if (problem) return refuse(400, problem);
			state.edits.set(editId, structuredClone(body.releases));
			return reply(200, body);
		}
		if (init.method === 'POST' && tail === ':commit') {
			if (init.body !== undefined) return refuse(400, 'The request body must be empty.');
			if (query !== 'changesInReviewBehavior=ERROR_IF_IN_REVIEW') return refuse(400, `commit sent with "${query}", which would cancel a review in progress`);
			if (state.commitStatus) return refuse(state.commitStatus, 'Backend error.');
			if (state.inReview) return refuse(400, 'You already have changes in review. Cancel this review or wait for it to complete before you try again.');
			state.releases = structuredClone(staged);
			state.tracks = structuredClone(extras.tracks);
			state.bundles = [...extras.bundles];
			state.edits.delete(editId);
			state.editExtras.delete(editId);
			return reply(200, { id: editId });
		}
		return refuse(404, `No such endpoint: ${init.method} ${rest}`);
	};
	return Object.assign(state, {
		fetcher,
		api: makeApi({ fetcher, assertion: () => buildAssertion({ ...readServiceAccount(ACCOUNT_JSON), nowS: NOW }) }),
		writes: () => state.requests.filter((r) => r.method !== 'GET' && r.path !== 'token' && !(r.method === 'POST' && r.path.endsWith('/edits')) && r.method !== 'DELETE'),
	});
}

const SERVING = { versionCodes: ['5100'], status: 'completed', releaseNotes: [{ language: 'en-US', text: 'Old.' }] };
const NOTES = 'Plans chain now.\n- Park courses.';

// --- Release notes ------------------------------------------------------------

test("the Play notes are the Release body's What's New section, at Play's 500-character limit", () => {
	assert.equal(extractPlayNotes("## What's New\nHello\n\n## What's Changed\n* feat: x"), 'Hello');
	const exact = 'x'.repeat(NOTES_MAX);
	assert.equal(extractPlayNotes(`## What's New\n${exact}`), exact);
	assert.throws(() => extractPlayNotes(`## What's New\n${exact}y`), /501 characters, over Google Play's 500.*never cut short/);
	assert.throws(() => extractPlayNotes("## What's Changed\n* feat: x"), /no "## What's New" section.*Google Play users.*Generated notes are never used/s);
	assert.throws(() => extractPlayNotes("## What's New\n<!-- placeholder -->"), /is empty/);
});

test('the notes command writes the section and refuses a body without one', async () => {
	const dir = mkdtempSync(join(tmpdir(), 'play-notes-'));
	writeFileSync(join(dir, 'body.md'), "## What's New\nFaster sync.\n");
	const lines = /** @type {string[]} */ ([]);
	await main(['notes', join(dir, 'body.md'), join(dir, 'out.txt')], {}, { print: (l) => lines.push(l) });
	assert.equal(readFileSync(join(dir, 'out.txt'), 'utf8'), 'Faster sync.');
	writeFileSync(join(dir, 'bare.md'), '## What\'s Changed\n* x');
	await assert.rejects(main(['notes', join(dir, 'bare.md'), join(dir, 'out2.txt')], {}), /no "## What's New" section/);
});

// --- Credentials ----------------------------------------------------------------

test('the assertion is an RS256 JWT with the claims Google checks, inside its one-hour cap', () => {
	const jwt = buildAssertion({ ...readServiceAccount(ACCOUNT_JSON), nowS: NOW });
	const [h, c, sig] = jwt.split('.');
	assert.deepEqual(JSON.parse(Buffer.from(h, 'base64url').toString()), { alg: 'RS256', typ: 'JWT' });
	assert.deepEqual(JSON.parse(Buffer.from(c, 'base64url').toString()), { iss: EMAIL, scope: SCOPE, aud: TOKEN_URI, iat: NOW, exp: NOW + 3600 });
	assert.ok(TOKEN_LIFETIME_S <= 3600);
	assert.ok(verify('sha256', Buffer.from(`${h}.${c}`), publicKey, Buffer.from(sig, 'base64url')));
});

test('a bad service account file names what is wrong and never echoes it', () => {
	/** @type {Array<[string | undefined, RegExp]>} */
	const cases = [
		[undefined, /unset/],
		['{not json', /not JSON/],
		[JSON.stringify({ type: 'authorized_user' }), /not a service account key file/],
		[JSON.stringify({ type: 'service_account', private_key: PEM }), /no client_email/],
		[JSON.stringify({ type: 'service_account', client_email: EMAIL, private_key: 'secret-looking-garbage' }), /no readable private_key/],
	];
	for (const [raw, pattern] of cases) {
		assert.throws(() => readServiceAccount(raw), (err) => {
			assert.match(/** @type {Error} */ (err).message, pattern);
			assert.ok(!/** @type {Error} */ (err).message.includes('secret-looking-garbage'));
			assert.ok(!/** @type {Error} */ (err).message.includes('PRIVATE KEY'));
			return true;
		});
	}
});

test("Google's error bodies are described by status and message, anything else by length", () => {
	assert.equal(describeError(JSON.stringify({ error: { code: 403, message: 'The caller does not have permission', status: 'PERMISSION_DENIED' } })), 'PERMISSION_DENIED: The caller does not have permission');
	assert.equal(describeError(JSON.stringify({ error: 'invalid_grant', error_description: 'Invalid JWT Signature.' })), 'invalid_grant: Invalid JWT Signature.');
	assert.equal(describeError('<html>token=abc</html>'), "a 22-character body that is not Google's error format");
});

// --- Ramp -----------------------------------------------------------------------

test("the ramp mirrors Apple's 7-day phased release and ends completed", () => {
	assert.deepEqual(RAMP, [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1]);
	assert.deepEqual(
		[0.01, 0.02, 0.05, 0.1, 0.2, 0.5].map(nextFraction),
		[0.02, 0.05, 0.1, 0.2, 0.5, null],
	);
	assert.equal(nextFraction(0.03), 0.05, 'a fraction set by hand between steps moves to the next step above it');
	assert.equal(nextFraction(0.7), null);
});

// --- promote --------------------------------------------------------------------

test("the app's first production release goes out completed, since Play cannot stage it", async () => {
	const play = fakePlay();
	const out = await promote({ api: play.api, versionCode: '5158', notes: NOTES });
	assert.equal(out.level, 'notice');
	assert.match(out.message, /first production release.*every user/);
	assert.deepEqual(play.releases, [{ versionCodes: ['5158'], status: 'completed', releaseNotes: [{ language: 'en-US', text: NOTES }] }]);
	assert.deepEqual(play.refused, []);
});

test('an update goes out as a staged rollout at the first ramp step with en-US notes', async () => {
	const play = fakePlay({ bundles: ['5100', '5158'], releases: [SERVING] });
	const out = await promote({ api: play.api, versionCode: '5158', notes: NOTES });
	assert.equal(out.level, 'info');
	assert.match(out.message, /staged rollout at 1%/);
	assert.deepEqual(play.releases, [{ versionCodes: ['5158'], status: 'inProgress', userFraction: 0.01, releaseNotes: [{ language: 'en-US', text: NOTES }] }]);
	assert.equal(play.edits.size, 0, 'the edit was left open');
	assert.deepEqual(play.refused, []);
});

test('promoting a build production already carries is a no-op success, and writes nothing', async () => {
	const play = fakePlay({ bundles: ['5100', '5158'], releases: [SERVING] });
	await promote({ api: play.api, versionCode: '5158', notes: NOTES });
	const before = play.writes().length;
	const again = await promote({ api: play.api, versionCode: '5158', notes: NOTES });
	assert.match(again.message, /already on production \(inProgress, 1%\)/);
	assert.equal(play.writes().length, before);
	assert.equal(play.edits.size, 0, 'the read-only edit was not discarded');
});

test('a halted build is never resumed by a re-promote', async () => {
	const play = fakePlay({ bundles: ['5100', '5158'], releases: [SERVING, { versionCodes: ['5158'], status: 'halted', userFraction: 0.05 }] });
	const out = await promote({ api: play.api, versionCode: '5158', notes: NOTES });
	assert.equal(out.level, 'notice');
	assert.match(out.message, /halted.*Play Console/);
	assert.equal(play.writes().length, 0);
});

test('another build still rolling out fails closed, naming it', async () => {
	const play = fakePlay({ bundles: ['5100', '5150', '5158'], releases: [SERVING, { versionCodes: ['5150'], status: 'inProgress', userFraction: 0.2 }] });
	await assert.rejects(promote({ api: play.api, versionCode: '5158', notes: NOTES }), /still rolling out version code 5150 at 20%/);
	assert.equal(play.writes().length, 0);
});

test('a version code Play holds no bundle for fails before anything is written', async () => {
	const play = fakePlay({ bundles: ['5100'], releases: [SERVING] });
	await assert.rejects(promote({ api: play.api, versionCode: '5158', notes: NOTES }), /no bundle with version code 5158/);
	assert.equal(play.writes().length, 0);
});

test('notes over the limit fail before an edit is opened', async () => {
	const play = fakePlay();
	await assert.rejects(promote({ api: play.api, versionCode: '5158', notes: 'x'.repeat(NOTES_MAX + 1) }), /never cut short/);
	assert.equal(play.requests.length, 0);
});

test('a failing commit fails the run with the status and message only, and a re-run then lands', async () => {
	const play = fakePlay({ bundles: ['5100', '5158'], releases: [SERVING], commitStatus: 500 });
	await assert.rejects(promote({ api: play.api, versionCode: '5158', notes: NOTES }), (err) => {
		const message = /** @type {Error} */ (err).message;
		assert.match(message, /:commit with HTTP 500: INVALID_ARGUMENT: Backend error\./);
		assert.ok(!message.includes(TOKEN) && !message.includes('PRIVATE KEY'));
		return true;
	});
	assert.deepEqual(play.releases, [SERVING], 'a failed commit changed production');
	play.commitStatus = 0;
	assert.match((await promote({ api: play.api, versionCode: '5158', notes: NOTES })).message, /staged rollout at 1%/);
});

test('changes already in review fail the promote rather than cancel that review', async () => {
	const play = fakePlay({ bundles: ['5100', '5158'], releases: [SERVING], inReview: true });
	await assert.rejects(promote({ api: play.api, versionCode: '5158', notes: NOTES }), /other changes in review.*re-run/);
	assert.deepEqual(play.releases, [SERVING]);
});

// --- advance --------------------------------------------------------------------

test('advance walks a staged rollout up the ramp, one step per run, to completed', async () => {
	const play = fakePlay({ bundles: ['5100', '5158'], releases: [SERVING] });
	await promote({ api: play.api, versionCode: '5158', notes: NOTES });
	const seen = [];
	for (let day = 0; day < 6; day++) {
		await advance({ api: play.api });
		const r = play.releases.find((x) => x.versionCodes?.includes('5158'));
		seen.push(r?.status === 'completed' ? 'completed' : r?.userFraction);
	}
	assert.deepEqual(seen, [0.02, 0.05, 0.1, 0.2, 0.5, 'completed']);
	assert.deepEqual(play.releases.map((r) => r.status), ['completed'], 'the superseded release was not replaced');
	assert.equal(play.releases[0].userFraction, undefined);
	assert.deepEqual(play.releases[0].releaseNotes, [{ language: 'en-US', text: NOTES }], 'the notes were dropped on the way');
	assert.match((await advance({ api: play.api })).message, /Nothing is rolling out/);
	assert.deepEqual(play.refused, []);
});

test('mid-ramp, the release still being superseded is written back unchanged', async () => {
	const play = fakePlay({ bundles: ['5100', '5158'], releases: [SERVING, { versionCodes: ['5158'], status: 'inProgress', userFraction: 0.05 }] });
	await advance({ api: play.api });
	assert.deepEqual(play.releases, [SERVING, { versionCodes: ['5158'], status: 'inProgress', userFraction: 0.1 }]);
});

test('a halted rollout is skipped with a notice and never resumed', async () => {
	const play = fakePlay({ bundles: ['5100', '5158'], releases: [SERVING, { versionCodes: ['5158'], status: 'halted', userFraction: 0.05 }] });
	const out = await advance({ api: play.api });
	assert.equal(out.level, 'notice');
	assert.match(out.message, /halted.*resumed in Play Console/);
	assert.equal(play.writes().length, 0);
	assert.equal(play.releases[1].status, 'halted');
});

test('a release still in review, or approved and unpublished, is not advanced', async () => {
	for (const state of ['RELEASE_LIFECYCLE_STATE_IN_REVIEW', 'RELEASE_LIFECYCLE_STATE_APPROVED_NOT_PUBLISHED']) {
		const play = fakePlay({ bundles: ['5100', '5158'], releases: [SERVING, { versionCodes: ['5158'], status: 'inProgress', userFraction: 0.01 }], states: { 5158: state } });
		const out = await advance({ api: play.api });
		assert.equal(out.level, 'notice');
		assert.match(out.message, new RegExp(state));
		assert.equal(play.writes().length, 0);
	}
});

test('other changes in review keep the rollout where it is today, with a notice', async () => {
	const play = fakePlay({ bundles: ['5100', '5158'], releases: [SERVING, { versionCodes: ['5158'], status: 'inProgress', userFraction: 0.2 }], inReview: true });
	const out = await advance({ api: play.api });
	assert.equal(out.level, 'notice');
	assert.match(out.message, /stays at 20% today/);
	assert.equal(play.releases[1].userFraction, 0.2);
});

test('a failing commit on advance fails the run and leaves production as it was', async () => {
	const play = fakePlay({ bundles: ['5100', '5158'], releases: [SERVING, { versionCodes: ['5158'], status: 'inProgress', userFraction: 0.2 }], commitStatus: 503 });
	await assert.rejects(advance({ api: play.api }), /:commit with HTTP 503/);
	assert.equal(play.releases[1].userFraction, 0.2);
});

test('nothing on production is a no-op', async () => {
	const play = fakePlay();
	assert.match((await advance({ api: play.api })).message, /Nothing is rolling out/);
	assert.equal(play.writes().length, 0);
});

// --- uploaded and the CLI -----------------------------------------------------------

test('uploaded answers from the bundles Play holds and writes the step output', async () => {
	const play = fakePlay({ bundles: ['5100', '5158'] });
	assert.equal(await isUploaded({ api: play.api, versionCode: '5158' }), true);
	assert.equal(await isUploaded({ api: play.api, versionCode: '5159' }), false);
	assert.equal(play.edits.size, 0);
	const dir = mkdtempSync(join(tmpdir(), 'play-uploaded-'));
	const out = join(dir, 'out');
	writeFileSync(out, '');
	await main(['uploaded', '--version-code', '5158'], { GITHUB_OUTPUT: out }, { apiFor: () => play.api, print: () => {} });
	assert.equal(readFileSync(out, 'utf8'), 'uploaded=true\n');
});

test('the CLI refuses a bad version code or package before any request', async () => {
	const play = fakePlay();
	const deps = { apiFor: () => play.api, print: () => {} };
	await assert.rejects(main(['promote', '--version-code', '0x10', '--notes', '/dev/null'], {}, deps), /positive integer/);
	await assert.rejects(main(['advance', '--package', 'not a package'], {}, deps), /not an Android package name/);
	await assert.rejects(main(['bogus'], {}, deps), /Usage/);
	assert.equal(play.requests.length, 0);
});

test('a refused token names the status and the service account, never the assertion', async () => {
	const { privateKey: other } = generateKeyPairSync('rsa', { modulusLength: 2048 });
	const play = fakePlay();
	const api = makeApi({ fetcher: play.fetcher, assertion: () => buildAssertion({ clientEmail: EMAIL, key: other, nowS: NOW }) });
	await assert.rejects(advance({ api }), (err) => {
		const message = /** @type {Error} */ (err).message;
		assert.match(message, /token endpoint refused the service account with HTTP 400: invalid_grant: Invalid JWT Signature\./);
		assert.ok(!message.includes('eyJ'), 'the assertion leaked into the error');
		return true;
	});
});

// --- upload: a form factor's bundle onto its internal track -----------------------

const WEAR_CODE = '1000005160';
const AAB = new Uint8Array([0x50, 0x4b, 0x03, 0x04, 1, 2, 3]);

test("a Wear bundle lands on the Wear internal track by the name Play lists, never on the phone's tracks", async () => {
	for (const name of ['wear:qa', 'wear:internal']) {
		const play = fakePlay({ releases: [SERVING], bundles: ['5100'], tracks: { [name]: [] }, uploadReads: WEAR_CODE });
		const outcome = await uploadToFormFactor({ api: play.api, formFactor: 'wear', versionCode: WEAR_CODE, bundle: AAB });
		assert.equal(outcome.message, `Version code ${WEAR_CODE} is on ${name} of ${PKG}.`);
		assert.deepEqual(play.tracks[name], [{ versionCodes: [WEAR_CODE], status: 'completed' }]);
		assert.deepEqual(play.releases, [SERVING], 'the phone production track moved');
		assert.deepEqual(play.uploads, [AAB.length]);
		assert.ok(play.requests.some((r) => r.path.endsWith(':commit?changesInReviewBehavior=ERROR_IF_IN_REVIEW')));
		assert.ok(!play.requests.some((r) => /\/tracks\/(production|internal|beta|alpha)$/.test(r.path)), 'a phone track was read or written');
		assert.equal(play.edits.size, 0);
	}
});

test('the documented wear:qa name wins when Play lists both', async () => {
	const play = fakePlay({ tracks: { 'wear:internal': [], 'wear:qa': [] }, uploadReads: WEAR_CODE });
	await uploadToFormFactor({ api: play.api, formFactor: 'wear', versionCode: WEAR_CODE, bundle: AAB });
	assert.deepEqual(play.tracks['wear:qa'], [{ versionCodes: [WEAR_CODE], status: 'completed' }]);
	assert.deepEqual(play.tracks['wear:internal'], []);
});

test('an app without the Wear form factor fails naming the tracks Play has and the Console step, before any upload', async () => {
	const play = fakePlay({ uploadReads: WEAR_CODE });
	await assert.rejects(uploadToFormFactor({ api: play.api, formFactor: 'wear', versionCode: WEAR_CODE, bundle: AAB }), (err) => {
		const message = /** @type {Error} */ (err).message;
		assert.match(message, /has no wear internal testing track \(looked for wear:qa and wear:internal; Play lists production, beta, alpha, internal\)/);
		assert.match(message, /Advanced settings → Form factors/);
		return true;
	});
	assert.deepEqual(play.uploads, []);
	assert.equal(play.writes().length, 0);
});

test('a re-run after the upload landed is a no-op, and one after a lost commit re-uploads', async () => {
	const done = fakePlay({ bundles: ['5100', WEAR_CODE], tracks: { 'wear:qa': [{ versionCodes: [WEAR_CODE], status: 'completed' }] }, uploadReads: WEAR_CODE });
	assert.match((await uploadToFormFactor({ api: done.api, formFactor: 'wear', versionCode: WEAR_CODE, bundle: AAB })).message, /already on wear:qa; nothing to do/);
	assert.equal(done.writes().length, 0);

	const held = fakePlay({ bundles: [WEAR_CODE], tracks: { 'wear:qa': [] }, uploadReads: WEAR_CODE });
	const lines = /** @type {string[]} */ ([]);
	await uploadToFormFactor({ api: held.api, formFactor: 'wear', versionCode: WEAR_CODE, bundle: AAB, log: (l) => lines.push(l) });
	assert.deepEqual(held.uploads, [], 'a bundle Play holds was uploaded again');
	assert.ok(lines.some((l) => /already holds version code/.test(l)));
	assert.deepEqual(held.tracks['wear:qa'], [{ versionCodes: [WEAR_CODE], status: 'completed' }]);

	const flaky = fakePlay({ tracks: { 'wear:qa': [] }, uploadReads: WEAR_CODE, commitStatus: 500 });
	await assert.rejects(uploadToFormFactor({ api: flaky.api, formFactor: 'wear', versionCode: WEAR_CODE, bundle: AAB }), /HTTP 500: INVALID_ARGUMENT: Backend error\./);
	assert.ok(!flaky.bundles.includes(WEAR_CODE), 'an uncommitted upload persisted');
	flaky.commitStatus = 0;
	await uploadToFormFactor({ api: flaky.api, formFactor: 'wear', versionCode: WEAR_CODE, bundle: AAB });
	assert.deepEqual(flaky.tracks['wear:qa'], [{ versionCodes: [WEAR_CODE], status: 'completed' }]);
});

test('a bundle whose version code is not the one asked for is never committed', async () => {
	const play = fakePlay({ tracks: { 'wear:qa': [] }, uploadReads: '5160' });
	await assert.rejects(uploadToFormFactor({ api: play.api, formFactor: 'wear', versionCode: WEAR_CODE, bundle: AAB }), /read version code 5160 out of the bundle, not 1000005160/);
	assert.deepEqual(play.tracks['wear:qa'], []);
	assert.ok(!play.requests.some((r) => r.path.includes(':commit')));
});

test("changes in review (the phone's release) fail the Wear upload rather than cancel that review", async () => {
	const play = fakePlay({ tracks: { 'wear:qa': [] }, uploadReads: WEAR_CODE, inReview: true });
	await assert.rejects(uploadToFormFactor({ api: play.api, formFactor: 'wear', versionCode: WEAR_CODE, bundle: AAB }), /other changes in review .* would cancel that review/);
	assert.deepEqual(play.tracks['wear:qa'], []);
});

test('the upload CLI reads the bundle file and refuses a bad form factor before any request', async () => {
	const dir = mkdtempSync(join(tmpdir(), 'play-upload-'));
	const aab = join(dir, 'app-release.aab');
	writeFileSync(aab, AAB);
	const play = fakePlay({ tracks: { 'wear:qa': [] }, uploadReads: WEAR_CODE });
	const lines = /** @type {string[]} */ ([]);
	const deps = { apiFor: () => play.api, print: (/** @type {string} */ l) => lines.push(l) };
	await assert.rejects(main(['upload', '--form-factor', 'Wear OS', '--version-code', WEAR_CODE, '--bundle', aab], {}, deps), /not a form factor track prefix/);
	await assert.rejects(main(['upload', '--version-code', WEAR_CODE, '--bundle', aab], {}, deps), /Usage/);
	assert.equal(play.requests.length, 0);
	await main(['upload', '--form-factor', 'wear', '--version-code', WEAR_CODE, '--bundle', aab], {}, deps);
	assert.deepEqual(play.uploads, [AAB.length]);
	assert.equal(lines.at(-1), `Version code ${WEAR_CODE} is on wear:qa of ${PKG}.`);
});

// --- Wiring ---------------------------------------------------------------------

/** @param {string} workflow @param {string} name */
const step = (workflow, name) => {
	const parts = workflow.split(/^ {6}- /m);
	const i = parts.findIndex((s) => s.startsWith(`name: ${name}\n`));
	assert.ok(i >= 0, `no step named "${name}"`);
	return { i, body: parts[i] };
};
/** @param {string} body */
const shell = (body) => body.split('run:')[1] ?? '';

test('release-android.yml checks the notes before the build, skips a duplicate upload, then promotes', () => {
	const job = ANDROID.slice(ANDROID.indexOf('\n  release:\n'), ANDROID.indexOf('\n  promote:\n'));
	assert.ok(job.length > 0, 'the release job is missing or no longer ends at the promote job');
	const notes = step(job, 'The GitHub Release carries a What\'s New for Google Play');
	const build = step(job, 'Build signed AAB');
	const probe = step(job, 'Is this build already on Google Play');
	const upload = step(job, 'Upload to Play Internal');
	const prom = step(job, 'Send the build to production as a staged rollout');
	assert.ok(notes.i < build.i && build.i < probe.i && probe.i < upload.i && upload.i < prom.i);
	assert.match(notes.body, /gh api "repos\/\$GITHUB_REPOSITORY\/releases\/tags\/\$TAG"/);
	assert.match(notes.body, /node scripts\/play_release\.mjs notes "\$RUNNER_TEMP\/release-body\.md" "\$RUNNER_TEMP\/play-notes\.txt"/);
	assert.match(probe.body, /id: uploaded/);
	assert.match(probe.body, /play_release\.mjs uploaded --version-code "\$VERSION_CODE"/);
	assert.match(upload.body, /if: steps\.uploaded\.outputs\.uploaded != 'true'/);
	assert.match(prom.body, /play_release\.mjs promote --version-code "\$VERSION_CODE" --notes "\$RUNNER_TEMP\/play-notes\.txt"/);
	for (const s of [notes, prom]) assert.ok(!/\bif:/.test(s.body) && !/continue-on-error/.test(s.body), 'a gate step is skippable');
	for (const s of [probe, prom]) {
		assert.ok(s.body.includes('PLAY_SERVICE_ACCOUNT_JSON: ${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}'));
		assert.ok(!/\$\{\{ secrets\./.test(shell(s.body)), 'a secret is interpolated into the shell');
	}
	assert.match(job, /environment: production/);
});

test('release-android.yml can promote an existing tag without rebuilding, still behind production', () => {
	assert.match(ANDROID, /workflow_dispatch:\n\s+inputs:\n\s+tag:/);
	const job = ANDROID.slice(ANDROID.indexOf('\n  promote:\n'));
	assert.match(job, /if: github\.event_name == 'workflow_dispatch'/);
	assert.match(job, /environment: production/);
	assert.ok(!/flutter|upload-google-play|keystore/i.test(job), 'the promote-only job builds or uploads');
	for (const body of job.split(/^ {6}- /m)) {
		assert.ok(!/\$\{\{ (inputs|github\.event\.inputs)\.tag \}\}/.test(shell(body)), 'the tag input is interpolated into a shell');
	}
	assert.match(job, /TAG: \$\{\{ inputs\.tag \}\}/);
	const prom = step(job, 'Send the build to production as a staged rollout');
	assert.match(prom.body, /play_release\.mjs promote --version-code "\$VERSION_CODE" --notes "\$RUNNER_TEMP\/play-notes\.txt"/);
	assert.ok(job.indexOf('play_release.mjs notes') < job.indexOf('play_release.mjs promote'));
});

test('play-rollout.yml advances daily on its own reviewer-less environment, not production', () => {
	assert.match(ROLLOUT, /schedule:\n(\s+#.*\n)*\s+- cron: '[^']+'/);
	assert.match(ROLLOUT, /workflow_dispatch:/);
	assert.match(ROLLOUT, /environment: play-rollout/);
	assert.ok(!/environment: production/.test(ROLLOUT), 'a daily job waiting on a reviewer advances nothing');
	assert.match(ROLLOUT, /node scripts\/play_release\.mjs advance/);
	assert.ok(ROLLOUT.includes('PLAY_SERVICE_ACCOUNT_JSON: ${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}'));
});

test("release-watch-wear.yml ships under the phone's package, key and a version-code range the phone's cannot reach", () => {
	const GRADLE = readFileSync(resolve(root, 'apps/watch_wear/android/app/build.gradle.kts'), 'utf8');
	assert.match(GRADLE, /^\s+applicationId = "com\.threkir\.app"$/m, 'the watch is not built as the phone app\'s package');
	assert.match(GRADLE, /^\s+namespace = "com\.runapp\.watchwear"$/m);

	const offset = Number(/^ {2}WEAR_VERSION_CODE_OFFSET: "(\d+)"$/m.exec(WEAR)?.[1]);
	assert.ok(Number.isSafeInteger(offset), 'WEAR_VERSION_CODE_OFFSET is missing from the workflow env');
	// Play's ceiling on a version code, and the phone's codes: the commit count,
	// 5,158 at mobile_android@1.24.0. The phone would need a billion commits to
	// reach the watch's floor; the watch has 1.1 billion before the ceiling.
	const PLAY_MAX = 2_100_000_000;
	assert.ok(offset >= 1_000_000_000, `an offset of ${offset} leaves the watch's codes within reach of the phone's`);
	assert.ok(offset + 1_000_000_000 <= PLAY_MAX, `an offset of ${offset} runs into Play's ${PLAY_MAX} ceiling`);
	const parse = step(WEAR, 'Parse version from tag');
	assert.match(parse.body, /VERSION_CODE=\$\(\(WEAR_VERSION_CODE_OFFSET \+ \$\(git rev-list --count HEAD\)\)\)/);
	assert.match(step(ANDROID, 'Parse version from tag').body, /VERSION_CODE=\$\(git rev-list --count HEAD\)\n/, "the phone's version code moved; recheck the watch's range against it");

	const keystore = step(WEAR, 'Decode release keystore');
	for (const name of ['ANDROID_KEYSTORE_BASE64', 'ANDROID_KEYSTORE_PASSWORD', 'ANDROID_KEY_PASSWORD', 'ANDROID_KEY_ALIAS']) {
		assert.ok(keystore.body.includes(`${name}: \${{ secrets.${name} }}`), `the watch does not sign with ${name}`);
		assert.ok(step(ANDROID, 'Decode release keystore').body.includes(`${name}: \${{ secrets.${name} }}`), `release-android.yml no longer names ${name}`);
	}
	assert.ok(!/WATCH_WEAR_KEY/.test(WEAR), 'the retired Wear upload keystore is still read');
	assert.ok(step(WEAR, 'Verify keystore credentials').i > keystore.i);

	const build = step(WEAR, 'Build AAB (signed)');
	const attach = step(WEAR, 'Attach artifacts to the Release');
	const upload = step(WEAR, 'Upload to the Wear OS internal track');
	assert.ok(build.i < attach.i && attach.i < upload.i);
	assert.match(
		upload.body,
		/node scripts\/play_release\.mjs upload --package com\.threkir\.app --form-factor wear \\\n\s+--version-code "\$VERSION_CODE" \\\n\s+--bundle apps\/watch_wear\/android\/app\/build\/outputs\/bundle\/release\/app-release\.aab/,
	);
	assert.ok(upload.body.includes('PLAY_SERVICE_ACCOUNT_JSON: ${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}'));
	assert.ok(!/\$\{\{ secrets\./.test(shell(upload.body)), 'a secret is interpolated into the shell');
	assert.ok(!/uses: r0adkll\/upload-google-play|com\.threkir\.watchwear|play_release\.mjs promote/.test(WEAR), 'the Wear release uploads elsewhere, or promotes on its own');
	assert.match(WEAR, /environment: production/);
});

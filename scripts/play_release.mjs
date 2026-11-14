#!/usr/bin/env node
// Takes a `mobile_android@<version>` bundle from the Play Internal track to
// production as a staged rollout, and walks that rollout up a fixed ramp, the
// way an iOS release goes to App Store review and then a 7-day phased release
// (decisions § 2040, § 2478). It also puts a `watch_wear@<version>` bundle on
// the Wear OS internal testing track of the same app, the phone's listing
// (decisions § 2529).
//
// Commands:
//
//   notes <release-body.md> <out.txt>
//       At the start of the release job, before the build. Reads the
//       owner-written `## What's New` section out of the GitHub Release body
//       (the same section the iOS release reads) and writes it to <out.txt>.
//       Missing, empty, or over Play's 500 characters fails here; it is never
//       truncated and generated notes are never a fallback.
//
//   uploaded --version-code N
//       Before the Internal upload. Writes `uploaded=true|false` to
//       $GITHUB_OUTPUT, so a re-run, or a promotion of a build Play already
//       holds, skips an upload Play would refuse as a duplicate version code.
//
//   promote --version-code N --notes <file>
//       Puts version code N on the production track, with the notes as its
//       en-US release notes, and commits the edit, which sends it for review.
//       An update starts as a staged rollout at the ramp's first step; the
//       app's first production release goes out `completed`, because Play
//       offers staged rollouts for updates only. Production already carrying
//       N is a no-op; a different release still rolling out fails closed.
//
//   upload --form-factor <prefix> --version-code N --bundle <file.aab>
//       From release-watch-wear.yml. Uploads a form factor's bundle (Wear OS:
//       `wear`) to that form factor's internal testing track of the same app,
//       found by name in the edit's track list, and commits. Play holding the
//       version code already skips the upload; the track already carrying it
//       is a no-op. A form factor's bundle shares the app's version codes, so
//       the caller gives it a range the phone's can never reach.
//
//   advance
//       Daily, from play-rollout.yml. Moves an in-progress production rollout
//       to the next ramp step, or to `completed` past the last. Does nothing
//       while the release is in review or awaiting manual publishing, while
//       other changes are in review, or when the rollout is halted: a halt in
//       Play Console is the brake and is never resumed from here.
//
// Every command takes `--package <name>` (default com.threkir.app).
//
// Reads PLAY_SERVICE_ACCOUNT_JSON, the service-account key file's contents.
// Nothing secret is printed: not the key, not the signed assertion, not the
// access token. Google's error bodies carry a status and a message about the
// request, so those, and only those, are printed.
import { createPrivateKey, sign } from 'node:crypto';
import { appendFileSync, readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { extractWhatsNew } from './asc_submit.mjs';

export const API = 'https://androidpublisher.googleapis.com/androidpublisher/v3';
/** Media uploads go to the same API under `/upload` (edits.bundles.upload). */
export const UPLOAD_API = 'https://androidpublisher.googleapis.com/upload/androidpublisher/v3';
export const TOKEN_URI = 'https://oauth2.googleapis.com/token';
export const SCOPE = 'https://www.googleapis.com/auth/androidpublisher';
export const PACKAGE_NAME = 'com.threkir.app';
export const TRACK = 'production';
export const NOTES_LANGUAGE = 'en-US';

/**
 * A form factor's internal testing track is `<prefix>:<name>`. Google's track
 * reference names the internal track `qa` ("wear:qa"), while the phone's has
 * always been uploaded to as `internal` and a form-factor upload is reported
 * working as `automotive:internal`, so both are looked for, documented name
 * first, in the track list Play itself returns.
 */
export const INTERNAL_TRACK_NAMES = ['qa', 'internal'];

/** Play's limit on a release note, per language, in characters. */
export const NOTES_MAX = 500;

/** Google refuses an assertion whose `exp` is more than an hour after `iat`. */
export const TOKEN_LIFETIME_S = 60 * 60;

/**
 * The staged-rollout ramp, one step per daily `advance`, mirroring the user
 * percentages of Apple's 7-day phased release. The last step is `completed`.
 */
export const RAMP = [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1];

/** The lifecycle state of a release users can get, staged or halted (applications.tracks.releases). */
export const PUBLISHED = 'RELEASE_LIFECYCLE_STATE_PUBLISHED';

const VERSION_CODE_PATTERN = /^[1-9][0-9]*$/;
const PACKAGE_PATTERN = /^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$/;
const FORM_FACTOR_PATTERN = /^[a-z][a-z_]*$/;
const EPSILON = 1e-9;

// --- Release notes ------------------------------------------------------------

/**
 * @param {string | null | undefined} body
 * @returns {string}
 */
export function extractPlayNotes(body) {
	return extractWhatsNew(body, { max: NOTES_MAX, audience: 'Google Play users', limitOwner: "Google Play's" });
}

// --- Credentials --------------------------------------------------------------

/**
 * The service account's email and private key, out of the key file's JSON.
 * Every error names what is wrong with the file and none echoes its content.
 *
 * @param {string | undefined} raw
 * @returns {{ clientEmail: string, key: import('node:crypto').KeyObject }}
 */
export function readServiceAccount(raw) {
	if (!(raw ?? '').trim()) {
		throw new Error('PLAY_SERVICE_ACCOUNT_JSON is unset. It is the Google Play service account key file, as downloaded.');
	}
	let parsed;
	try {
		parsed = JSON.parse(/** @type {string} */ (raw));
	} catch {
		throw new Error('PLAY_SERVICE_ACCOUNT_JSON is not JSON. It should be the service account key file, as downloaded.');
	}
	if (parsed?.type !== 'service_account') {
		throw new Error('PLAY_SERVICE_ACCOUNT_JSON is not a service account key file (its "type" is not "service_account").');
	}
	if (typeof parsed.client_email !== 'string' || !parsed.client_email.includes('@')) {
		throw new Error('PLAY_SERVICE_ACCOUNT_JSON has no client_email.');
	}
	let key;
	try {
		key = createPrivateKey(String(parsed.private_key ?? ''));
	} catch {
		throw new Error('PLAY_SERVICE_ACCOUNT_JSON has no readable private_key.');
	}
	if (key.asymmetricKeyType !== 'rsa') {
		throw new Error('PLAY_SERVICE_ACCOUNT_JSON private_key is not an RSA key, which every service account key is.');
	}
	return { clientEmail: parsed.client_email, key };
}

/** @param {string | Buffer} value */
function base64url(value) {
	return Buffer.from(value).toString('base64url');
}

/**
 * The RS256 JWT a service account exchanges for an access token.
 *
 * @param {{ clientEmail: string, key: import('node:crypto').KeyObject, nowS: number }} input
 */
export function buildAssertion({ clientEmail, key, nowS }) {
	const header = { alg: 'RS256', typ: 'JWT' };
	const claims = { iss: clientEmail, scope: SCOPE, aud: TOKEN_URI, iat: nowS, exp: nowS + TOKEN_LIFETIME_S };
	const signingInput = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(claims))}`;
	return `${signingInput}.${base64url(sign('sha256', Buffer.from(signingInput), key))}`;
}

// --- API client -----------------------------------------------------------------

/**
 * @typedef {(url: string, init: { method: string, headers: Record<string, string>, body?: string | Uint8Array }) =>
 *   Promise<{ ok: boolean, status: number, text: () => Promise<string> }>} Fetcher
 */

/**
 * Google's error message, or the error code of an OAuth error, never the body
 * whole: a body that is not Google's format is described by its length.
 *
 * @param {string} text
 */
export function describeError(text) {
	try {
		const parsed = JSON.parse(text);
		const message = parsed?.error?.message ?? parsed?.error_description;
		const code = typeof parsed?.error === 'string' ? parsed.error : parsed?.error?.status;
		const parts = [code, message].filter((part) => typeof part === 'string' && part);
		if (parts.length) return parts.join(': ');
	} catch {
		// fall through to the length-only description
	}
	return `a ${text.length}-character body that is not Google's error format`;
}

/** An error from the Play API that carries its HTTP status. */
export class PlayError extends Error {
	/** @param {string} message @param {number} status @param {string} detail */
	constructor(message, status, detail) {
		super(message);
		this.status = status;
		this.detail = detail;
	}
}

/**
 * @param {{ fetcher: Fetcher, assertion: () => string, base?: string, uploadBase?: string, tokenUri?: string }} input
 */
export function makeApi({ fetcher, assertion, base = API, uploadBase = UPLOAD_API, tokenUri = TOKEN_URI }) {
	/** @type {string | null} */
	let token = null;

	async function accessToken() {
		if (token) return token;
		const res = await fetcher(tokenUri, {
			method: 'POST',
			headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
			body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: assertion() }).toString(),
		});
		const text = await res.text();
		if (!res.ok) {
			throw new PlayError(
				`Google's token endpoint refused the service account with HTTP ${res.status}: ${describeError(text)}. The key in PLAY_SERVICE_ACCOUNT_JSON is revoked, or not this account's.`,
				res.status,
				describeError(text),
			);
		}
		const parsed = JSON.parse(text);
		if (typeof parsed?.access_token !== 'string') throw new Error("Google's token endpoint answered without an access token.");
		token = parsed.access_token;
		return token;
	}

	/**
	 * @param {string} method
	 * @param {string} path
	 * @param {unknown} [body] JSON, or the raw bytes of a media upload
	 * @param {string} [root]
	 * @returns {Promise<any>}
	 */
	async function call(method, path, body, root = base) {
		const media = body instanceof Uint8Array;
		const res = await fetcher(`${root}${path}`, {
			method,
			headers: {
				Authorization: `Bearer ${await accessToken()}`,
				...(body === undefined ? {} : { 'Content-Type': media ? 'application/octet-stream' : 'application/json' }),
			},
			...(body === undefined ? {} : { body: media ? body : JSON.stringify(body) }),
		});
		const text = await res.text();
		if (!res.ok) {
			const detail = describeError(text);
			const hint =
				res.status === 401 || res.status === 403
					? ' A 401 or 403 is the service account: it needs "Release to production, exclude devices, and use Play App Signing" on this app in Play Console → Users and permissions.'
					: '';
			throw new PlayError(`Google Play answered ${method} ${path.split('?')[0]} with HTTP ${res.status}: ${detail}.${hint}`, res.status, detail);
		}
		return text.trim() === '' ? null : JSON.parse(text);
	}

	return {
		/** @param {string} path */
		get: (path) => call('GET', path),
		/** @param {string} path @param {unknown} [body] */
		post: (path, body) => call('POST', path, body),
		/** @param {string} path @param {unknown} body */
		put: (path, body) => call('PUT', path, body),
		/** @param {string} path */
		delete: (path) => call('DELETE', path),
		/** @param {string} path @param {Uint8Array} bytes */
		upload: (path, bytes) => call('POST', path, bytes, uploadBase),
	};
}

/** @typedef {ReturnType<typeof makeApi>} Api */

/**
 * @typedef {{ name?: string, versionCodes?: string[], status?: string, userFraction?: number,
 *   releaseNotes?: Array<{ language: string, text: string }>, [key: string]: unknown }} Release
 */

// --- Edits ----------------------------------------------------------------------

/**
 * One edit, opened on the first call and deleted unless committed. Play keeps
 * one open edit per user per app, and a new one invalidates the last, so an
 * abandoned edit is harmless; deleting it is tidiness, and a failure to is
 * not a failure of the command.
 *
 * @param {Api} api
 * @param {string} packageName
 */
async function openEdit(api, packageName) {
	const app = `/applications/${packageName}`;
	const edit = await api.post(`${app}/edits`, {});
	if (typeof edit?.id !== 'string' || !edit.id) throw new Error('Google Play opened an edit without an id.');
	const at = `${app}/edits/${edit.id}`;
	let committed = false;
	return {
		at,
		/** @returns {Promise<Release[]>} */
		async releases(track = TRACK) {
			const read = await api.get(`${at}/tracks/${track}`);
			return Array.isArray(read?.releases) ? read.releases : [];
		},
		/** @param {Release[]} releases */
		async putReleases(releases, track = TRACK) {
			await api.put(`${at}/tracks/${track}`, { track, releases });
		},
		/** @returns {Promise<string[]>} */
		async trackNames() {
			const list = await api.get(`${at}/tracks`);
			return (Array.isArray(list?.tracks) ? list.tracks : []).map((/** @type {{ track?: unknown }} */ t) => String(t.track));
		},
		/** @param {Uint8Array} bytes @returns {Promise<string>} the version code Play read out of the bundle */
		async uploadBundle(bytes) {
			const bundle = await api.upload(`${at}/bundles?uploadType=media`, bytes);
			return String(bundle?.versionCode);
		},
		/** @returns {Promise<string[]>} */
		async bundleVersionCodes() {
			const list = await api.get(`${at}/bundles`);
			return (Array.isArray(list?.bundles) ? list.bundles : []).map((/** @type {{ versionCode?: unknown }} */ b) => String(b.versionCode));
		},
		async commit() {
			// ERROR_IF_IN_REVIEW rather than the default, which cancels whatever
			// is in review (a listing change, the previous release) and
			// resubmits it with this edit, restarting that review.
			await api.post(`${at}:commit?changesInReviewBehavior=ERROR_IF_IN_REVIEW`);
			committed = true;
		},
		async discard() {
			if (committed) return;
			try {
				await api.delete(at);
			} catch {
				// see above: an open edit expires or is replaced on its own
			}
		},
	};
}

/** @param {unknown} err */
export function isInReviewRefusal(err) {
	return err instanceof PlayError && err.status === 400 && /changes in review/i.test(err.detail);
}

/** @param {Release} release @param {string} versionCode */
const holds = (release, versionCode) => (release.versionCodes ?? []).map(String).includes(versionCode);

/** @param {Release} release */
const percent = (release) => asPercent(release.userFraction ?? 1);

/** @param {number} fraction */
const asPercent = (fraction) => `${Math.round(fraction * 1000) / 10}%`;

/**
 * The ramp step after `fraction`, or null when the next step is the whole
 * audience. A fraction set by hand between steps moves to the next step above it.
 *
 * @param {number | undefined} fraction
 * @returns {number | null}
 */
export function nextFraction(fraction) {
	const current = fraction ?? 0;
	const next = RAMP.find((step) => step > current + EPSILON);
	return next === undefined || next >= 1 - EPSILON ? null : next;
}

/** @typedef {{ level: 'info' | 'notice', message: string }} Outcome */

// --- Commands -------------------------------------------------------------------

/**
 * @param {{ api: Api, packageName?: string, versionCode: string }} input
 * @returns {Promise<boolean>}
 */
export async function isUploaded({ api, packageName = PACKAGE_NAME, versionCode }) {
	const edit = await openEdit(api, packageName);
	try {
		return (await edit.bundleVersionCodes()).includes(versionCode);
	} finally {
		await edit.discard();
	}
}

/**
 * @param {{ api: Api, packageName?: string, versionCode: string, notes: string, log?: (line: string) => void }} input
 * @returns {Promise<Outcome>}
 */
export async function promote({ api, packageName = PACKAGE_NAME, versionCode, notes, log = () => {} }) {
	if (!VERSION_CODE_PATTERN.test(versionCode)) throw new Error(`"${versionCode}" is not a version code.`);
	const text = extractPlayNotes(`## What's New\n${notes}`);
	const edit = await openEdit(api, packageName);
	try {
		const releases = await edit.releases();
		const mine = releases.find((r) => holds(r, versionCode) && r.status !== 'draft');
		if (mine?.status === 'halted') {
			return {
				level: 'notice',
				message: `Version code ${versionCode} is on production and halted. A halt is only lifted in Play Console; nothing was changed.`,
			};
		}
		if (mine) {
			return { level: 'info', message: `Version code ${versionCode} is already on production (${mine.status}, ${percent(mine)}); nothing to do.` };
		}
		const rolling = releases.find((r) => r.status === 'inProgress');
		if (rolling) {
			throw new Error(
				`Production is still rolling out version code ${(rolling.versionCodes ?? []).join(', ')} at ${percent(rolling)}. Complete or halt it in Play Console, then re-run this job.`,
			);
		}
		if (!(await edit.bundleVersionCodes()).includes(versionCode)) {
			throw new Error(`Google Play holds no bundle with version code ${versionCode}. Upload it (the release job's Internal upload does) before promoting it.`);
		}
		const first = !releases.some((r) => r.status === 'completed' || r.status === 'halted');
		/** @type {Release} */
		const release = first
			? { versionCodes: [versionCode], status: 'completed', releaseNotes: [{ language: NOTES_LANGUAGE, text }] }
			: { versionCodes: [versionCode], status: 'inProgress', userFraction: RAMP[0], releaseNotes: [{ language: NOTES_LANGUAGE, text }] };
		log(`Putting version code ${versionCode} on production as ${first ? 'a full release (the first, which Play cannot stage)' : `a staged rollout at ${percent(release)}`}.`);
		await edit.putReleases([release]);
		try {
			await edit.commit();
		} catch (err) {
			if (isInReviewRefusal(err)) {
				throw new Error(
					'Google Play has other changes in review, and committing now would cancel that review. Wait for it to finish (or cancel it in Play Console → Publishing overview), then re-run this job.',
				);
			}
			throw err;
		}
		return first
			? {
					level: 'notice',
					message: `Version code ${versionCode} is sent for review as the app's first production release. Play cannot stage a first release, so on approval it reaches every user in the chosen countries at once.`,
				}
			: {
					level: 'info',
					message: `Version code ${versionCode} is sent for review as a staged rollout at ${percent(release)}; play-rollout.yml walks it up ${RAMP.map(asPercent).join(', ')} once a day after approval.`,
				};
	} finally {
		await edit.discard();
	}
}

/**
 * @param {{ api: Api, packageName?: string, formFactor: string, versionCode: string, bundle: Uint8Array, log?: (line: string) => void }} input
 * @returns {Promise<Outcome>}
 */
export async function uploadToFormFactor({ api, packageName = PACKAGE_NAME, formFactor, versionCode, bundle, log = () => {} }) {
	if (!VERSION_CODE_PATTERN.test(versionCode)) throw new Error(`"${versionCode}" is not a version code.`);
	if (!FORM_FACTOR_PATTERN.test(formFactor)) throw new Error(`"${formFactor}" is not a form factor track prefix (wear, tv, automotive, ...).`);
	const candidates = INTERNAL_TRACK_NAMES.map((name) => `${formFactor}:${name}`);
	const edit = await openEdit(api, packageName);
	try {
		const names = await edit.trackNames();
		const track = candidates.find((name) => names.includes(name));
		if (!track) {
			throw new Error(
				`${packageName} has no ${formFactor} internal testing track (looked for ${candidates.join(' and ')}; Play lists ${names.join(', ') || 'no tracks'}). Add the form factor in Play Console → Test and release → Advanced settings → Form factors, then re-run this job.`,
			);
		}
		const held = (await edit.bundleVersionCodes()).includes(versionCode);
		if (held && (await edit.releases(track)).some((r) => holds(r, versionCode) && r.status === 'completed')) {
			return { level: 'info', message: `Version code ${versionCode} is already on ${track}; nothing to do.` };
		}
		if (held) {
			log(`Google Play already holds version code ${versionCode}; the upload is skipped.`);
		} else {
			log(`Uploading the ${(bundle.length / 1e6).toFixed(1)} MB bundle for version code ${versionCode}.`);
			const read = await edit.uploadBundle(bundle);
			if (read !== versionCode) {
				throw new Error(`Google Play read version code ${read} out of the bundle, not ${versionCode}. The build and the workflow disagree on the version code; nothing was committed.`);
			}
		}
		log(`Putting version code ${versionCode} on ${track}.`);
		await edit.putReleases([{ versionCodes: [versionCode], status: 'completed' }], track);
		try {
			await edit.commit();
		} catch (err) {
			if (isInReviewRefusal(err)) {
				throw new Error(
					`Google Play has other changes in review for ${packageName} (the phone app's release, or a listing change), and committing now would cancel that review. Wait for it to finish, then re-run this job.`,
				);
			}
			throw err;
		}
		return { level: 'info', message: `Version code ${versionCode} is on ${track} of ${packageName}.` };
	} finally {
		await edit.discard();
	}
}

/**
 * @param {{ api: Api, packageName?: string, log?: (line: string) => void }} input
 * @returns {Promise<Outcome>}
 */
export async function advance({ api, packageName = PACKAGE_NAME, log = () => {} }) {
	const edit = await openEdit(api, packageName);
	try {
		const releases = await edit.releases();
		const rolling = releases.find((r) => r.status === 'inProgress');
		if (!rolling) {
			const halted = releases.find((r) => r.status === 'halted');
			if (halted) {
				return {
					level: 'notice',
					message: `The production rollout of version code ${(halted.versionCodes ?? []).join(', ')} is halted. It stays halted until it is resumed in Play Console; nothing was changed.`,
				};
			}
			return { level: 'info', message: 'Nothing is rolling out on production; nothing to do.' };
		}
		const codes = (rolling.versionCodes ?? []).map(String);
		const summaries = await api.get(`/applications/${packageName}/tracks/${TRACK}/releases`);
		const summary = (Array.isArray(summaries?.releases) ? summaries.releases : []).find((/** @type {{ activeArtifacts?: Array<{ versionCode?: unknown }> }} */ s) =>
			(s.activeArtifacts ?? []).some((a) => codes.includes(String(a.versionCode))),
		);
		const state = summary?.releaseLifecycleState ?? 'unknown';
		if (state !== PUBLISHED) {
			return {
				level: 'notice',
				message: `Version code ${codes.join(', ')} is not published yet (${state}): in review, or approved and waiting to be published. The rollout is advanced only once users can get it.`,
			};
		}
		const next = nextFraction(rolling.userFraction);
		/** @type {Release} */
		const moved = { ...rolling };
		if (next === null) {
			moved.status = 'completed';
			delete moved.userFraction;
		} else {
			moved.userFraction = next;
		}
		// The track is written back as read, with this release moved. A
		// completed rollout replaces the release it was superseding.
		const others = releases.filter((r) => r !== rolling && !(next === null && r.status === 'completed'));
		log(`Moving version code ${codes.join(', ')} from ${percent(rolling)} to ${next === null ? '100% (completed)' : percent(moved)}.`);
		await edit.putReleases([...others, moved]);
		try {
			await edit.commit();
		} catch (err) {
			if (isInReviewRefusal(err)) {
				return {
					level: 'notice',
					message: `Google Play has changes in review, so version code ${codes.join(', ')} stays at ${percent(rolling)} today rather than cancel that review.`,
				};
			}
			throw err;
		}
		return {
			level: 'info',
			message: next === null ? `Version code ${codes.join(', ')} is rolled out to every user.` : `Version code ${codes.join(', ')} is now rolling out to ${percent(moved)}.`,
		};
	} finally {
		await edit.discard();
	}
}

// --- CLI ------------------------------------------------------------------------

/**
 * @param {string[]} args
 * @returns {Record<string, string>}
 */
export function parseFlags(args) {
	/** @type {Record<string, string>} */
	const flags = {};
	for (let i = 0; i < args.length; i += 2) {
		const name = args[i];
		const value = args[i + 1];
		if (!name?.startsWith('--') || value === undefined || value.startsWith('--')) throw new Error(`Expected "--flag value" pairs, got "${args.join(' ')}".`);
		flags[name.slice(2)] = value;
	}
	return flags;
}

/** @param {Record<string, string | undefined>} env */
function apiFromEnv(env) {
	const account = readServiceAccount(env.PLAY_SERVICE_ACCOUNT_JSON);
	return makeApi({
		fetcher: (url, init) => fetch(url, init),
		assertion: () => buildAssertion({ ...account, nowS: Math.floor(Date.now() / 1000) }),
	});
}

/** @param {Record<string, string>} flags */
function packageOf(flags) {
	const name = flags.package ?? PACKAGE_NAME;
	if (!PACKAGE_PATTERN.test(name)) throw new Error(`"${name}" is not an Android package name.`);
	return name;
}

/** @param {Record<string, string>} flags */
function versionCodeOf(flags) {
	const code = (flags['version-code'] ?? '').trim();
	if (!VERSION_CODE_PATTERN.test(code)) throw new Error('--version-code must be a positive integer.');
	return code;
}

const USAGE =
	'Usage: node scripts/play_release.mjs notes <body> <out> | uploaded --version-code N | promote --version-code N --notes <file> | upload --form-factor <prefix> --version-code N --bundle <file> | advance  [--package <name>]';

/** @param {string[]} argv @param {Record<string, string | undefined>} env */
export async function main(argv, env, { apiFor = apiFromEnv, print = (/** @type {string} */ line) => console.log(line) } = {}) {
	const [command, ...args] = argv;
	if (command === 'notes') {
		const [bodyFile, outFile] = args;
		if (!bodyFile || !outFile) throw new Error(USAGE);
		const note = extractPlayNotes(readFileSync(bodyFile, 'utf8'));
		writeFileSync(outFile, note);
		print(`Release notes: ${[...note].length} of ${NOTES_MAX} characters, as the ${NOTES_LANGUAGE} notes on Google Play.`);
		return;
	}
	const flags = parseFlags(args);
	/** @param {Outcome} outcome */
	const report = ({ level, message }) => print(level === 'notice' ? `::notice::${message}` : message);
	if (command === 'uploaded') {
		const versionCode = versionCodeOf(flags);
		const uploaded = await isUploaded({ api: apiFor(env), packageName: packageOf(flags), versionCode });
		print(uploaded ? `Version code ${versionCode} is already on Google Play; the upload is skipped.` : `Version code ${versionCode} is not on Google Play yet.`);
		if (env.GITHUB_OUTPUT) appendFileSync(env.GITHUB_OUTPUT, `uploaded=${uploaded}\n`);
		return;
	}
	if (command === 'promote') {
		if (!flags.notes) throw new Error(USAGE);
		report(await promote({ api: apiFor(env), packageName: packageOf(flags), versionCode: versionCodeOf(flags), notes: readFileSync(flags.notes, 'utf8'), log: print }));
		return;
	}
	if (command === 'upload') {
		if (!flags['form-factor'] || !flags.bundle) throw new Error(USAGE);
		const packageName = packageOf(flags);
		const versionCode = versionCodeOf(flags);
		const bundle = readFileSync(flags.bundle);
		report(await uploadToFormFactor({ api: apiFor(env), packageName, formFactor: flags['form-factor'], versionCode, bundle, log: print }));
		return;
	}
	if (command === 'advance') {
		report(await advance({ api: apiFor(env), packageName: packageOf(flags), log: print }));
		return;
	}
	throw new Error(USAGE);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
	try {
		await main(process.argv.slice(2), process.env);
	} catch (err) {
		console.log(`::error::${err instanceof Error ? err.message : 'The Google Play release failed for a reason it did not name.'}`);
		process.exit(1);
	}
}

#!/usr/bin/env node
// Takes a `mobile_ios@<version>` build from TestFlight to App Store review,
// the five steps the owner used to click through in App Store Connect after
// every iOS release (issue #1072, decisions § 2040).
//
// `release-ios.yml` runs it in three places:
//
//   whats-new <release-body.md> <out.txt>
//       At the start of the job, before the build. Reads the owner-written
//       `## What's New` section out of the GitHub Release body and writes it
//       to <out.txt>. A body with no such section, an empty one, or one over
//       Apple's 4000 characters fails here, in seconds, rather than after a
//       half-hour build. Generated notes are never a fallback: they are a
//       developer changelog, not something to put in front of every user.
//       Until the app's first version is released, nothing submits a note, so
//       a missing section is allowed (one that is present is still checked);
//       when App Store Connect cannot be read to tell, the strict rule holds.
//
//   uploaded
//       Before the TestFlight upload. Writes `uploaded=true|false` to
//       $GITHUB_OUTPUT, so a re-run of a job whose submission failed skips an
//       upload Apple would refuse as a duplicate build number.
//
//   submit
//       After the upload. Waits for the build to finish processing, finds the
//       App Store version for the tag (creating it when no version is in
//       progress), attaches the build, writes What's New into every
//       localization the version has, sets the release to go out on approval
//       as a 7-day phased release, and submits it for review. Each step is a
//       no-op when already true, so re-running is safe; anything it does not
//       recognise fails the job rather than being guessed past. While the app
//       has no released version it ends green with a notice: the first
//       submission is the owner's (issue #1113), and the build is in TestFlight
//       for it.
//
// Reads, for `uploaded` and `submit` (the first missing one is named, never a
// value):
//   APP_STORE_CONNECT_API_KEY_ID       the API key's id (`kid`)
//   APP_STORE_CONNECT_API_ISSUER_ID    its issuer id (`iss`)
//   APP_STORE_CONNECT_API_PRIVATE_KEY  its `.p8` contents, PEM as is
//   ASC_VERSION                        the tag's version, CFBundleShortVersionString
//   ASC_BUILD_NUMBER                   the build number, CFBundleVersion
// and for `submit` also
//   WHATS_NEW_FILE                     the file `whats-new` wrote
// `whats-new` reads the three API key variables when they are set, to learn
// whether the app has a released version; unset, it applies the strict rule.
//
// Nothing secret is printed: not the key, not the JWT. App Store Connect's
// error bodies carry an error code and a description of the request, never a
// credential, so those are printed whole: they are the only diagnosis.
import { createPrivateKey, sign } from 'node:crypto';
import { appendFileSync, readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export const API = 'https://api.appstoreconnect.apple.com';
export const BUNDLE_ID = 'com.threkir.app';
export const AUDIENCE = 'appstoreconnect-v1';

/** Apple refuses a token whose `exp` is more than 20 minutes after `iat`. */
export const MAX_TOKEN_LIFETIME_S = 20 * 60;
export const TOKEN_LIFETIME_S = 15 * 60;

/** The heading the owner writes the release note under, in the GitHub Release body. */
export const WHATS_NEW_HEADING = "What's New";

/** App Store Connect's limit on `whatsNew`, in characters. */
export const WHATS_NEW_MAX = 4000;

/** Processing usually takes 5-15 minutes; past an hour, something is wrong. */
export const PROCESSING_TIMEOUT_MS = 60 * 60 * 1000;
export const PROCESSING_POLL_MS = 60 * 1000;

/** The App Store Connect API key, without which nothing in App Store Connect can be read. */
export const ASC_KEY_ENV = ['APP_STORE_CONNECT_API_KEY_ID', 'APP_STORE_CONNECT_API_ISSUER_ID', 'APP_STORE_CONNECT_API_PRIVATE_KEY'];

export const REQUIRED_ENV = [
	'APP_STORE_CONNECT_API_KEY_ID',
	'APP_STORE_CONNECT_API_ISSUER_ID',
	'APP_STORE_CONNECT_API_PRIVATE_KEY',
	'ASC_VERSION',
	'ASC_BUILD_NUMBER',
];

// A version's state is `appVersionState` on current API versions and
// `appStoreState` on older ones; the two vocabularies differ, so each set
// below carries both spellings.

/** States a version is live or retired in. Never edited, never resubmitted. */
export const RELEASED = new Set([
	'READY_FOR_SALE',
	'READY_FOR_DISTRIBUTION',
	'REPLACED_WITH_NEW_VERSION',
	'REMOVED_FROM_SALE',
	'DEVELOPER_REMOVED_FROM_SALE',
	'PREORDER_READY_FOR_SALE',
]);

/** States a version can still be edited and submitted in. */
export const EDITABLE = new Set([
	'PREPARE_FOR_SUBMISSION',
	'READY_FOR_REVIEW',
	'DEVELOPER_REJECTED',
	'REJECTED',
	'METADATA_REJECTED',
	'INVALID_BINARY',
]);

/** States between "submitted" and "released": nothing here may change it. */
export const SUBMITTED = new Set([
	'WAITING_FOR_REVIEW',
	'IN_REVIEW',
	'PENDING_CONTRACT',
	'WAITING_FOR_EXPORT_COMPLIANCE',
	'ACCEPTED',
	'PENDING_DEVELOPER_RELEASE',
	'PENDING_APPLE_RELEASE',
	'PROCESSING_FOR_APP_STORE',
	'PROCESSING_FOR_DISTRIBUTION',
]);

const KEY_ID_PATTERN = /^[A-Z0-9]{10}$/;
const ISSUER_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const VERSION_PATTERN = /^[0-9]+(\.[0-9]+){0,2}$/;
const BUILD_NUMBER_PATTERN = /^[0-9]+$/;

// --- What's New ---------------------------------------------------------------

/**
 * A line that opens the What's New section: a level-2 heading reading
 * "What's New", any case, with a straight or curly apostrophe (GitHub's
 * editor and macOS both substitute the curly one).
 */
const WHATS_NEW_LINE = /^##[ \t]+what[’']s[ \t]+new[ \t]*#*[ \t]*$/i;

/** A heading that ends the section: level 1 or 2. A `###` inside it is text. */
const SECTION_END = /^#{1,2}[ \t]/;

/**
 * Removes HTML comments until none is left, since one pass over a nested
 * `<!-<!-- -->-` leaves a fresh `<!--` behind. An opener with no closer is
 * refused rather than shipped: everything after it would otherwise reach App
 * Store users as the comment text it was meant to hide.
 *
 * @param {string} text
 */
function stripHtmlComments(text) {
	let out = text;
	for (;;) {
		const next = out.replace(/<!--[\s\S]*?-->/g, '');
		if (next === out) break;
		out = next;
	}
	if (out.includes('<!--')) {
		throw new Error(
			`The "## ${WHATS_NEW_HEADING}" section of the GitHub Release body has a "<!--" with no closing "-->". Close or remove the comment in the Release and re-run the job.`,
		);
	}
	return out;
}

/**
 * The release note the owner wrote under `## What's New` in the GitHub Release
 * body, as plain text. Throws, naming what to fix, when there is none, it is
 * empty once HTML comments are removed (a template's placeholder), there are
 * two such sections, or it is over Apple's limit. Never truncates: a note cut
 * mid-sentence would go to every user. With `required: false` (the app has no
 * released version, so no note will be submitted) a body with no section
 * returns '' instead; one that has a section is checked exactly as always.
 *
 * @param {string | null | undefined} body
 * @param {{ required?: boolean }} [options]
 * @returns {string}
 */
export function extractWhatsNew(body, { required = true } = {}) {
	const lines = (body ?? '').replace(/\r\n?/g, '\n').split('\n');
	const starts = lines.flatMap((line, i) => (WHATS_NEW_LINE.test(line) ? [i] : []));
	if (starts.length === 0 && !required) return '';
	if (starts.length === 0) {
		throw new Error(
			`The GitHub Release body has no "## ${WHATS_NEW_HEADING}" section. Edit the Release, add that heading with the note App Store users should read under it, and re-run the job. Generated notes are never used in its place.`,
		);
	}
	if (starts.length > 1) {
		throw new Error(`The GitHub Release body has ${starts.length} "## ${WHATS_NEW_HEADING}" sections. Keep one, so there is no question which note goes to the App Store.`);
	}
	const rest = lines.slice(starts[0] + 1);
	const end = rest.findIndex((line) => SECTION_END.test(line));
	const text = stripHtmlComments((end < 0 ? rest : rest.slice(0, end)).join('\n'))
		.replace(/[ \t]+$/gm, '')
		.replace(/\n{3,}/g, '\n\n')
		.trim();
	if (text === '') {
		throw new Error(
			`The "## ${WHATS_NEW_HEADING}" section of the GitHub Release body is empty. Write the note App Store users should read under it, and re-run the job.`,
		);
	}
	const length = [...text].length;
	if (length > WHATS_NEW_MAX) {
		throw new Error(
			`The "## ${WHATS_NEW_HEADING}" section is ${length} characters, over App Store Connect's ${WHATS_NEW_MAX}. Shorten it in the GitHub Release and re-run the job; it is never cut short.`,
		);
	}
	return text;
}

// --- Credentials ----------------------------------------------------------------

/**
 * @param {Record<string, string | undefined>} env
 * @param {string[]} [names]
 * @returns {string[]} the names that are unset or blank
 */
export function missingEnv(env, names = REQUIRED_ENV) {
	return names.filter((name) => !(env[name] ?? '').trim());
}

/** @param {string | Buffer} value */
function base64url(value) {
	return Buffer.from(value).toString('base64url');
}

/**
 * A secret pasted through a JSON round trip can arrive with literal `\n`
 * sequences instead of line breaks; a PEM with no real newline is never valid,
 * so that is the only case rewritten.
 *
 * @param {string} pem
 */
export function normalizePem(pem) {
	const trimmed = pem.trim();
	return trimmed.includes('\n') ? trimmed : trimmed.replace(/\\n/g, '\n');
}

/**
 * An App Store Connect API token: an ES256 JWT with the raw 64-byte r||s
 * signature JWS requires, not the DER encoding Node emits by default. Every
 * error names the input at fault and none echoes its value.
 *
 * @param {{ keyId: string, issuerId: string, privateKeyPem: string, nowS: number, lifetimeS?: number }} input
 */
export function buildToken({ keyId, issuerId, privateKeyPem, nowS, lifetimeS = TOKEN_LIFETIME_S }) {
	if (!KEY_ID_PATTERN.test(keyId)) {
		throw new Error('APP_STORE_CONNECT_API_KEY_ID is not a 10-character key id (uppercase letters and digits).');
	}
	if (!ISSUER_ID_PATTERN.test(issuerId)) {
		throw new Error('APP_STORE_CONNECT_API_ISSUER_ID is not a UUID, which every issuer id is.');
	}
	if (!Number.isInteger(lifetimeS) || lifetimeS <= 0 || lifetimeS > MAX_TOKEN_LIFETIME_S) {
		throw new Error(`The token lifetime must be between 1 and ${MAX_TOKEN_LIFETIME_S} seconds, Apple's cap.`);
	}
	let key;
	try {
		key = createPrivateKey(normalizePem(privateKeyPem));
	} catch {
		throw new Error('APP_STORE_CONNECT_API_PRIVATE_KEY is not a readable PEM private key. It should be the .p8 file contents, unmodified.');
	}
	if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') {
		throw new Error('APP_STORE_CONNECT_API_PRIVATE_KEY is not a P-256 EC key, which every App Store Connect .p8 is.');
	}
	const header = { alg: 'ES256', kid: keyId, typ: 'JWT' };
	const claims = { iss: issuerId, iat: nowS, exp: nowS + lifetimeS, aud: AUDIENCE };
	const signingInput = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(claims))}`;
	const signature = sign('sha256', Buffer.from(signingInput), { key, dsaEncoding: 'ieee-p1363' });
	return `${signingInput}.${base64url(signature)}`;
}

// --- API client -------------------------------------------------------------------

/**
 * @typedef {(url: string, init: { method: string, headers: Record<string, string>, body?: string }) =>
 *   Promise<{ ok: boolean, status: number, text: () => Promise<string> }>} Fetcher
 */

/**
 * @typedef {{ type: string, id: string, attributes?: Record<string, any>, relationships?: Record<string, { data?: { type: string, id: string } | null }> }} Resource
 * @typedef {{ data: Resource | Resource[] | null, included?: Resource[] }} Document
 */

/**
 * One line per App Store Connect error object: its status, code, title and
 * detail. These describe the request (an attribute that is locked, a version
 * number already used), never a credential.
 *
 * @param {string} text
 */
export function describeErrors(text) {
	try {
		const errors = /** @type {{ errors?: Array<Record<string, unknown>> }} */ (JSON.parse(text)).errors;
		if (Array.isArray(errors) && errors.length) {
			return errors
				.map((e) => [e.status, e.code, e.title, e.detail].filter((part) => typeof part === 'string' && part).join(' / '))
				.join('; ');
		}
	} catch {
		// fall through to the length-only description
	}
	return `a ${text.length}-character body that is not App Store Connect's error format`;
}

/**
 * @param {{ fetcher: Fetcher, token: () => string, base?: string }} input
 */
export function makeApi({ fetcher, token, base = API }) {
	/**
	 * @param {string} method
	 * @param {string} path
	 * @param {unknown} [body]
	 * @returns {Promise<Document | null>}
	 */
	async function call(method, path, body) {
		const res = await fetcher(`${base}${path}`, {
			method,
			headers: {
				Authorization: `Bearer ${token()}`,
				...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
			},
			...(body === undefined ? {} : { body: JSON.stringify(body) }),
		});
		const text = await res.text();
		if (!res.ok) {
			const hint =
				res.status === 401
					? ' A 401 is the API key: revoked, or its id, issuer id and .p8 do not belong together.'
					: res.status === 403
						? ' A 403 is the key\'s role: submitting for review needs App Manager or Admin.'
						: '';
			throw new Error(`App Store Connect answered ${method} ${path.split('?')[0]} with HTTP ${res.status}: ${describeErrors(text)}.${hint}`);
		}
		return text.trim() === '' ? null : /** @type {Document} */ (JSON.parse(text));
	}
	return {
		/** @param {string} path */
		get: async (path) => /** @type {Document} */ (await call('GET', path)),
		/** @param {string} path @param {unknown} body */
		post: async (path, body) => /** @type {Document} */ (await call('POST', path, body)),
		/** @param {string} path @param {unknown} body */
		patch: (path, body) => call('PATCH', path, body),
	};
}

/** @typedef {ReturnType<typeof makeApi>} Api */

/** @param {Document} doc @returns {Resource[]} */
function many(doc) {
	return Array.isArray(doc.data) ? doc.data : doc.data ? [doc.data] : [];
}

/** @param {Document} doc @returns {Resource} */
function one(doc) {
	if (!doc.data || Array.isArray(doc.data)) throw new Error('App Store Connect returned no single resource where one was expected.');
	return doc.data;
}

/** @param {string} value */
const q = (value) => encodeURIComponent(value);

/**
 * @param {Api} api
 * @param {string} [bundleId]
 */
export async function findApp(api, bundleId = BUNDLE_ID) {
	const apps = many(await api.get(`/v1/apps?filter[bundleId]=${q(bundleId)}`));
	if (apps.length !== 1) {
		throw new Error(`App Store Connect lists ${apps.length} apps with bundle id ${bundleId} for this API key, where there must be exactly one.`);
	}
	return apps[0].id;
}

/**
 * The build the release uploaded, or null when App Store Connect does not list
 * it (yet: a fresh upload takes a few minutes to appear).
 *
 * @param {Api} api
 * @param {{ appId: string, version: string, buildNumber: string }} input
 * @returns {Promise<Resource | null>}
 */
export async function findBuild(api, { appId, version, buildNumber }) {
	const builds = many(
		await api.get(`/v1/builds?filter[app]=${q(appId)}&filter[version]=${q(buildNumber)}&filter[preReleaseVersion.version]=${q(version)}&limit=2`),
	);
	if (builds.length > 1) throw new Error(`App Store Connect lists ${builds.length} builds numbered ${buildNumber} for version ${version}, where there can be one.`);
	return builds[0] ?? null;
}

/**
 * Polls until the build is VALID. A build that is not listed yet keeps the
 * wait going; FAILED or INVALID, or the timeout, throws.
 *
 * @param {Api} api
 * @param {{ appId: string, version: string, buildNumber: string, sleep: (ms: number) => Promise<void>, now: () => number, timeoutMs?: number, pollMs?: number, log?: (line: string) => void }} input
 */
export async function waitForBuild(api, { appId, version, buildNumber, sleep, now, timeoutMs = PROCESSING_TIMEOUT_MS, pollMs = PROCESSING_POLL_MS, log = () => {} }) {
	const deadline = now() + timeoutMs;
	for (;;) {
		const build = await findBuild(api, { appId, version, buildNumber });
		const state = build?.attributes?.processingState;
		if (build && state === 'VALID') return build;
		if (build && (state === 'FAILED' || state === 'INVALID')) {
			throw new Error(`Build ${version} (${buildNumber}) finished processing as ${state}. App Store Connect → TestFlight shows Apple's reason, and Apple emails it.`);
		}
		const last = build ? `processing state ${state ?? 'unknown'}` : 'not listed yet';
		if (now() >= deadline) {
			throw new Error(
				`Build ${version} (${buildNumber}) was still ${last} after ${Math.round(timeoutMs / 60000)} minutes. Nothing was submitted. Re-run the job once TestFlight shows the build; the upload is skipped when the build already exists.`,
			);
		}
		log(`Build ${version} (${buildNumber}): ${last}; checking again in ${Math.round(pollMs / 1000)}s.`);
		await sleep(pollMs);
	}
}

/** @param {Resource} version */
export function versionState(version) {
	const a = version.attributes ?? {};
	return /** @type {string} */ (a.appVersionState ?? a.appStoreState ?? 'UNKNOWN');
}

/**
 * Decides which App Store version the tag goes on, from the app's iOS
 * versions. Never guesses: a version in progress under another number is the
 * owner's to rename or finish, because App Store Connect allows one in
 * progress at a time and this script does not rename or replace one.
 *
 * @param {Resource[]} versions
 * @param {string} versionString
 * @returns {{ action: 'create' } | { action: 'use' | 'submitted', version: Resource }}
 */
export function planVersion(versions, versionString) {
	const unknown = versions.filter((v) => {
		const s = versionState(v);
		return !RELEASED.has(s) && !EDITABLE.has(s) && !SUBMITTED.has(s);
	});
	if (unknown.length) {
		const v = unknown[0];
		throw new Error(`App Store Connect version ${v.attributes?.versionString} is in state ${versionState(v)}, which this script does not know. Nothing was changed; finish it in App Store Connect, or teach scripts/asc_submit.mjs the state.`);
	}
	if (!versions.some((v) => RELEASED.has(versionState(v)))) {
		throw new Error(
			'This app has no released App Store version yet. Apple takes no What\'s New on a first version, and the first submission carries review notes, a demo account and a recording that only the owner can supply, so it is submitted by hand in App Store Connect (issue #1113). Automatic submission starts with the version after it.',
		);
	}
	const exact = versions.find((v) => v.attributes?.versionString === versionString);
	if (exact) {
		const s = versionState(exact);
		if (RELEASED.has(s)) {
			throw new Error(`App Store version ${versionString} is already ${s}. A released version cannot take another build; tag the next version.`);
		}
		return { action: SUBMITTED.has(s) ? 'submitted' : 'use', version: exact };
	}
	const inProgress = versions.filter((v) => !RELEASED.has(versionState(v)));
	if (inProgress.length) {
		const v = inProgress[0];
		throw new Error(
			`App Store Connect already has version ${v.attributes?.versionString} in progress (${versionState(v)}), and this release is ${versionString}. ` +
				`Apple allows one version in progress at a time, and this script matches by version number rather than guess which one you meant. ` +
				(EDITABLE.has(versionState(v))
					? `If that version is this release's, change its number to ${versionString} on its App Store Connect page and re-run the job; otherwise finish or remove it first.`
					: 'It is with App Review or waiting to be released, so let it finish, then re-run the job.'),
		);
	}
	return { action: 'create' };
}

/** @param {Resource[]} versions */
export function hasReleasedVersion(versions) {
	return versions.some((v) => RELEASED.has(versionState(v)));
}

/** @param {Api} api @param {string} appId */
async function listVersions(api, appId) {
	return many(await api.get(`/v1/apps/${q(appId)}/appStoreVersions?filter[platform]=IOS&limit=200`));
}

/**
 * Whether this release's note will be submitted: true once the app has a
 * released version. Fails closed: a read that errors answers true, so the
 * strict What's New check applies.
 *
 * @param {Api} api
 * @param {(line: string) => void} [log]
 */
export async function whatsNewRequired(api, log = () => {}) {
	try {
		return hasReleasedVersion(await listVersions(api, await findApp(api)));
	} catch (err) {
		log(`Could not read App Store Connect to tell whether the app has a released version (${err instanceof Error ? err.message : 'no reason given'}); applying the full What's New check.`);
		return true;
	}
}

/** The message a release ends on while the app has no released version. */
export const FIRST_VERSION_NOTICE =
	"The app has no released App Store version yet, so automatic submission starts after the first one is released. This build is in TestFlight for the manual first submission (issue #1113).";

/** @param {Resource} version @param {string} name */
function related(version, name) {
	return version.relationships?.[name]?.data ?? null;
}

/**
 * @param {Api} api
 * @param {string} versionId
 */
async function readVersion(api, versionId) {
	return one(await api.get(`/v1/appStoreVersions/${q(versionId)}?include=build,appStoreVersionPhasedRelease`));
}

/** Review submission states in which a submission is still open. */
const OPEN_SUBMISSION_STATES = ['READY_FOR_REVIEW', 'WAITING_FOR_REVIEW', 'IN_REVIEW', 'UNRESOLVED_ISSUES'];

/**
 * Submits the version for review through a review submission, reusing a draft
 * one when it exists. A rejection awaiting a reply, or another submission
 * already with App Review, fails closed.
 *
 * @param {Api} api
 * @param {{ appId: string, versionId: string, versionString: string, log: (line: string) => void }} input
 * @returns {Promise<'submitted' | 'already'>}
 */
export async function ensureSubmitted(api, { appId, versionId, versionString, log }) {
	const open = many(
		await api.get(`/v1/reviewSubmissions?filter[app]=${q(appId)}&filter[platform]=IOS&filter[state]=${OPEN_SUBMISSION_STATES.join(',')}`),
	);
	/** @type {Array<{ submission: Resource, state: string, hasVersion: boolean }>} */
	const subs = [];
	for (const submission of open) {
		const items = many(await api.get(`/v1/reviewSubmissions/${q(submission.id)}/items?include=appStoreVersion`));
		subs.push({
			submission,
			state: /** @type {string} */ (submission.attributes?.state),
			hasVersion: items.some((item) => related(item, 'appStoreVersion')?.id === versionId),
		});
	}
	if (subs.some((s) => s.hasVersion && (s.state === 'WAITING_FOR_REVIEW' || s.state === 'IN_REVIEW'))) return 'already';
	const unresolved = subs.find((s) => s.state === 'UNRESOLVED_ISSUES');
	if (unresolved) {
		throw new Error(
			`App Review returned a submission with unresolved issues (review submission ${unresolved.submission.id}). Answer it in App Store Connect's App Review section first; a rejection is not something to resubmit past unread.`,
		);
	}
	const busy = subs.find((s) => s.state === 'WAITING_FOR_REVIEW' || s.state === 'IN_REVIEW');
	if (busy) {
		throw new Error(`Another review submission (${busy.submission.id}) is already ${busy.state} and does not hold version ${versionString}. Let it finish or cancel it in App Store Connect, then re-run the job.`);
	}
	let draft = subs.find((s) => s.state === 'READY_FOR_REVIEW');
	if (!draft) {
		const created = one(
			await api.post('/v1/reviewSubmissions', {
				data: { type: 'reviewSubmissions', attributes: { platform: 'IOS' }, relationships: { app: { data: { type: 'apps', id: appId } } } },
			}),
		);
		draft = { submission: created, state: 'READY_FOR_REVIEW', hasVersion: false };
		log(`Opened review submission ${created.id}.`);
	}
	if (!draft.hasVersion) {
		await api.post('/v1/reviewSubmissionItems', {
			data: {
				type: 'reviewSubmissionItems',
				relationships: {
					reviewSubmission: { data: { type: 'reviewSubmissions', id: draft.submission.id } },
					appStoreVersion: { data: { type: 'appStoreVersions', id: versionId } },
				},
			},
		});
		log(`Added version ${versionString} to review submission ${draft.submission.id}.`);
	}
	await api.patch(`/v1/reviewSubmissions/${q(draft.submission.id)}`, {
		data: { type: 'reviewSubmissions', id: draft.submission.id, attributes: { submitted: true } },
	});
	return 'submitted';
}

/**
 * @typedef {{
 *   api: Api,
 *   version: string,
 *   buildNumber: string,
 *   whatsNew: string,
 *   sleep: (ms: number) => Promise<void>,
 *   now: () => number,
 *   timeoutMs?: number,
 *   pollMs?: number,
 *   log?: (line: string) => void,
 * }} SubmitInput
 */

/**
 * The whole TestFlight-to-review path. Returns a one-line verdict, at
 * `notice` level when it stops because the app has no released version;
 * throws on anything it cannot confirm.
 *
 * @param {SubmitInput} input
 * @returns {Promise<{ level: 'info' | 'notice', message: string }>}
 */
export async function submit({ api, version, buildNumber, whatsNew, sleep, now, timeoutMs, pollMs, log = () => {} }) {
	if (!VERSION_PATTERN.test(version)) throw new Error(`ASC_VERSION ${version} is not one to three dot-separated integers.`);
	if (!BUILD_NUMBER_PATTERN.test(buildNumber)) throw new Error(`ASC_BUILD_NUMBER ${buildNumber} is not a whole number.`);

	const appId = await findApp(api);
	const versions = await listVersions(api, appId);
	if (!hasReleasedVersion(versions)) return { level: 'notice', message: FIRST_VERSION_NOTICE };
	const note = extractWhatsNew(`## ${WHATS_NEW_HEADING}\n${whatsNew}`);
	const plan = planVersion(versions, version);

	const build = await waitForBuild(api, { appId, version, buildNumber, sleep, now, timeoutMs, pollMs, log });
	log(`Build ${version} (${buildNumber}) is processed.`);

	if (plan.action === 'submitted') {
		const current = await readVersion(api, plan.version.id);
		if (related(current, 'build')?.id !== build.id) {
			throw new Error(`App Store version ${version} is already ${versionState(current)} with a different build attached. Nothing was changed; a submitted version's build can only be swapped by hand, after removing it from review.`);
		}
		return { level: 'info', message: `Version ${version} is already ${versionState(current)} with build ${buildNumber}; nothing to do.` };
	}

	let versionId;
	if (plan.action === 'create') {
		const created = one(
			await api.post('/v1/appStoreVersions', {
				data: {
					type: 'appStoreVersions',
					attributes: { platform: 'IOS', versionString: version, releaseType: 'AFTER_APPROVAL' },
					relationships: {
						app: { data: { type: 'apps', id: appId } },
						build: { data: { type: 'builds', id: build.id } },
					},
				},
			}),
		);
		versionId = created.id;
		log(`Created App Store version ${version}.`);
	} else {
		versionId = plan.version.id;
		log(`Using App Store version ${version} (${versionState(plan.version)}).`);
	}

	let current = await readVersion(api, versionId);
	if (related(current, 'build')?.id !== build.id) {
		await api.patch(`/v1/appStoreVersions/${q(versionId)}/relationships/build`, { data: { type: 'builds', id: build.id } });
		log(`Attached build ${buildNumber}.`);
	}
	if (current.attributes?.releaseType !== 'AFTER_APPROVAL') {
		await api.patch(`/v1/appStoreVersions/${q(versionId)}`, {
			data: { type: 'appStoreVersions', id: versionId, attributes: { releaseType: 'AFTER_APPROVAL' } },
		});
		log('Set the release to go out automatically once approved.');
	}
	if (!related(current, 'appStoreVersionPhasedRelease')) {
		await api.post('/v1/appStoreVersionPhasedReleases', {
			data: {
				type: 'appStoreVersionPhasedReleases',
				attributes: { phasedReleaseState: 'INACTIVE' },
				relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: versionId } } },
			},
		});
		log('Turned on the 7-day phased release.');
	}

	const localizations = many(await api.get(`/v1/appStoreVersions/${q(versionId)}/appStoreVersionLocalizations?limit=200`));
	if (localizations.length === 0) {
		throw new Error(`App Store version ${version} has no localizations to write What's New into. Check its product page in App Store Connect.`);
	}
	for (const loc of localizations) {
		if (loc.attributes?.whatsNew === note) continue;
		await api.patch(`/v1/appStoreVersionLocalizations/${q(loc.id)}`, {
			data: { type: 'appStoreVersionLocalizations', id: loc.id, attributes: { whatsNew: note } },
		});
		log(`Wrote What's New for ${loc.attributes?.locale}.`);
	}

	const outcome = await ensureSubmitted(api, { appId, versionId, versionString: version, log });
	current = await readVersion(api, versionId);
	const state = versionState(current);
	if (outcome === 'submitted' && EDITABLE.has(state) && state !== 'READY_FOR_REVIEW') {
		throw new Error(`The review submission was sent, but version ${version} still reads ${state}, so the submission is unconfirmed. Check App Store Connect before re-running.`);
	}
	return {
		level: 'info',
		message:
			outcome === 'already'
				? `Version ${version} was already with App Review (${state}); its build, What's New and release settings are confirmed.`
				: `Version ${version} with build ${buildNumber} is submitted for review (${state}). Once approved it releases automatically as a 7-day phased release.`,
	};
}

// --- CLI -----------------------------------------------------------------------

/**
 * @param {Record<string, string | undefined>} env
 * @param {string[]} names
 */
function requireEnv(env, names) {
	const missing = missingEnv(env, names);
	if (missing.length) {
		throw new Error(`These are unset: ${missing.join(', ')}. The header of scripts/asc_submit.mjs says what each one is; release-ios.yml passes them.`);
	}
}

/** @param {Record<string, string | undefined>} env */
function apiFromEnv(env) {
	const keyId = /** @type {string} */ (env.APP_STORE_CONNECT_API_KEY_ID).trim();
	const issuerId = /** @type {string} */ (env.APP_STORE_CONNECT_API_ISSUER_ID).trim();
	const privateKeyPem = /** @type {string} */ (env.APP_STORE_CONNECT_API_PRIVATE_KEY);
	// Validated once up front, so a malformed key fails before any request.
	buildToken({ keyId, issuerId, privateKeyPem, nowS: Math.floor(Date.now() / 1000) });
	return makeApi({
		fetcher: (url, init) => fetch(url, init),
		token: () => buildToken({ keyId, issuerId, privateKeyPem, nowS: Math.floor(Date.now() / 1000) }),
	});
}

/** @param {string[]} argv @param {Record<string, string | undefined>} env */
async function main(argv, env) {
	const [command, ...args] = argv;
	if (command === 'whats-new') {
		const [bodyFile, outFile] = args;
		if (!bodyFile || !outFile) throw new Error('Usage: node scripts/asc_submit.mjs whats-new <release-body.md> <out.txt>');
		// Without the key there is nothing to ask, so the strict rule holds.
		const required = missingEnv(env, ASC_KEY_ENV).length
			? true
			: await whatsNewRequired(apiFromEnv(env), (line) => console.log(line));
		const note = extractWhatsNew(readFileSync(bodyFile, 'utf8'), { required });
		writeFileSync(outFile, note);
		if (note === '') {
			console.log(`::notice::The Release has no "## ${WHATS_NEW_HEADING}" section, which is allowed until the app's first App Store version is released: nothing will be submitted. Add one to every mobile_ios Release after that.`);
		} else {
			console.log(`What's New: ${[...note].length} of ${WHATS_NEW_MAX} characters, written to every localization the App Store version has.`);
		}
		return;
	}
	if (command === 'uploaded') {
		requireEnv(env, REQUIRED_ENV);
		const api = apiFromEnv(env);
		const version = /** @type {string} */ (env.ASC_VERSION).trim();
		const buildNumber = /** @type {string} */ (env.ASC_BUILD_NUMBER).trim();
		const build = await findBuild(api, { appId: await findApp(api), version, buildNumber });
		console.log(build ? `Build ${version} (${buildNumber}) is already in App Store Connect; the upload is skipped.` : `Build ${version} (${buildNumber}) is not in App Store Connect yet.`);
		if (env.GITHUB_OUTPUT) appendFileSync(env.GITHUB_OUTPUT, `uploaded=${build ? 'true' : 'false'}\n`);
		return;
	}
	if (command === 'submit') {
		requireEnv(env, [...REQUIRED_ENV, 'WHATS_NEW_FILE']);
		const { level, message } = await submit({
			api: apiFromEnv(env),
			version: /** @type {string} */ (env.ASC_VERSION).trim(),
			buildNumber: /** @type {string} */ (env.ASC_BUILD_NUMBER).trim(),
			whatsNew: readFileSync(/** @type {string} */ (env.WHATS_NEW_FILE), 'utf8'),
			sleep: (ms) => new Promise((done) => setTimeout(done, ms)),
			now: () => Date.now(),
			log: (line) => console.log(line),
		});
		console.log(level === 'notice' ? `::notice::${message}` : message);
		return;
	}
	throw new Error('Usage: node scripts/asc_submit.mjs whats-new <body> <out> | uploaded | submit');
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
	try {
		await main(process.argv.slice(2), process.env);
	} catch (err) {
		console.log(`::error::${err instanceof Error ? err.message : 'The App Store submission failed for a reason it did not name.'}`);
		process.exit(1);
	}
}

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { generateKeyPairSync, verify } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
	AUDIENCE,
	BUNDLE_ID,
	MAX_TOKEN_LIFETIME_S,
	WHATS_NEW_MAX,
	buildToken,
	describeErrors,
	EDITABLE,
	FIRST_VERSION_NOTICE,
	extractWhatsNew,
	makeApi,
	missingEnv,
	planVersion,
	RELEASED,
	SUBMITTED,
	submit,
	whatsNewRequired,
} from './asc_submit.mjs';

/**
 * No network and no real credential: the key is generated here, and App Store
 * Connect is an in-memory fake that answers the endpoints the script calls in
 * the response shapes App Store Connect returns (JSON:API documents, `errors`
 * arrays, 204 on a relationship PATCH). Every request is recorded, so a test
 * can assert what was written as well as what came back.
 */

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const WORKFLOW = readFileSync(resolve(root, '.github/workflows/release-ios.yml'), 'utf8');

const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const PEM = /** @type {string} */ (privateKey.export({ type: 'pkcs8', format: 'pem' }));
const KID = 'ABC123DEF4';
const ISSUER = '69a6de7e-1234-47e3-e053-5b8c7c11a4d1';
const NOW = 1_800_000_000;

// --- What's New ---------------------------------------------------------------

test("What's New is the owner's section of the Release body, up to the next heading", () => {
	const body = [
		"## What's New",
		'',
		'- Plans can now chain one after another.',
		'- Race photos on the run page.',
		'',
		'### Fixed',
		'- GPS distance under tree canopy.',
		'',
		"## What's Changed",
		'* feat: something by @someone in #1164',
	].join('\r\n');
	assert.equal(
		extractWhatsNew(body),
		'- Plans can now chain one after another.\n- Race photos on the run page.\n\n### Fixed\n- GPS distance under tree canopy.',
	);
});

test('the heading matches any case and either apostrophe, and only at level 2', () => {
	assert.equal(extractWhatsNew('## what’s new\nHello'), 'Hello');
	assert.equal(extractWhatsNew("## WHAT'S NEW ##\nHello"), 'Hello');
	assert.throws(() => extractWhatsNew("### What's New\nHello"), /no "## What's New" section/);
	assert.throws(() => extractWhatsNew("What's New\nHello"), /no "## What's New" section/);
});

test('a missing, empty or placeholder-only section fails, and generated notes are never used instead', () => {
	for (const body of [null, undefined, '', "## What's Changed\n* feat: x in #1"]) {
		assert.throws(() => extractWhatsNew(body), /no "## What's New" section.*Generated notes are never used/s);
	}
	assert.throws(() => extractWhatsNew("## What's New\n\n## What's Changed\n* feat: x"), /is empty/);
	assert.throws(() => extractWhatsNew("## What's New\n<!-- write the App Store note here -->\n"), /is empty/);
});

test('a comment cannot survive the strip by nesting, and an unclosed one is refused', () => {
	// Reason: a single pass over `<!-<!-- x -->- y -->` removed the inner
	// comment and left a fresh `<!-- y -->` behind (code scanning #285).
	assert.equal(extractWhatsNew("## What's New\nKeep<!-<!-- x -->- hidden -->\nthis"), 'Keep\nthis');
	assert.equal(extractWhatsNew("## What's New\nA <!-- one --> B <!-- two --> C"), 'A  B  C');
	assert.throws(() => extractWhatsNew("## What's New\nVisible\n<!-- never closed\nsecret"), /no closing "-->"/);
	assert.throws(() => extractWhatsNew("## What's New\nVisible <!<!---->-- tail"), /no closing "-->"/);
});

test('two sections are refused rather than one picked', () => {
	assert.throws(() => extractWhatsNew("## What's New\nA\n## What's New\nB"), /2 "## What's New" sections/);
});

test(`a note over ${WHATS_NEW_MAX} characters fails and is never truncated`, () => {
	const exact = 'x'.repeat(WHATS_NEW_MAX);
	assert.equal(extractWhatsNew(`## What's New\n${exact}`), exact);
	assert.throws(() => extractWhatsNew(`## What's New\n${exact}y`), new RegExp(`${WHATS_NEW_MAX + 1} characters.*never cut short`));
	// Characters, not UTF-16 units: an emoji-free note in Japanese counts one per character.
	assert.equal([...extractWhatsNew(`## What's New\n${'走'.repeat(WHATS_NEW_MAX)}`)].length, WHATS_NEW_MAX);
});

test('before the first release a missing section is allowed, and a present one is still checked', () => {
	const lenient = { required: false };
	for (const body of [null, '', "## What's Changed\n* feat: x in #1"]) assert.equal(extractWhatsNew(body, lenient), '');
	assert.equal(extractWhatsNew("## What's New\nHello", lenient), 'Hello');
	assert.throws(() => extractWhatsNew("## What's New\nA\n## What's New\nB", lenient), /2 "## What's New" sections/);
	assert.throws(() => extractWhatsNew(`## What's New\n${'x'.repeat(WHATS_NEW_MAX + 1)}`, lenient), /never cut short/);
	assert.throws(() => extractWhatsNew("## What's New\n<!-- placeholder -->", lenient), /is empty/);
});

test('the whats-new command with no API key in its environment applies the strict rule', () => {
	const dir = mkdtempSync(join(tmpdir(), 'asc-submit-'));
	const body = join(dir, 'body.md');
	const out = join(dir, 'out.txt');
	/** @type {Record<string, string>} */
	const env = { PATH: process.env.PATH ?? '' };
	const cli = () => spawnSync(process.execPath, [resolve(root, 'scripts/asc_submit.mjs'), 'whats-new', body, out], { env, encoding: 'utf8' });
	writeFileSync(body, "## What's Changed\n* feat: x in #1\n");
	const missing = cli();
	assert.equal(missing.status, 1, missing.stdout);
	assert.match(missing.stdout, /^::error::.*no "## What's New" section/m);
	writeFileSync(body, "## What's New\nPlans chain now.\n\n## What's Changed\n* feat: x\n");
	const present = cli();
	assert.equal(present.status, 0, present.stdout);
	assert.equal(readFileSync(out, 'utf8'), 'Plans chain now.');
});

// --- Token ---------------------------------------------------------------------

/** @param {string} jwt */
function decode(jwt) {
	const [h, c, s] = jwt.split('.');
	return {
		header: JSON.parse(Buffer.from(h, 'base64url').toString()),
		claims: JSON.parse(Buffer.from(c, 'base64url').toString()),
		signingInput: `${h}.${c}`,
		signature: Buffer.from(s, 'base64url'),
	};
}

test('the API token is an ES256 JWT with the claims App Store Connect checks, inside its 20-minute cap', () => {
	const { header, claims, signingInput, signature } = decode(buildToken({ keyId: KID, issuerId: ISSUER, privateKeyPem: PEM, nowS: NOW }));
	assert.deepEqual(header, { alg: 'ES256', kid: KID, typ: 'JWT' });
	assert.equal(claims.iss, ISSUER);
	assert.equal(claims.aud, AUDIENCE);
	assert.equal(claims.iat, NOW);
	assert.ok(claims.exp - claims.iat <= MAX_TOKEN_LIFETIME_S);
	assert.equal(signature.length, 64, 'ES256 needs the raw r||s signature, not DER');
	assert.ok(verify('sha256', Buffer.from(signingInput), { key: publicKey, dsaEncoding: 'ieee-p1363' }, signature));
	assert.throws(() => buildToken({ keyId: KID, issuerId: ISSUER, privateKeyPem: PEM, nowS: NOW, lifetimeS: MAX_TOKEN_LIFETIME_S + 1 }), /cap/);
});

test('bad credentials name the variable and never echo a value', () => {
	assert.throws(() => buildToken({ keyId: 'short', issuerId: ISSUER, privateKeyPem: PEM, nowS: NOW }), /APP_STORE_CONNECT_API_KEY_ID/);
	assert.throws(() => buildToken({ keyId: KID, issuerId: 'nope', privateKeyPem: PEM, nowS: NOW }), /APP_STORE_CONNECT_API_ISSUER_ID/);
	const notAKey = 'definitely-not-a-pem-value';
	assert.throws(
		() => buildToken({ keyId: KID, issuerId: ISSUER, privateKeyPem: notAKey, nowS: NOW }),
		(err) => err instanceof Error && /APP_STORE_CONNECT_API_PRIVATE_KEY/.test(err.message) && !err.message.includes(notAKey),
	);
	const rsa = /** @type {string} */ (generateKeyPairSync('rsa', { modulusLength: 2048 }).privateKey.export({ type: 'pkcs8', format: 'pem' }));
	assert.throws(() => buildToken({ keyId: KID, issuerId: ISSUER, privateKeyPem: rsa, nowS: NOW }), /P-256/);
	// A PEM whose newlines arrived as literal `\n` still reads.
	assert.ok(buildToken({ keyId: KID, issuerId: ISSUER, privateKeyPem: PEM.trim().replace(/\n/g, '\\n'), nowS: NOW }));
	assert.deepEqual(missingEnv({ APP_STORE_CONNECT_API_KEY_ID: ' ', ASC_VERSION: '1.0.12' }), [
		'APP_STORE_CONNECT_API_KEY_ID',
		'APP_STORE_CONNECT_API_ISSUER_ID',
		'APP_STORE_CONNECT_API_PRIVATE_KEY',
		'ASC_BUILD_NUMBER',
	]);
});

test("App Store Connect's error bodies are described by code and detail", () => {
	const body = JSON.stringify({
		errors: [{ status: '409', code: 'ENTITY_ERROR.ATTRIBUTE.INVALID', title: 'An attribute value is invalid.', detail: 'The version string has already been used.' }],
	});
	assert.equal(describeErrors(body), '409 / ENTITY_ERROR.ATTRIBUTE.INVALID / An attribute value is invalid. / The version string has already been used.');
	assert.match(describeErrors('<html>gateway</html>'), /20-character body/);
});

// --- Version planning --------------------------------------------------------------

/** @param {string} id @param {string} versionString @param {string} state */
const ver = (id, versionString, state) => ({ type: 'appStoreVersions', id, attributes: { versionString, appVersionState: state } });

test('the tag goes on the version with its number, or a new one when none is in progress', () => {
	const live = ver('v1', '1.0', 'READY_FOR_DISTRIBUTION');
	assert.deepEqual(planVersion([live], '1.0.12'), { action: 'create' });
	const editable = ver('v2', '1.0.12', 'PREPARE_FOR_SUBMISSION');
	assert.deepEqual(planVersion([live, editable], '1.0.12'), { action: 'use', version: editable });
	const rejected = ver('v2', '1.0.12', 'REJECTED');
	assert.deepEqual(planVersion([live, rejected], '1.0.12'), { action: 'use', version: rejected });
	const waiting = ver('v2', '1.0.12', 'WAITING_FOR_REVIEW');
	assert.deepEqual(planVersion([live, waiting], '1.0.12'), { action: 'submitted', version: waiting });
	// The older `appStoreState` vocabulary reads the same.
	const legacy = { type: 'appStoreVersions', id: 'v0', attributes: { versionString: '1.0', appStoreState: 'READY_FOR_SALE' } };
	assert.deepEqual(planVersion([legacy], '1.0.12'), { action: 'create' });
});

test('a version in progress under another number fails closed, naming both numbers', () => {
	const live = ver('v1', '1.0.11', 'READY_FOR_DISTRIBUTION');
	assert.throws(
		() => planVersion([live, ver('v2', '1.1', 'PREPARE_FOR_SUBMISSION')], '1.0.12'),
		/version 1\.1 in progress \(PREPARE_FOR_SUBMISSION\), and this release is 1\.0\.12.*change its number to 1\.0\.12/s,
	);
	assert.throws(() => planVersion([live, ver('v2', '1.1', 'PENDING_DEVELOPER_RELEASE')], '1.0.12'), /let it finish/);
});

test("the app's first version is left to the owner: it takes no What's New", () => {
	// The live record today: version "1.0", rejected under 2.1, with 1.0.x builds selected by hand (#1113).
	assert.throws(() => planVersion([ver('v1', '1.0', 'REJECTED')], '1.0.12'), /no released App Store version yet.*#1113/s);
	assert.throws(() => planVersion([ver('v1', '1.0.12', 'REJECTED')], '1.0.12'), /no released App Store version yet/);
});

test('a released version or an unknown state is refused', () => {
	assert.throws(() => planVersion([ver('v1', '1.0.12', 'READY_FOR_DISTRIBUTION')], '1.0.12'), /already READY_FOR_DISTRIBUTION.*tag the next version/);
	assert.throws(() => planVersion([ver('v1', '1.0', 'READY_FOR_SALE'), ver('v2', '1.1', 'SOMETHING_NEW')], '1.1'), /SOMETHING_NEW, which this script does not know/);
});

// --- End to end against a fake App Store Connect ----------------------------------

/*
 * App Store Connect's contract for every request the script makes, transcribed
 * from Apple's OpenAPI specification 4.5.1 (2026-10-06),
 * https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip
 * The fake refuses anything outside it the way App Store Connect does: an
 * unknown path is a 404, an unknown query parameter, enum value or over-cap
 * `limit` a 400, and a body with an unknown attribute or relationship, a wrong
 * `type`, a missing required member or an enum value Apple does not define a
 * 409. So a test passes only on a request Apple's spec accepts, and a script
 * that drifts from it fails here rather than on the first real release. Only
 * the parameters these endpoints define are listed, minus `fields[...]`, which
 * the script never sends.
 */
const PLATFORM = ['IOS', 'MAC_OS', 'TV_OS', 'VISION_OS'];
/** `appStoreState`, deprecated in the spec but still returned. */
const APP_STORE_STATE = [
	'ACCEPTED', 'DEVELOPER_REMOVED_FROM_SALE', 'DEVELOPER_REJECTED', 'IN_REVIEW', 'INVALID_BINARY', 'METADATA_REJECTED',
	'PENDING_APPLE_RELEASE', 'PENDING_CONTRACT', 'PENDING_DEVELOPER_RELEASE', 'PREPARE_FOR_SUBMISSION', 'PREORDER_READY_FOR_SALE',
	'PROCESSING_FOR_APP_STORE', 'READY_FOR_REVIEW', 'READY_FOR_SALE', 'REJECTED', 'REMOVED_FROM_SALE', 'WAITING_FOR_EXPORT_COMPLIANCE',
	'WAITING_FOR_REVIEW', 'REPLACED_WITH_NEW_VERSION', 'NOT_APPLICABLE',
];
/** `appVersionState`, the current one. */
const APP_VERSION_STATE = [
	'ACCEPTED', 'DEVELOPER_REJECTED', 'IN_REVIEW', 'INVALID_BINARY', 'METADATA_REJECTED', 'PENDING_APPLE_RELEASE',
	'PENDING_DEVELOPER_RELEASE', 'PREPARE_FOR_SUBMISSION', 'PROCESSING_FOR_DISTRIBUTION', 'READY_FOR_DISTRIBUTION', 'READY_FOR_REVIEW',
	'REJECTED', 'REPLACED_WITH_NEW_VERSION', 'WAITING_FOR_EXPORT_COMPLIANCE', 'WAITING_FOR_REVIEW',
];
const REVIEW_SUBMISSION_STATE = ['READY_FOR_REVIEW', 'WAITING_FOR_REVIEW', 'IN_REVIEW', 'UNRESOLVED_ISSUES', 'CANCELING', 'COMPLETING', 'COMPLETE'];
const RELEASE_TYPE = ['MANUAL', 'AFTER_APPROVAL', 'SCHEDULED'];
const VERSION_INCLUDE = [
	'app', 'appStoreVersionLocalizations', 'build', 'appStoreVersionPhasedRelease', 'gameCenterAppVersion', 'routingAppCoverage',
	'appStoreReviewDetail', 'appStoreVersionSubmission', 'appClipDefaultExperience', 'appStoreVersionExperiments',
	'appStoreVersionExperimentsV2', 'alternativeDistributionPackage',
];
/** @type {Record<string, 'string' | 'boolean' | string[]>} */
const VERSION_ATTRIBUTES = {
	versionString: 'string',
	copyright: 'string',
	reviewType: ['APP_STORE', 'NOTARIZATION'],
	releaseType: RELEASE_TYPE,
	earliestReleaseDate: 'string',
};

/**
 * @typedef {{
 *   query?: Record<string, null | number | string[]>,
 *   requiredQuery?: string[],
 *   body?: { type: string, id?: boolean, attributes?: Record<string, 'string' | 'boolean' | string[]>, requiredAttributes?: string[], relationships?: Record<string, string>, requiredRelationships?: string[] },
 *   linkage?: string,
 * }} Contract
 */

/** @type {Record<string, Contract>} */
const CONTRACT = {
	'GET /v1/apps': { query: { 'filter[bundleId]': null, 'filter[name]': null, 'filter[sku]': null, 'filter[id]': null, limit: 200 } },
	'GET /v1/builds': {
		query: {
			'filter[app]': null,
			'filter[version]': null,
			'filter[preReleaseVersion.version]': null,
			'filter[preReleaseVersion.platform]': PLATFORM,
			'filter[processingState]': ['PROCESSING', 'FAILED', 'INVALID', 'VALID'],
			'filter[expired]': null,
			'filter[id]': null,
			limit: 200,
		},
	},
	'GET /v1/apps/{id}/appStoreVersions': {
		query: {
			'filter[platform]': PLATFORM,
			'filter[versionString]': null,
			'filter[appStoreState]': APP_STORE_STATE,
			'filter[appVersionState]': APP_VERSION_STATE,
			'filter[id]': null,
			limit: 200,
			include: VERSION_INCLUDE,
		},
	},
	'GET /v1/appStoreVersions/{id}': { query: { include: VERSION_INCLUDE } },
	'GET /v1/appStoreVersions/{id}/appStoreVersionLocalizations': {
		query: { 'filter[locale]': null, limit: 200, include: ['appStoreVersion', 'appScreenshotSets', 'appPreviewSets', 'searchKeywords', 'placements'] },
	},
	'GET /v1/reviewSubmissions': {
		query: {
			'filter[app]': null,
			'filter[platform]': PLATFORM,
			'filter[state]': REVIEW_SUBMISSION_STATE,
			limit: 200,
			include: ['app', 'items', 'appStoreVersionForReview', 'submittedByActor', 'lastUpdatedByActor'],
		},
		requiredQuery: ['filter[app]'],
	},
	'GET /v1/reviewSubmissions/{id}/items': {
		query: { limit: 200, include: ['appStoreVersion', 'appCustomProductPageVersion', 'appStoreVersionExperiment', 'appStoreVersionExperimentV2', 'appEvent'] },
	},
	'POST /v1/appStoreVersions': {
		body: {
			type: 'appStoreVersions',
			attributes: { platform: PLATFORM, ...VERSION_ATTRIBUTES },
			requiredAttributes: ['platform', 'versionString'],
			relationships: { app: 'apps', build: 'builds', appStoreVersionLocalizations: 'appStoreVersionLocalizations[]' },
			requiredRelationships: ['app'],
		},
	},
	'PATCH /v1/appStoreVersions/{id}': {
		body: {
			type: 'appStoreVersions',
			id: true,
			attributes: { ...VERSION_ATTRIBUTES, downloadable: 'boolean' },
			relationships: { build: 'builds', appClipDefaultExperience: 'appClipDefaultExperiences' },
		},
	},
	'PATCH /v1/appStoreVersions/{id}/relationships/build': { linkage: 'builds' },
	'POST /v1/appStoreVersionPhasedReleases': {
		body: {
			type: 'appStoreVersionPhasedReleases',
			attributes: { phasedReleaseState: ['INACTIVE', 'ACTIVE', 'PAUSED', 'COMPLETE'] },
			relationships: { appStoreVersion: 'appStoreVersions' },
			requiredRelationships: ['appStoreVersion'],
		},
	},
	'PATCH /v1/appStoreVersionLocalizations/{id}': {
		body: {
			type: 'appStoreVersionLocalizations',
			id: true,
			attributes: { description: 'string', keywords: 'string', marketingUrl: 'string', promotionalText: 'string', supportUrl: 'string', whatsNew: 'string' },
		},
	},
	'POST /v1/reviewSubmissions': {
		body: { type: 'reviewSubmissions', attributes: { platform: PLATFORM }, relationships: { app: 'apps' }, requiredRelationships: ['app'] },
	},
	'POST /v1/reviewSubmissionItems': {
		body: {
			type: 'reviewSubmissionItems',
			relationships: { reviewSubmission: 'reviewSubmissions', appStoreVersion: 'appStoreVersions' },
			requiredRelationships: ['reviewSubmission'],
		},
	},
	'PATCH /v1/reviewSubmissions/{id}': {
		body: { type: 'reviewSubmissions', id: true, attributes: { platform: PLATFORM, submitted: 'boolean', canceled: 'boolean' } },
	},
};

/**
 * The status, code and detail App Store Connect would refuse the request
 * with, or null when its spec accepts it.
 *
 * @param {string} method
 * @param {string} url
 * @param {any} body
 * @returns {[number, string, string] | null}
 */
function contractError(method, url, body) {
	const u = new URL(url);
	if (u.origin !== 'https://api.appstoreconnect.apple.com') return [404, 'NOT_FOUND', `${u.origin} is not App Store Connect`];
	/** @type {string | undefined} */
	let pathId;
	const entry = Object.entries(CONTRACT).find(([key]) => {
		const [m, template] = key.split(' ');
		const match = new RegExp(`^${template.replace('{id}', '([^/]+)')}$`).exec(u.pathname);
		if (m !== method || !match) return false;
		pathId = match[1];
		return true;
	});
	if (!entry) return [404, 'NOT_FOUND', `The path provided does not match a defined resource type: ${method} ${u.pathname}`];
	const spec = entry[1];
	for (const [name, value] of u.searchParams) {
		const allowed = (spec.query ?? {})[name];
		if (allowed === undefined) return [400, 'PARAMETER_ERROR.ILLEGAL', `The parameter '${name}' can not be used with this request`];
		if (typeof allowed === 'number') {
			if (!/^[0-9]+$/.test(value) || Number(value) < 1 || Number(value) > allowed) return [400, 'PARAMETER_ERROR.INVALID', `'${value}' is not a valid limit; the maximum is ${allowed}`];
		} else {
			for (const v of value.split(',')) {
				if (v === '' || (allowed && !allowed.includes(v))) return [400, 'PARAMETER_ERROR.INVALID', `'${v}' is not a valid value for '${name}'`];
			}
		}
	}
	for (const name of spec.requiredQuery ?? []) {
		if (!u.searchParams.has(name)) return [400, 'PARAMETER_ERROR.REQUIRED', `The parameter '${name}' is required`];
	}
	if (!spec.body && !spec.linkage) return body === undefined ? null : [400, 'ENTITY_ERROR', 'This request takes no body'];
	if (body === null || typeof body !== 'object' || Object.keys(body).join() !== 'data') return [409, 'ENTITY_ERROR', 'The body must be one JSON:API `data` member'];
	const data = body.data;
	/** @param {any} linkage @param {string} type */
	const badLinkage = (linkage, type) =>
		!linkage || typeof linkage !== 'object' || Object.keys(linkage).sort().join() !== 'id,type' || linkage.type !== type || typeof linkage.id !== 'string' || linkage.id === '';
	if (spec.linkage) return badLinkage(data, spec.linkage) ? [409, 'ENTITY_ERROR.RELATIONSHIP.INVALID', `The linkage must be { type: '${spec.linkage}', id }`] : null;
	const b = /** @type {NonNullable<Contract['body']>} */ (spec.body);
	const extra = Object.keys(data ?? {}).filter((k) => !['type', 'id', 'attributes', 'relationships'].includes(k));
	if (extra.length) return [409, 'ENTITY_ERROR', `'${extra[0]}' is not a member of a resource object`];
	if (data.type !== b.type) return [409, 'ENTITY_ERROR.INCLUDED.INVALID', `The type '${data.type}' is not '${b.type}'`];
	if (b.id ? data.id !== pathId : 'id' in data) return [409, 'ENTITY_ERROR.ID.INVALID', `The id '${data.id}' does not match the path`];
	const attributes = data.attributes ?? {};
	for (const [name, value] of Object.entries(attributes)) {
		const kind = (b.attributes ?? {})[name];
		if (kind === undefined) return [409, 'ENTITY_ERROR.ATTRIBUTE.UNKNOWN', `'${name}' is not an attribute of ${b.type} in this request`];
		const valid = Array.isArray(kind) ? kind.includes(value) : typeof value === kind;
		if (!valid) return [409, 'ENTITY_ERROR.ATTRIBUTE.INVALID', `'${JSON.stringify(value)}' is not a valid value for '${name}'`];
	}
	for (const name of b.requiredAttributes ?? []) {
		if (!(name in attributes)) return [409, 'ENTITY_ERROR.ATTRIBUTE.REQUIRED', `'${name}' is required`];
	}
	const relationships = data.relationships ?? {};
	for (const [name, value] of Object.entries(relationships)) {
		const type = (b.relationships ?? {})[name];
		if (type === undefined) return [409, 'ENTITY_ERROR.RELATIONSHIP.UNKNOWN', `'${name}' is not a relationship of ${b.type} in this request`];
		const toMany = type.endsWith('[]');
		const ok =
			value && Object.keys(value).join() === 'data' && (toMany ? Array.isArray(value.data) && value.data.every((/** @type {any} */ l) => !badLinkage(l, type.slice(0, -2))) : !badLinkage(value.data, type));
		if (!ok) return [409, 'ENTITY_ERROR.RELATIONSHIP.INVALID', `'${name}' must be { data: ${toMany ? '[{ type, id }]' : '{ type, id }'} } of type ${type}`];
	}
	for (const name of b.requiredRelationships ?? []) {
		if (!(name in relationships)) return [409, 'ENTITY_ERROR.RELATIONSHIP.REQUIRED', `'${name}' is required`];
	}
	return null;
}

/**
 * @typedef {{ method: string, path: string, body?: any }} Req
 */

/**
 * An in-memory App Store Connect holding one app with one released version.
 * Every request is checked against CONTRACT first. Like App Store Connect, a
 * filter that is not sent does not filter, and a relationship's `data` is
 * returned only when the request's `include` names it.
 *
 * @param {{ versions?: any[], builds?: any[], localizations?: string[], submissions?: any[], buildStates?: string[] }} [seed]
 */
function fakeAsc(seed = {}) {
	/** @type {Req[]} */
	const requests = [];
	/** @type {Req[]} */
	const refused = [];
	const app = { type: 'apps', id: 'app1', attributes: { bundleId: BUNDLE_ID } };
	/** @type {any[]} */
	const versions = seed.versions ?? [
		{ type: 'appStoreVersions', id: 'v1', attributes: { versionString: '1.0', appVersionState: 'READY_FOR_DISTRIBUTION', releaseType: 'MANUAL' }, build: 'b-old', phased: null },
	];
	/** @type {any[]} */
	const builds = seed.builds ?? [{ id: 'b-old', version: '7', short: '1.0', state: 'VALID' }];
	/** Processing states the uploaded build reports on successive polls; it is unlisted until the first. */
	const pending = [...(seed.buildStates ?? ['VALID'])];
	/** @type {any[]} */
	const localizations = [];
	/** @type {any[]} */
	const submissions = seed.submissions ?? [];
	const locales = seed.localizations ?? ['en-US'];
	let next = 1;
	const id = (/** @type {string} */ p) => `${p}${next++}`;
	/** @param {any} v @param {string[]} include */
	const versionDoc = (v, include) => ({
		type: 'appStoreVersions',
		id: v.id,
		attributes: v.attributes,
		relationships: {
			build: include.includes('build') ? { data: v.build ? { type: 'builds', id: v.build } : null } : { links: {} },
			appStoreVersionPhasedRelease: include.includes('appStoreVersionPhasedRelease')
				? { data: v.phased ? { type: 'appStoreVersionPhasedReleases', id: v.phased } : null }
				: { links: {} },
		},
	});
	const ok = (/** @type {unknown} */ doc, status = 200) => ({ ok: true, status, text: async () => (doc === null ? '' : JSON.stringify(doc)) });
	const fail = (/** @type {number} */ status, /** @type {string} */ detail, code = 'ENTITY_ERROR') => ({
		ok: false,
		status,
		text: async () => JSON.stringify({ errors: [{ status: String(status), code, title: 'Refused', detail }] }),
	});

	/** @type {import('./asc_submit.mjs').Fetcher} */
	const fetcher = async (url, init) => {
		assert.match(init.headers.Authorization, /^Bearer [\w-]+\.[\w-]+\.[\w-]+$/);
		const u = new URL(url);
		const path = u.pathname;
		const f = (/** @type {string} */ k) => u.searchParams.get(`filter[${k}]`);
		const include = (u.searchParams.get('include') ?? '').split(',');
		const body = init.body === undefined ? undefined : JSON.parse(init.body);
		if (body !== undefined) assert.equal(init.headers['Content-Type'], 'application/json');
		const req = { method: init.method, path: `${path}${u.search}`, body };
		const refusal = contractError(init.method, url, body);
		if (refusal) {
			refused.push(req);
			return fail(refusal[0], refusal[2], refusal[1]);
		}
		requests.push(req);
		const route = `${init.method} ${path}`;
		/** @type {any} */
		let m;

		if (route === 'GET /v1/apps') return ok({ data: [app].filter((a) => f('bundleId') === null || f('bundleId') === a.attributes.bundleId) });
		if (route === 'GET /v1/apps/app1/appStoreVersions') {
			return ok({ data: versions.filter((v) => f('platform') === null || f('platform')?.split(',').includes('IOS')).map((v) => versionDoc(v, include)) });
		}
		if (route === 'GET /v1/builds') {
			/** @param {any} b */
			const listed = (b) =>
				(f('app') === null || f('app') === 'app1') &&
				(f('version') === null || b.version === f('version')) &&
				(f('preReleaseVersion.version') === null || b.short === f('preReleaseVersion.version'));
			let match = builds.filter(listed);
			const uploadQuery = f('version') !== null && f('preReleaseVersion.version') !== null && f('preReleaseVersion.version') !== '1.0';
			if (uploadQuery && !builds.some((b) => b.id === 'b-new') && pending.length) {
				// The upload's build: unlisted on the first poll, then each queued state in turn.
				const state = pending.shift();
				if (state !== 'UNLISTED') builds.push({ id: 'b-new', version: f('version'), short: f('preReleaseVersion.version'), state });
				match = builds.filter(listed);
			} else if (uploadQuery && pending.length) {
				const upload = builds.find((b) => b.id === 'b-new');
				if (upload && listed(upload)) upload.state = pending.shift();
			}
			const limit = Number(u.searchParams.get('limit') ?? 50);
			return ok({ data: match.slice(0, limit).map((b) => ({ type: 'builds', id: b.id, attributes: { version: b.version, processingState: b.state } })) });
		}
		if (route === 'POST /v1/appStoreVersions') {
			const a = body.data.attributes;
			if (versions.some((v) => v.attributes.versionString === a.versionString)) return fail(409, 'The version string has already been used.');
			if (versions.some((v) => !['READY_FOR_DISTRIBUTION', 'REPLACED_WITH_NEW_VERSION', 'READY_FOR_SALE'].includes(v.attributes.appVersionState ?? v.attributes.appStoreState))) {
				return fail(409, 'You cannot create a new version of the App in the current state.');
			}
			const v = {
				type: 'appStoreVersions',
				id: id('vn'),
				attributes: { versionString: a.versionString, appVersionState: 'PREPARE_FOR_SUBMISSION', releaseType: a.releaseType ?? 'MANUAL' },
				build: body.data.relationships.build?.data?.id ?? null,
				phased: null,
			};
			versions.push(v);
			for (const locale of locales) localizations.push({ id: id('loc'), version: v.id, locale, whatsNew: null });
			return ok({ data: versionDoc(v, []) }, 201);
		}
		if ((m = /^GET \/v1\/appStoreVersions\/([^/]+)$/.exec(route))) {
			const v = versions.find((x) => x.id === m[1]);
			return v ? ok({ data: versionDoc(v, include) }) : fail(404, 'no such version', 'NOT_FOUND');
		}
		if ((m = /^PATCH \/v1\/appStoreVersions\/([^/]+)\/relationships\/build$/.exec(route))) {
			const v = versions.find((x) => x.id === m[1]);
			if (!['PREPARE_FOR_SUBMISSION', 'REJECTED', 'DEVELOPER_REJECTED'].includes(v.attributes.appVersionState)) return fail(409, 'build is locked');
			if (!builds.some((b) => b.id === body.data.id && b.state === 'VALID')) return fail(409, 'The build is not valid for this version.');
			v.build = body.data.id;
			return ok(null, 204);
		}
		if ((m = /^PATCH \/v1\/appStoreVersions\/([^/]+)$/.exec(route))) {
			const v = versions.find((x) => x.id === m[1]);
			if (!EDITABLE.has(v.attributes.appVersionState)) return fail(409, 'The version is not in an editable state.');
			Object.assign(v.attributes, body.data.attributes);
			return ok({ data: versionDoc(v, []) });
		}
		if (route === 'POST /v1/appStoreVersionPhasedReleases') {
			const v = versions.find((x) => x.id === body.data.relationships.appStoreVersion.data.id);
			if (v.phased) return fail(409, 'A phased release already exists for this version.');
			v.phased = id('pr');
			v.phasedState = body.data.attributes?.phasedReleaseState;
			return ok({ data: { type: 'appStoreVersionPhasedReleases', id: v.phased, attributes: body.data.attributes } }, 201);
		}
		if ((m = /^GET \/v1\/appStoreVersions\/([^/]+)\/appStoreVersionLocalizations$/.exec(route))) {
			for (const v of versions) {
				if (v.id === m[1] && !localizations.some((l) => l.version === v.id)) {
					for (const locale of locales) localizations.push({ id: id('loc'), version: v.id, locale, whatsNew: null });
				}
			}
			return ok({
				data: localizations
					.filter((l) => l.version === m[1])
					.map((l) => ({ type: 'appStoreVersionLocalizations', id: l.id, attributes: { locale: l.locale, whatsNew: l.whatsNew } })),
			});
		}
		if ((m = /^PATCH \/v1\/appStoreVersionLocalizations\/([^/]+)$/.exec(route))) {
			const l = localizations.find((x) => x.id === m[1]);
			const v = versions.find((x) => x.id === l.version);
			if (!EDITABLE.has(v.attributes.appVersionState)) return fail(409, 'whatsNew cannot be edited in the current state.');
			l.whatsNew = body.data.attributes.whatsNew;
			return ok({ data: { type: 'appStoreVersionLocalizations', id: l.id, attributes: { locale: l.locale, whatsNew: l.whatsNew } } });
		}
		if (route === 'GET /v1/reviewSubmissions') {
			const states = f('state')?.split(',') ?? null;
			return ok({
				data: submissions
					.filter((s) => states === null || states.includes(s.state))
					.map((s) => ({ type: 'reviewSubmissions', id: s.id, attributes: { state: s.state, platform: 'IOS' } })),
			});
		}
		if ((m = /^GET \/v1\/reviewSubmissions\/([^/]+)\/items$/.exec(route))) {
			const s = submissions.find((x) => x.id === m[1]);
			return ok({
				data: s.items.map((/** @type {string} */ vid, /** @type {number} */ i) => ({
					type: 'reviewSubmissionItems',
					id: `${s.id}-item${i}`,
					relationships: { appStoreVersion: include.includes('appStoreVersion') ? { data: { type: 'appStoreVersions', id: vid } } : { links: {} } },
				})),
			});
		}
		if (route === 'POST /v1/reviewSubmissions') {
			if (submissions.some((s) => s.state === 'READY_FOR_REVIEW')) return fail(409, 'a draft submission already exists');
			const s = { id: id('rs'), state: 'READY_FOR_REVIEW', items: /** @type {string[]} */ ([]) };
			submissions.push(s);
			return ok({ data: { type: 'reviewSubmissions', id: s.id, attributes: { state: s.state } } }, 201);
		}
		if (route === 'POST /v1/reviewSubmissionItems') {
			const s = submissions.find((x) => x.id === body.data.relationships.reviewSubmission.data.id);
			const vid = body.data.relationships.appStoreVersion?.data?.id;
			if (s.items.includes(vid)) return fail(409, 'The item is already in this submission.');
			s.items.push(vid);
			return ok({ data: { type: 'reviewSubmissionItems', id: id('item') } }, 201);
		}
		if ((m = /^PATCH \/v1\/reviewSubmissions\/([^/]+)$/.exec(route))) {
			const s = submissions.find((x) => x.id === m[1]);
			assert.equal(body.data.attributes.submitted, true);
			if (s.state !== 'READY_FOR_REVIEW') return fail(409, `The submission is ${s.state}.`);
			s.state = 'WAITING_FOR_REVIEW';
			for (const vid of s.items) {
				const v = versions.find((x) => x.id === vid);
				if (v) v.attributes.appVersionState = 'WAITING_FOR_REVIEW';
			}
			return ok({ data: { type: 'reviewSubmissions', id: s.id, attributes: { state: s.state } } });
		}
		throw new Error(`the contract admits ${route} but the fake does not implement it`);
	};

	const writes = () => requests.filter((r) => r.method !== 'GET');
	return { fetcher, requests, refused, writes, versions, builds, localizations, submissions };
}

/**
 * A clock that moves on every sleep, so a processing wait that never ends
 * reaches its deadline and fails the test instead of spinning forever.
 */
function ticking() {
	let clock = 0;
	return {
		sleep: async (/** @type {number} */ ms) => {
			clock += ms;
		},
		now: () => clock,
		timeoutMs: 10 * 60_000,
	};
}

/**
 * @param {ReturnType<typeof fakeAsc>} asc
 * @param {Partial<import('./asc_submit.mjs').SubmitInput>} [over]
 */
function run(asc, over = {}) {
	let clock = 0;
	/** @type {number[]} */
	const sleeps = [];
	return {
		sleeps,
		result: submit({
			api: makeApi({ fetcher: asc.fetcher, token: () => buildToken({ keyId: KID, issuerId: ISSUER, privateKeyPem: PEM, nowS: NOW }) }),
			version: '1.0.12',
			buildNumber: '5120',
			whatsNew: 'Plans chain now.',
			sleep: async (ms) => {
				sleeps.push(ms);
				clock += ms;
			},
			now: () => clock,
			pollMs: 60_000,
			timeoutMs: 10 * 60_000,
			...over,
		}),
	};
}

test('a fresh release: waits for processing, creates the version, attaches, writes every locale, phases, submits', async () => {
	const asc = fakeAsc({ buildStates: ['UNLISTED', 'PROCESSING', 'VALID'], localizations: ['en-US', 'de-DE'] });
	const { result, sleeps } = run(asc);
	const done = await result;
	assert.equal(done.level, 'info');
	assert.match(done.message, /1\.0\.12 with build 5120 is submitted for review \(WAITING_FOR_REVIEW\).*7-day phased release/);
	assert.deepEqual(sleeps, [60_000, 60_000], 'unlisted, then processing, then valid');

	const created = asc.versions.find((v) => v.attributes.versionString === '1.0.12');
	assert.equal(created.attributes.releaseType, 'AFTER_APPROVAL');
	assert.equal(created.build, 'b-new');
	assert.ok(created.phased, 'no phased release was created');
	assert.equal(created.phasedState, 'INACTIVE', 'a phased release starts INACTIVE and goes ACTIVE when the version releases');
	assert.equal(created.attributes.appVersionState, 'WAITING_FOR_REVIEW');
	assert.deepEqual(
		asc.localizations.filter((l) => l.version === created.id).map((l) => [l.locale, l.whatsNew]),
		[['en-US', 'Plans chain now.'], ['de-DE', 'Plans chain now.']],
	);
	assert.deepEqual(
		asc.writes().map((r) => `${r.method} ${r.path}`),
		[
			'POST /v1/appStoreVersions',
			'POST /v1/appStoreVersionPhasedReleases',
			'PATCH /v1/appStoreVersionLocalizations/loc2',
			'PATCH /v1/appStoreVersionLocalizations/loc3',
			'POST /v1/reviewSubmissions',
			'POST /v1/reviewSubmissionItems',
			'PATCH /v1/reviewSubmissions/rs5',
		],
	);
	// Nothing is created before the build is known to be good.
	const firstWrite = asc.requests.findIndex((r) => r.method !== 'GET');
	const lastBuildRead = asc.requests.map((r) => r.path.startsWith('/v1/builds')).lastIndexOf(true);
	assert.ok(lastBuildRead < firstWrite);
});

test('re-running after success writes nothing', async () => {
	const asc = fakeAsc();
	await run(asc).result;
	const before = asc.writes().length;
	assert.match((await run(asc).result).message, /already WAITING_FOR_REVIEW with build 5120; nothing to do/);
	assert.equal(asc.writes().length, before);
});

test('a version the owner made by hand under the tag number is completed, not duplicated', async () => {
	const asc = fakeAsc({
		versions: [
			{ type: 'appStoreVersions', id: 'v1', attributes: { versionString: '1.0', appVersionState: 'READY_FOR_DISTRIBUTION', releaseType: 'MANUAL' }, build: 'b-old', phased: null },
			{ type: 'appStoreVersions', id: 'v2', attributes: { versionString: '1.0.12', appVersionState: 'PREPARE_FOR_SUBMISSION', releaseType: 'MANUAL' }, build: null, phased: null },
		],
	});
	await run(asc).result;
	const paths = asc.writes().map((r) => `${r.method} ${r.path}`);
	assert.ok(!paths.includes('POST /v1/appStoreVersions'), paths.join('\n'));
	assert.ok(paths.includes('PATCH /v1/appStoreVersions/v2/relationships/build'));
	assert.ok(paths.includes('PATCH /v1/appStoreVersions/v2'), 'MANUAL release was not switched to AFTER_APPROVAL');
	assert.equal(asc.versions[1].attributes.releaseType, 'AFTER_APPROVAL');
	assert.ok(asc.versions[1].phased, 'a version made by hand was submitted without a phased release');
	assert.equal(asc.versions[1].attributes.appVersionState, 'WAITING_FOR_REVIEW');
});

test('a draft review submission is reused rather than a second one opened', async () => {
	const asc = fakeAsc({ submissions: [{ id: 'rs-draft', state: 'READY_FOR_REVIEW', items: [] }] });
	await run(asc).result;
	const paths = asc.writes().map((r) => `${r.method} ${r.path}`);
	assert.ok(!paths.includes('POST /v1/reviewSubmissions'), paths.join('\n'));
	assert.ok(paths.includes('PATCH /v1/reviewSubmissions/rs-draft'));
});

test('a build that never finishes processing times out with nothing created', async () => {
	const asc = fakeAsc({ buildStates: Array(50).fill('PROCESSING') });
	await assert.rejects(run(asc).result, /still processing state PROCESSING after 10 minutes\. Nothing was submitted/);
	assert.deepEqual(asc.refused, [], 'the rejection was the fake refusing a malformed request');
	assert.deepEqual(asc.writes(), []);
});

test('a build Apple rejected in processing fails with nothing created', async () => {
	const asc = fakeAsc({ buildStates: ['PROCESSING', 'INVALID'] });
	await assert.rejects(run(asc).result, /finished processing as INVALID/);
	assert.deepEqual(asc.refused, [], 'the rejection was the fake refusing a malformed request');
	assert.deepEqual(asc.writes(), []);
});

test('a rejection awaiting a reply is not resubmitted past', async () => {
	const asc = fakeAsc({ submissions: [{ id: 'rs-old', state: 'UNRESOLVED_ISSUES', items: ['v1'] }] });
	await assert.rejects(run(asc).result, /unresolved issues/);
	assert.deepEqual(asc.refused, [], 'the rejection was the fake refusing a malformed request');
	assert.ok(!asc.writes().some((r) => r.path.startsWith('/v1/reviewSubmissions')), 'a submission was written');
});

test('a submitted version holding a different build fails closed', async () => {
	const asc = fakeAsc({
		versions: [
			{ type: 'appStoreVersions', id: 'v1', attributes: { versionString: '1.0', appVersionState: 'READY_FOR_DISTRIBUTION' }, build: 'b-old', phased: null },
			{ type: 'appStoreVersions', id: 'v2', attributes: { versionString: '1.0.12', appVersionState: 'IN_REVIEW', releaseType: 'AFTER_APPROVAL' }, build: 'b-other', phased: 'pr' },
		],
	});
	await assert.rejects(run(asc).result, /already IN_REVIEW with a different build attached/);
	assert.deepEqual(asc.refused, [], 'the rejection was the fake refusing a malformed request');
	assert.deepEqual(asc.writes(), []);
});

test('an API refusal fails the run with Apple\'s code and detail, and the token never appears', async () => {
	const asc = fakeAsc();
	const real = asc.fetcher;
	/** @type {import('./asc_submit.mjs').Fetcher} */
	const fetcher = async (url, init) =>
		init.method === 'POST' && url.endsWith('/v1/appStoreVersions')
			? { ok: false, status: 409, text: async () => JSON.stringify({ errors: [{ status: '409', code: 'ENTITY_ERROR.ATTRIBUTE.INVALID', detail: 'versionString must be greater than 1.0.12' }] }) }
			: real(url, init);
	/** @type {string[]} */
	const tokens = [];
	const api = makeApi({
		fetcher,
		token: () => {
			const t = buildToken({ keyId: KID, issuerId: ISSUER, privateKeyPem: PEM, nowS: NOW });
			tokens.push(t);
			return t;
		},
	});
	await assert.rejects(
		submit({ api, version: '1.0.12', buildNumber: '5120', whatsNew: 'x', ...ticking() }),
		(err) =>
			err instanceof Error &&
			/POST \/v1\/appStoreVersions with HTTP 409: 409 \/ ENTITY_ERROR\.ATTRIBUTE\.INVALID \/ versionString must be greater/.test(err.message) &&
			!tokens.some((t) => err.message.includes(t)) &&
			!err.message.includes(PEM.split('\n')[1]),
	);
});

test('an empty What\'s New file is refused before anything is written', async () => {
	const asc = fakeAsc();
	await assert.rejects(run(asc, { whatsNew: '  \n' }).result, /is empty/);
	assert.deepEqual(asc.writes(), []);
	assert.ok(!asc.requests.some((r) => r.path.startsWith('/v1/builds')), 'it waited on processing first');
});

/** The live record today: version "1.0", rejected under 2.1, resubmitted by hand (#1113). */
const PRE_RELEASE = [{ type: 'appStoreVersions', id: 'v1', attributes: { versionString: '1.0', appVersionState: 'REJECTED', releaseType: 'MANUAL' }, build: 'b-old', phased: null }];

test('before the first release, submit ends at notice level with nothing written and no wait', async () => {
	for (const whatsNew of ['Plans chain now.', '']) {
		const asc = fakeAsc({ versions: structuredClone(PRE_RELEASE) });
		const { result, sleeps } = run(asc, { whatsNew });
		assert.deepEqual(await result, { level: 'notice', message: FIRST_VERSION_NOTICE });
		assert.match(FIRST_VERSION_NOTICE, /starts after the first one is released.*TestFlight.*#1113/);
		assert.deepEqual(asc.writes(), []);
		assert.deepEqual(sleeps, []);
	}
});

test('the What\'s New check is lenient only when App Store Connect says nothing is released', async () => {
	/** @param {import('./asc_submit.mjs').Fetcher} fetcher */
	const api = (fetcher) => makeApi({ fetcher, token: () => buildToken({ keyId: KID, issuerId: ISSUER, privateKeyPem: PEM, nowS: NOW }) });
	assert.equal(await whatsNewRequired(api(fakeAsc({ versions: structuredClone(PRE_RELEASE) }).fetcher)), false);
	assert.equal(await whatsNewRequired(api(fakeAsc().fetcher)), true);
	/** @type {string[]} */
	const logged = [];
	const down = api(async () => ({ ok: false, status: 503, text: async () => '' }));
	assert.equal(await whatsNewRequired(down, (line) => logged.push(line)), true, 'a failed read must keep the strict rule');
	assert.match(logged.join('\n'), /HTTP 503.*applying the full What's New check/s);
	const thrown = api(async () => {
		throw new Error('network down');
	});
	assert.equal(await whatsNewRequired(thrown), true);
});

test("the fake refuses what Apple's spec refuses, so a drifted request cannot pass", async () => {
	const asc = fakeAsc();
	const api = makeApi({ fetcher: asc.fetcher, token: () => buildToken({ keyId: KID, issuerId: ISSUER, privateKeyPem: PEM, nowS: NOW }) });
	/** @type {Array<[string, () => Promise<unknown>, RegExp]>} */
	const cases = [
		['the retired v1 submission resource', () => api.post('/v1/appStoreVersionSubmissions', { data: { type: 'appStoreVersionSubmissions', relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: 'v1' } } } } }), /HTTP 404/],
		['a misspelled filter', () => api.get('/v1/builds?filter[preReleaseVersion.versionString]=1.0.12'), /HTTP 400.*PARAMETER_ERROR\.ILLEGAL/],
		['a state from the wrong vocabulary', () => api.get('/v1/apps/app1/appStoreVersions?filter[appVersionState]=READY_FOR_SALE'), /HTTP 400.*READY_FOR_SALE/],
		['a limit over the cap', () => api.get('/v1/apps/app1/appStoreVersions?limit=201'), /HTTP 400.*maximum is 200/],
		['a review-submission list without its required app filter', () => api.get('/v1/reviewSubmissions?filter[platform]=IOS'), /HTTP 400.*PARAMETER_ERROR\.REQUIRED/],
		['an include the endpoint does not define', () => api.get('/v1/appStoreVersions/v1?include=localizations'), /HTTP 400/],
		['a release type Apple does not define', () => api.patch('/v1/appStoreVersions/v1', { data: { type: 'appStoreVersions', id: 'v1', attributes: { releaseType: 'ON_APPROVAL' } } }), /HTTP 409.*ATTRIBUTE\.INVALID/],
		['a phased-release state in the wrong case', () => api.post('/v1/appStoreVersionPhasedReleases', { data: { type: 'appStoreVersionPhasedReleases', attributes: { phasedReleaseState: 'inactive' }, relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: 'v1' } } } } }), /HTTP 409/],
		['an attribute the resource does not have', () => api.patch('/v1/appStoreVersionLocalizations/loc1', { data: { type: 'appStoreVersionLocalizations', id: 'loc1', attributes: { releaseNotes: 'x' } } }), /HTTP 409.*ATTRIBUTE\.UNKNOWN/],
		['a body id that is not the path id', () => api.patch('/v1/reviewSubmissions/rs1', { data: { type: 'reviewSubmissions', id: 'rs2', attributes: { submitted: true } } }), /HTTP 409.*ID\.INVALID/],
		['a boolean sent as a string', () => api.patch('/v1/reviewSubmissions/rs1', { data: { type: 'reviewSubmissions', id: 'rs1', attributes: { submitted: 'true' } } }), /HTTP 409/],
		['a version created with no app', () => api.post('/v1/appStoreVersions', { data: { type: 'appStoreVersions', attributes: { platform: 'IOS', versionString: '2.0' } } }), /HTTP 409.*RELATIONSHIP\.REQUIRED/],
		['a build linkage of the wrong type', () => api.patch('/v1/appStoreVersions/v1/relationships/build', { data: { type: 'build', id: 'b-old' } }), /HTTP 409/],
	];
	for (const [what, call, refusal] of cases) await assert.rejects(call(), refusal, what);
	assert.equal(asc.refused.length, cases.length);
	assert.deepEqual(asc.requests, [], 'a refused request reached the fake');
	// A relationship's linkage comes back only when the request includes it.
	const bare = /** @type {any} */ (await api.get('/v1/appStoreVersions/v1')).data;
	assert.ok(!('data' in bare.relationships.build) && !('data' in bare.relationships.appStoreVersionPhasedRelease));
	const full = /** @type {any} */ (await api.get('/v1/appStoreVersions/v1?include=build,appStoreVersionPhasedRelease')).data;
	assert.deepEqual(full.relationships.build.data, { type: 'builds', id: 'b-old' });
	assert.equal(full.relationships.appStoreVersionPhasedRelease.data, null);
});

test("every App Store version state Apple defines is classified once, and nothing else is", () => {
	const sets = /** @type {Array<[string, Set<string>]>} */ ([['RELEASED', RELEASED], ['EDITABLE', EDITABLE], ['SUBMITTED', SUBMITTED]]);
	const vocabulary = new Set([...APP_VERSION_STATE, ...APP_STORE_STATE]);
	for (const [name, set] of sets) {
		for (const state of set) assert.ok(vocabulary.has(state), `${name} holds ${state}, which is in neither of Apple's vocabularies`);
	}
	for (const state of vocabulary) {
		const homes = sets.filter(([, set]) => set.has(state)).map(([name]) => name);
		if (state === 'NOT_APPLICABLE') {
			assert.deepEqual(homes, [], 'NOT_APPLICABLE has no meaning to act on, so it fails closed');
			continue;
		}
		assert.equal(homes.length, 1, `${state} is in ${homes.length ? homes.join(' and ') : 'no set'}`);
	}
	// Live or retired in either vocabulary: never edited, never resubmitted.
	for (const state of ['READY_FOR_DISTRIBUTION', 'READY_FOR_SALE', 'REPLACED_WITH_NEW_VERSION', 'REMOVED_FROM_SALE', 'DEVELOPER_REMOVED_FROM_SALE']) {
		assert.ok(RELEASED.has(state), `${state} is not treated as released`);
	}
	assert.throws(() => planVersion([ver('v1', '1.0', 'READY_FOR_DISTRIBUTION'), ver('v2', '1.1', 'NOT_APPLICABLE')], '1.1'), /NOT_APPLICABLE, which this script does not know/);
});

test('the build attached is the one numbered like the tag, never a sibling or another train', async () => {
	const asc = fakeAsc({
		builds: [
			{ id: 'b-old', version: '7', short: '1.0', state: 'VALID' },
			// An earlier upload of the same version, processed and valid.
			{ id: 'b-5119', version: '5119', short: '1.0.12', state: 'VALID' },
			// The same build number under another version.
			{ id: 'b-5120-train', version: '5120', short: '1.0.11', state: 'VALID' },
		],
		buildStates: ['PROCESSING', 'VALID'],
	});
	await run(asc).result;
	const created = asc.versions.find((v) => v.attributes.versionString === '1.0.12');
	assert.equal(created.build, 'b-new');
	const buildReads = asc.requests.filter((r) => r.path.startsWith('/v1/builds')).map((r) => new URL(r.path, 'https://x').searchParams);
	assert.ok(buildReads.length >= 2);
	for (const p of buildReads) {
		assert.equal(p.get('filter[version]'), '5120');
		assert.equal(p.get('filter[preReleaseVersion.version]'), '1.0.12');
		assert.equal(p.get('filter[app]'), 'app1');
	}
	assert.deepEqual(asc.refused, []);
});

test('two builds answering for one number fail closed rather than one being picked', async () => {
	const asc = fakeAsc({
		builds: [
			{ id: 'b-old', version: '7', short: '1.0', state: 'VALID' },
			{ id: 'b-a', version: '5120', short: '1.0.12', state: 'VALID' },
			{ id: 'b-b', version: '5120', short: '1.0.12', state: 'VALID' },
		],
		buildStates: [],
	});
	await assert.rejects(run(asc).result, /2 builds numbered 5120 for version 1\.0\.12/);
	assert.deepEqual(asc.writes(), []);
});

test('a re-run after a failure part-way resumes without duplicating the version, phased release, note or submission', async () => {
	const asc = fakeAsc({ localizations: ['en-US', 'de-DE'] });
	const real = asc.fetcher;
	let broken = true;
	/** @type {import('./asc_submit.mjs').Fetcher} */
	const flaky = async (url, init) =>
		broken && init.method === 'POST' && url.endsWith('/v1/reviewSubmissionItems')
			? { ok: false, status: 500, text: async () => JSON.stringify({ errors: [{ status: '500', code: 'UNEXPECTED_ERROR', title: 'x', detail: 'try again' }] }) }
			: real(url, init);
	const api = makeApi({ fetcher: flaky, token: () => buildToken({ keyId: KID, issuerId: ISSUER, privateKeyPem: PEM, nowS: NOW }) });
	const input = { api, version: '1.0.12', buildNumber: '5120', whatsNew: 'Plans chain now.', ...ticking() };
	await assert.rejects(submit(input), /POST \/v1\/reviewSubmissionItems with HTTP 500/);
	const firstWrites = asc.writes().length;
	broken = false;
	assert.match((await submit(input)).message, /submitted for review \(WAITING_FOR_REVIEW\)/);
	assert.deepEqual(
		asc.writes().slice(firstWrites).map((r) => `${r.method} ${r.path}`),
		['POST /v1/reviewSubmissionItems', `PATCH /v1/reviewSubmissions/${asc.submissions[0].id}`],
		'the re-run repeated a step that had already landed',
	);
	assert.equal(asc.versions.filter((v) => v.attributes.versionString === '1.0.12').length, 1);
	assert.equal(asc.submissions.length, 1);
	assert.deepEqual(asc.refused, []);
});

test('a re-run after the final submit failed sends the draft that already holds the version, adding nothing to it', async () => {
	const asc = fakeAsc();
	const real = asc.fetcher;
	let broken = true;
	/** @type {import('./asc_submit.mjs').Fetcher} */
	const flaky = async (url, init) =>
		broken && init.method === 'PATCH' && /\/v1\/reviewSubmissions\//.test(url)
			? { ok: false, status: 503, text: async () => '' }
			: real(url, init);
	const api = makeApi({ fetcher: flaky, token: () => buildToken({ keyId: KID, issuerId: ISSUER, privateKeyPem: PEM, nowS: NOW }) });
	const input = { api, version: '1.0.12', buildNumber: '5120', whatsNew: 'Plans chain now.', ...ticking() };
	await assert.rejects(submit(input), /PATCH \/v1\/reviewSubmissions\/rs\d+ with HTTP 503/);
	const firstWrites = asc.writes().length;
	broken = false;
	assert.match((await submit(input)).message, /submitted for review/);
	assert.deepEqual(
		asc.writes().slice(firstWrites).map((r) => `${r.method} ${r.path}`),
		[`PATCH /v1/reviewSubmissions/${asc.submissions[0].id}`],
	);
	assert.equal(asc.submissions[0].items.length, 1);
	assert.deepEqual(asc.refused, []);
});

test('another submission already with App Review fails closed rather than a second one being sent', async () => {
	// An in-app event or purchase under review: no App Store version in progress, but a submission in flight.
	const asc = fakeAsc({ submissions: [{ id: 'rs-event', state: 'WAITING_FOR_REVIEW', items: [] }] });
	await assert.rejects(run(asc).result, /Another review submission \(rs-event\) is already WAITING_FOR_REVIEW and does not hold version 1\.0\.12/);
	assert.ok(!asc.writes().some((r) => r.path.startsWith('/v1/reviewSubmission')), 'a submission was written');
	assert.equal(asc.submissions.length, 1);
	assert.deepEqual(asc.refused, []);
});

// --- Wiring --------------------------------------------------------------------

/** @param {string} name */
const stepIndex = (name) => {
	const i = WORKFLOW.split(/^ {6}- /m).findIndex((s) => s.startsWith(`name: ${name}\n`));
	assert.ok(i >= 0, `release-ios.yml has no step named "${name}"`);
	return i;
};
/** @param {string} name */
const stepBody = (name) => WORKFLOW.split(/^ {6}- /m)[stepIndex(name)];

const NOTE_STEP = "The GitHub Release carries a What's New for the App Store";
const PROBE_STEP = 'Is this build already in App Store Connect';
const SUBMIT_STEP = 'Submit the build for App Store review';

test("release-ios.yml checks What's New before the build and submits after the upload", () => {
	assert.ok(stepIndex(NOTE_STEP) < stepIndex('Build the signed IPA'));
	assert.ok(stepIndex(NOTE_STEP) < stepIndex('Install the distribution certificate'), 'the note check must come before the slow steps');
	assert.ok(stepIndex(PROBE_STEP) < stepIndex('Upload to TestFlight'));
	assert.ok(stepIndex('Upload to TestFlight') < stepIndex(SUBMIT_STEP));
	assert.ok(stepIndex(SUBMIT_STEP) < stepIndex('Remove the signing keychain and the runtime configs'));

	const note = stepBody(NOTE_STEP);
	// Read live, so editing the Release and re-running picks the edit up; the
	// event payload is frozen at publish time.
	assert.match(note, /gh api "repos\/\$GITHUB_REPOSITORY\/releases\/tags\/\$TAG"/);
	assert.match(note, /node scripts\/asc_submit\.mjs whats-new "\$RUNNER_TEMP\/release-body\.md" "\$RUNNER_TEMP\/whats-new\.txt"/);
	assert.ok(!/\bif:/.test(note) && !/continue-on-error/.test(note), 'the note check must not be skippable');
	for (const name of ['APP_STORE_CONNECT_API_KEY_ID', 'APP_STORE_CONNECT_API_ISSUER_ID', 'APP_STORE_CONNECT_API_PRIVATE_KEY']) {
		assert.ok(note.includes(`${name}: \${{ secrets.${name} }}`), `the note check cannot tell a first version without ${name}`);
	}
	assert.ok(!/\$\{\{ secrets\./.test(note.split('run:')[1] ?? ''), 'a secret is interpolated into the shell');

	const probe = stepBody(PROBE_STEP);
	assert.match(probe, /id: uploaded/);
	assert.match(probe, /node scripts\/asc_submit\.mjs uploaded/);
	assert.match(stepBody('Upload to TestFlight'), /if: steps\.uploaded\.outputs\.uploaded != 'true'/);

	const sub = stepBody(SUBMIT_STEP);
	assert.match(sub, /WHATS_NEW_FILE="\$RUNNER_TEMP\/whats-new\.txt" node scripts\/asc_submit\.mjs submit/);
	assert.ok(!/\bif:/.test(sub) && !/continue-on-error/.test(sub), 'the submission must not be skippable');

	for (const body of [probe, sub]) {
		for (const name of ['APP_STORE_CONNECT_API_KEY_ID', 'APP_STORE_CONNECT_API_ISSUER_ID', 'APP_STORE_CONNECT_API_PRIVATE_KEY']) {
			assert.ok(body.includes(`${name}: \${{ secrets.${name} }}`), `${name} is not passed through env`);
		}
		assert.match(body, /ASC_VERSION: \$\{\{ steps\.version\.outputs\.name \}\}/);
		assert.match(body, /ASC_BUILD_NUMBER: \$\{\{ steps\.version\.outputs\.code \}\}/);
		assert.ok(!/\$\{\{ secrets\./.test(body.split('run:')[1] ?? ''), 'a secret is interpolated into the shell');
	}
});

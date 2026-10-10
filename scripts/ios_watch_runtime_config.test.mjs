import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
	DSN_INFO_KEY,
	DSN_SETTING,
	KEY_INFO_KEY,
	KEY_SETTING,
	RELEASE_INFO_KEY,
	RELEASE_SETTING,
	URL_INFO_KEY,
	URL_SETTING,
	expandEscapes,
	main,
	normalizeDsn,
	normalizeKey,
	normalizeRelease,
	normalizeUrl,
	renderXcconfig,
	verifyInfo,
} from './ios_watch_runtime_config.mjs';
import { nativeTarget, pbxObject } from './check_watch_ios_source.mjs';

/**
 * The script runs only at release time on a Mac, so this is what holds it —
 * and the wiring around it — on every PR. The wiring cases read the committed
 * files rather than fixtures: the defect this exists for was a gap BETWEEN
 * files (a workflow that wrote the values somewhere the watch never looks),
 * and only the real files can show that gap closed (decisions § 1810).
 */

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const read = (/** @type {string} */ p) => readFileSync(resolve(root, p), 'utf8');

const WORKFLOW = read('.github/workflows/release-ios.yml');
const WATCH_XCCONFIG_PATH = 'apps/mobile_ios/ios/Flutter/WatchApp.xcconfig';
const WATCH_XCCONFIG = read(WATCH_XCCONFIG_PATH);
const PHONE_PBXPROJ = read('apps/mobile_ios/ios/Runner.xcodeproj/project.pbxproj');
const WATCH_PLIST = read('apps/watch_ios/WatchApp/Info.plist');

const jwt = (/** @type {object} */ payload) =>
	[{ alg: 'HS256', typ: 'JWT' }, payload].map((o) => Buffer.from(JSON.stringify(o)).toString('base64url')).join('.') +
	'.c2lnbmF0dXJl';
const ANON_JWT = jwt({ iss: 'supabase', role: 'anon' });
const PUBLISHABLE = 'sb_publishable_AbC123-xyz_789';
const ORIGIN = 'https://abcdefghijkl.supabase.co';
const DSN_KEY = '0123456789abcdef0123456789abcdef';
const DSN = `https://${DSN_KEY}@o4501234.ingest.us.sentry.io/4507654321`;
const RELEASE = 'mobile_ios@1.2.3';
/** A complete release environment, with `over` replacing any of it. @param {Record<string, string | undefined>} [over] */
const env = (over = {}) => ({
	[URL_SETTING]: ORIGIN,
	[KEY_SETTING]: PUBLISHABLE,
	[DSN_SETTING]: DSN,
	[RELEASE_SETTING]: RELEASE,
	...over,
});

test('an https origin is accepted and a pasted trailing slash dropped', () => {
	assert.equal(normalizeUrl(ORIGIN), ORIGIN);
	assert.equal(normalizeUrl(`${ORIGIN}/`), ORIGIN);
	assert.equal(normalizeUrl(' https://127.0.0.1:24321 '), 'https://127.0.0.1:24321');
});

test('anything but an https origin is refused, naming the setting and not the value', () => {
	for (const bad of [undefined, '', '  ', 'http://abc.supabase.co', 'https://abc.supabase.co/rest/v1', 'abc.supabase.co', 'https://a b']) {
		assert.throws(
			() => normalizeUrl(bad),
			(e) => e instanceof Error && e.message.includes(URL_SETTING) && (bad === undefined || bad.trim() === '' || !e.message.includes(bad)),
			String(bad),
		);
	}
});

test('an anon JWT and an sb_publishable_ key are accepted', () => {
	assert.equal(normalizeKey(ANON_JWT), ANON_JWT);
	assert.equal(normalizeKey(` ${PUBLISHABLE}\n`), PUBLISHABLE);
});

test('a key that bypasses RLS is refused before it can ship in a binary', () => {
	for (const bad of [jwt({ role: 'service_role' }), jwt({}), 'sb_secret_abc123', 'a.b.c', 'plainstring', 'sb_publishable_a/b', 'sb_publishable_$(X)', '']) {
		assert.throws(() => normalizeKey(bad), (e) => e instanceof Error && e.message.includes(KEY_SETTING), bad);
	}
});

test('an unset or blank Sentry DSN is accepted as "Sentry off", not refused', () => {
	for (const off of [undefined, '', '  \n']) assert.equal(normalizeDsn(off), '', String(off));
});

test('a Sentry DSN is accepted in its SaaS and self-hosted forms', () => {
	assert.equal(normalizeDsn(` ${DSN}\n`), DSN);
	const selfHosted = `https://${DSN_KEY}@sentry.example.org:9000/sentry/42`;
	assert.equal(normalizeDsn(selfHosted), selfHosted);
});

test('anything else in the DSN secret is refused, naming the setting and not the value', () => {
	for (const bad of [
		`http://${DSN_KEY}@o1.ingest.sentry.io/1`,
		`https://${DSN_KEY}:deadbeefdeadbeefdeadbeefdeadbeef@o1.ingest.sentry.io/1`,
		'https://o1.ingest.sentry.io/1',
		`https://${DSN_KEY}@o1.ingest.sentry.io`,
		`https://${DSN_KEY}@o1.ingest.sentry.io/`,
		`https://${DSN_KEY}@o1.ingest.sentry.io/1/`,
		`https://${DSN_KEY}@o1.ingest.sentry.io/project`,
		`https://${DSN_KEY.toUpperCase()}@o1.ingest.sentry.io/1`,
		'https://abc@o1.ingest.sentry.io/1',
		`https://${DSN_KEY}@o1.ingest.sentry.io/1?x=1`,
		`https://${DSN_KEY}@o1 ingest.sentry.io/1`,
		`https://${DSN_KEY}@$(EVIL)/1`,
		ORIGIN,
		PUBLISHABLE,
	]) {
		assert.throws(
			() => normalizeDsn(bad),
			(e) => e instanceof Error && e.message.includes(DSN_SETTING) && !e.message.includes(DSN_KEY) && !e.message.includes('abcdefghijkl'),
			bad,
		);
	}
});

test('the legacy key:secret DSN is refused for carrying a credential', () => {
	assert.throws(() => normalizeDsn(`https://${DSN_KEY}:deadbeefdeadbeefdeadbeefdeadbeef@o1.ingest.sentry.io/1`), /legacy secret key/);
});

test('the release is a mobile_ios@ tag and nothing else', () => {
	for (const ok of ['mobile_ios@1', 'mobile_ios@1.2', RELEASE, ' mobile_ios@10.20.30 ']) assert.equal(normalizeRelease(ok), ok.trim());
	for (const bad of [undefined, '', '1.2.3', 'watch_ios@1.2.3', 'mobile_android@1.2.3', 'mobile_ios@1.2.3.4', 'mobile_ios@v1.2.3', 'mobile_ios@1.2.3-rc1', 'dev']) {
		assert.throws(() => normalizeRelease(bad), (e) => e instanceof Error && e.message.includes(RELEASE_SETTING), String(bad));
	}
});

test('the rendered xcconfig survives Xcode reading it: no // in a value, and the escape expands back', () => {
	/** @param {string} out */
	const parse = (out) =>
		Object.fromEntries(
			out
				.split('\n')
				.filter((l) => l !== '' && !l.startsWith('//'))
				.map((l) => {
					assert.ok(!l.includes('//'), `an xcconfig would read the rest of this line as a comment: ${l}`);
					const [k, ...v] = l.split('=');
					return [k.trim(), expandEscapes(v.join('=').trim())];
				}),
		);
	assert.deepEqual(parse(renderXcconfig({ url: ORIGIN, key: ANON_JWT, dsn: DSN, release: RELEASE })), {
		[URL_SETTING]: ORIGIN,
		[KEY_SETTING]: ANON_JWT,
		[DSN_SETTING]: DSN,
		[RELEASE_SETTING]: RELEASE,
	});
	// An unset DSN is still DEFINED, as empty, so nothing else can supply one.
	const off = renderXcconfig({ url: ORIGIN, key: ANON_JWT, dsn: '', release: RELEASE });
	assert.match(off, new RegExp(`^${DSN_SETTING} =$`, 'm'));
	assert.equal(parse(off)[DSN_SETTING], '');
});

test('the shipped plist passes only when every key came through equal to the release values', () => {
	const expected = { url: ORIGIN, key: PUBLISHABLE, dsn: DSN, release: RELEASE };
	const good = { [URL_INFO_KEY]: ORIGIN, [KEY_INFO_KEY]: PUBLISHABLE, [DSN_INFO_KEY]: DSN, [RELEASE_INFO_KEY]: RELEASE };
	// Pinned to the exact text rather than scanned for the values: a line that
	// equals its expected wording carries nothing but the lengths (and the
	// public tag), which proves more than a substring search for each secret could.
	assert.deepEqual(verifyInfo(good, expected), [
		`${URL_INFO_KEY}: https origin present, length ${ORIGIN.length}, equal to the release secret`,
		`${KEY_INFO_KEY}: present, length ${PUBLISHABLE.length}, equal to the release secret`,
		`${DSN_INFO_KEY}: present, length ${DSN.length}, equal to the release secret`,
		`${RELEASE_INFO_KEY}: ${RELEASE}`,
	]);

	for (const [over, needle] of /** @type {const} */ ([
		[{ [URL_INFO_KEY]: undefined, [KEY_INFO_KEY]: undefined }, 'is empty'],
		[{ [URL_INFO_KEY]: '', [KEY_INFO_KEY]: '' }, 'is empty'],
		[{ [URL_INFO_KEY]: '$(SUPABASE_URL)', [KEY_INFO_KEY]: '$(SUPABASE_ANON_KEY)' }, 'unexpanded'],
		[{ [URL_INFO_KEY]: 'https:' }, 'differs'],
		[{ [KEY_INFO_KEY]: 'sb_publishable_other' }, 'differs'],
		[{ [DSN_INFO_KEY]: undefined }, `${DSN_INFO_KEY} is empty`],
		[{ [DSN_INFO_KEY]: '' }, `${DSN_INFO_KEY} is empty`],
		[{ [DSN_INFO_KEY]: '$(SENTRY_DSN)' }, 'unexpanded'],
		[{ [DSN_INFO_KEY]: 'https:' }, 'differs'],
		[{ [RELEASE_INFO_KEY]: undefined }, `${RELEASE_INFO_KEY} is empty`],
		[{ [RELEASE_INFO_KEY]: '$(APP_RELEASE)' }, 'unexpanded'],
		[{ [RELEASE_INFO_KEY]: 'mobile_ios@1.2.2' }, 'differs'],
	])) {
		const info = { ...good, ...over };
		assert.throws(
			() => verifyInfo(info, expected),
			(e) =>
				e instanceof Error &&
				e.message.includes(needle) &&
				!e.message.includes(PUBLISHABLE) &&
				!e.message.includes('abcdefghijkl') &&
				!e.message.includes(DSN_KEY),
			JSON.stringify(info),
		);
	}
});

test('a release with no DSN passes only while the shipped watch carries none', () => {
	const expected = { url: ORIGIN, key: PUBLISHABLE, dsn: '', release: RELEASE };
	const base = { [URL_INFO_KEY]: ORIGIN, [KEY_INFO_KEY]: PUBLISHABLE, [RELEASE_INFO_KEY]: RELEASE };
	for (const info of [{ ...base, [DSN_INFO_KEY]: '' }, base]) {
		assert.equal(verifyInfo(info, expected)[2], `${DSN_INFO_KEY}: empty, as the release set none, so the watch starts no Sentry`);
	}
	assert.throws(
		() => verifyInfo({ ...base, [DSN_INFO_KEY]: DSN }, expected),
		(e) => e instanceof Error && e.message.includes('although the release set no') && !e.message.includes(DSN_KEY),
	);
});

test('the command line prints an ::error:: and exits 1 on a bad secret, and never prints a value', (t) => {
	/** @type {string[]} */ const printed = [];
	t.mock.method(console, 'log', (/** @type {string} */ s) => printed.push(s));
	assert.equal(main(['write', '/dev/null'], env({ [KEY_SETTING]: jwt({ role: 'service_role' }) })), 1);
	assert.match(printed.join('\n'), /^::error::/m);
	assert.equal(main(['write', '/dev/null'], env({ [DSN_SETTING]: `http://${DSN_KEY}@o1.ingest.sentry.io/1` })), 1);
	assert.equal(main(['write', '/dev/null'], env({ [RELEASE_SETTING]: undefined })), 1);
	assert.equal(main(['write', '/dev/null'], env()), 0);
	assert.equal(main(['write', '/dev/null'], env({ [DSN_SETTING]: undefined })), 0, 'an unset DSN must not fail the release');
	assert.equal(main(['write', '/dev/null'], env({ [DSN_SETTING]: '' })), 0, 'an empty DSN secret must not fail the release');
	assert.equal(main(['frobnicate', 'x'], env()), 1);
	const all = printed.join('\n');
	assert.ok(!all.includes('abcdefghijkl') && !all.includes(PUBLISHABLE) && !all.includes(DSN_KEY), all);
});

// --- Wiring: the values have to land where the watch actually reads them.

/** The `- name:` lines of the release job, in order. */
const stepNames = [...WORKFLOW.matchAll(/^ {6}- name: (.+)$/gm)].map((m) => m[1].trim());
/** @param {string} name */
const stepBody = (name) => {
	const start = WORKFLOW.indexOf(`      - name: ${name}\n`);
	assert.ok(start >= 0, `release-ios.yml has no step named "${name}"`);
	const next = WORKFLOW.slice(start + 1).search(/^ {6}- (name|uses):/m);
	return next < 0 ? WORKFLOW.slice(start) : WORKFLOW.slice(start, start + 1 + next);
};
/** Index of a step by name, or of an unnamed `uses:` step by its action. @param {string} needle */
const stepIndex = (needle) => {
	const steps = WORKFLOW.split(/^ {6}- /m);
	const i = steps.findIndex((s) => s.startsWith(`name: ${needle}\n`) || s.startsWith(`uses: ${needle}`) || s.includes(`\n        uses: ${needle}`));
	assert.ok(i >= 0, `release-ios.yml has no step for ${needle}`);
	return i;
};

const WRITE_STEP = "Write the watch app's runtime config";
const VERIFY_STEP = 'The shipped watch app carries its runtime config';

test('the watch target builds against the xcconfig that includes the generated file', () => {
	const include = /^#include\? "([^"]+)"$/m.exec(WATCH_XCCONFIG);
	assert.ok(include, `${WATCH_XCCONFIG_PATH} no longer includes the generated Supabase config`);
	const included = join(dirname(WATCH_XCCONFIG_PATH), include[1]);

	const target = nativeTarget(PHONE_PBXPROJ, 'WatchApp');
	assert.ok(target, 'Runner.xcodeproj has no WatchApp target');
	const listId = /buildConfigurationList = ([0-9A-Fa-f]{24})/.exec(target)?.[1];
	assert.ok(listId);
	const list = pbxObject(PHONE_PBXPROJ, listId) ?? '';
	const configs = [...list.matchAll(/\t+([0-9A-Fa-f]{24}) \/\* ([^*]+?) \*\/,/g)].map((m) => ({
		name: m[2].trim(),
		body: pbxObject(PHONE_PBXPROJ, m[1]) ?? '',
	}));
	assert.ok(configs.some((c) => c.name === 'Release'), configs.map((c) => c.name).join(', '));
	for (const { name, body } of configs) {
		assert.match(body, /baseConfigurationReference = [0-9A-F]{24} \/\* WatchApp\.xcconfig \*\//, `WatchApp ${name}`);
		assert.ok(
			!/\b(SUPABASE_(URL|ORIGIN|ANON_KEY)|SENTRY_DSN|APP_RELEASE) =/.test(body),
			`WatchApp ${name} sets a release-written value in the committed project`,
		);
	}

	const write = stepBody(WRITE_STEP);
	assert.ok(write.includes(`node scripts/ios_watch_runtime_config.mjs write ${included}`), write);

	assert.ok(
		read('apps/mobile_ios/ios/.gitignore').split('\n').includes(`Flutter/${include[1]}`),
		`${included} must be gitignored: it is generated from secrets and this repo is public`,
	);
});

test('the watch Info.plist expands exactly the four settings the script writes', () => {
	for (const [infoKey, setting] of [
		[URL_INFO_KEY, URL_SETTING],
		[KEY_INFO_KEY, KEY_SETTING],
		[DSN_INFO_KEY, DSN_SETTING],
		[RELEASE_INFO_KEY, RELEASE_SETTING],
	]) {
		assert.match(WATCH_PLIST, new RegExp(`<key>${infoKey}</key>\\s*<string>\\$\\(${setting}\\)</string>`));
	}
});

test('RunApp.swift reads the two Sentry keys the plist carries and starts Sentry only behind a non-empty DSN', () => {
	const runApp = read('apps/watch_ios/WatchApp/RunApp.swift');
	for (const infoKey of [DSN_INFO_KEY, RELEASE_INFO_KEY]) {
		assert.ok(runApp.includes(`forInfoDictionaryKey: "${infoKey}"`), `RunApp.swift no longer reads ${infoKey}`);
	}
	assert.match(runApp, /if !dsn\.isEmpty \{[\s\S]*?SentrySDK\.start/);
});

test('release-ios.yml writes the config before the build and verifies the IPA before keeping or uploading it', () => {
	assert.ok(stepIndex(WRITE_STEP) < stepIndex('Build the signed IPA'), stepNames.join(' | '));
	assert.ok(stepIndex('Find the IPA') < stepIndex(VERIFY_STEP), stepNames.join(' | '));
	assert.ok(stepIndex(VERIFY_STEP) < stepIndex('Keep the signed IPA as an artifact'), stepNames.join(' | '));
	assert.ok(stepIndex(VERIFY_STEP) < stepIndex('Upload to TestFlight'), stepNames.join(' | '));

	for (const name of [WRITE_STEP, VERIFY_STEP]) {
		const body = stepBody(name);
		assert.ok(!/\bif:/.test(body), `${name} must not be conditional`);
		assert.match(body, /SUPABASE_URL: \$\{\{ secrets\.PUBLIC_SUPABASE_URL \}\}/, name);
		assert.match(body, /SUPABASE_ANON_KEY: \$\{\{ secrets\.PUBLIC_SUPABASE_ANON_KEY \}\}/, name);
		assert.match(body, /SENTRY_DSN: \$\{\{ secrets\.WATCH_IOS_SENTRY_DSN \}\}/, name);
		assert.match(body, /APP_RELEASE: \$\{\{ github\.event\.release\.tag_name \}\}/, name);
		assert.ok(!/\$\{\{ secrets\./.test(body.split('run:')[1] ?? ''), `${name} interpolates a secret into its shell`);
	}
	const verify = stepBody(VERIFY_STEP);
	assert.ok(verify.includes('Watch/WatchApp.app/Info.plist'), verify);
	assert.ok(verify.includes('node scripts/ios_watch_runtime_config.mjs verify -'), verify);

	const cleanup = stepBody('Remove the signing keychain and the runtime configs');
	assert.match(cleanup, /if: always\(\)/);
	assert.ok(cleanup.includes('apps/mobile_ios/ios/Flutter/WatchRuntime.xcconfig'), cleanup);
});

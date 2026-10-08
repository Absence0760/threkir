import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
	KEY_INFO_KEY,
	KEY_SETTING,
	URL_INFO_KEY,
	URL_SETTING,
	expandEscapes,
	main,
	normalizeKey,
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

test('the rendered xcconfig survives Xcode reading it: no // in a value, and the escape expands back', () => {
	const out = renderXcconfig({ url: ORIGIN, key: ANON_JWT });
	const settings = Object.fromEntries(
		out
			.split('\n')
			.filter((l) => l !== '' && !l.startsWith('//'))
			.map((l) => {
				assert.ok(!l.includes('//'), `an xcconfig would read the rest of this line as a comment: ${l}`);
				const [k, ...v] = l.split('=');
				return [k.trim(), expandEscapes(v.join('=').trim())];
			}),
	);
	assert.deepEqual(settings, { [URL_SETTING]: ORIGIN, [KEY_SETTING]: ANON_JWT });
});

test('the shipped plist passes only when both keys came through equal to the secrets', () => {
	const expected = { url: ORIGIN, key: PUBLISHABLE };
	const lines = verifyInfo({ [URL_INFO_KEY]: ORIGIN, [KEY_INFO_KEY]: PUBLISHABLE }, expected);
	assert.equal(lines.length, 2);
	for (const line of lines) {
		assert.ok(!line.includes(ORIGIN) && !line.includes('abcdefghijkl') && !line.includes(PUBLISHABLE), line);
	}

	for (const [info, needle] of /** @type {const} */ ([
		[{}, 'is empty'],
		[{ [URL_INFO_KEY]: '', [KEY_INFO_KEY]: '' }, 'is empty'],
		[{ [URL_INFO_KEY]: '$(SUPABASE_URL)', [KEY_INFO_KEY]: '$(SUPABASE_ANON_KEY)' }, 'unexpanded'],
		[{ [URL_INFO_KEY]: 'https:', [KEY_INFO_KEY]: PUBLISHABLE }, 'differs'],
		[{ [URL_INFO_KEY]: ORIGIN, [KEY_INFO_KEY]: 'sb_publishable_other' }, 'differs'],
	])) {
		assert.throws(
			() => verifyInfo(info, expected),
			(e) => e instanceof Error && e.message.includes(needle) && !e.message.includes(PUBLISHABLE) && !e.message.includes('abcdefghijkl'),
			JSON.stringify(info),
		);
	}
});

test('the command line prints an ::error:: and exits 1 on a bad secret, and never prints a value', (t) => {
	/** @type {string[]} */ const printed = [];
	t.mock.method(console, 'log', (/** @type {string} */ s) => printed.push(s));
	assert.equal(main(['write', '/dev/null'], { [URL_SETTING]: ORIGIN, [KEY_SETTING]: jwt({ role: 'service_role' }) }), 1);
	assert.match(printed.join('\n'), /^::error::/m);
	assert.equal(main(['write', '/dev/null'], { [URL_SETTING]: ORIGIN, [KEY_SETTING]: PUBLISHABLE }), 0);
	assert.equal(main(['frobnicate', 'x'], { [URL_SETTING]: ORIGIN, [KEY_SETTING]: PUBLISHABLE }), 1);
	const all = printed.join('\n');
	assert.ok(!all.includes('abcdefghijkl') && !all.includes(PUBLISHABLE), all);
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

const WRITE_STEP = "Write the watch app's Supabase config";
const VERIFY_STEP = 'The shipped watch app carries its Supabase config';

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
		assert.ok(!/\bSUPABASE_(ORIGIN|ANON_KEY) =/.test(body), `WatchApp ${name} sets a Supabase value in the committed project`);
	}

	const write = stepBody(WRITE_STEP);
	assert.ok(write.includes(`node scripts/ios_watch_runtime_config.mjs write ${included}`), write);

	assert.ok(
		read('apps/mobile_ios/ios/.gitignore').split('\n').includes(`Flutter/${include[1]}`),
		`${included} must be gitignored: it is generated from secrets and this repo is public`,
	);
});

test('the watch Info.plist expands exactly the two settings the script writes', () => {
	for (const [infoKey, setting] of [[URL_INFO_KEY, URL_SETTING], [KEY_INFO_KEY, KEY_SETTING]]) {
		assert.match(WATCH_PLIST, new RegExp(`<key>${infoKey}</key>\\s*<string>\\$\\(${setting}\\)</string>`));
	}
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
		assert.ok(!/\$\{\{ secrets\./.test(body.split('run:')[1] ?? ''), `${name} interpolates a secret into its shell`);
	}
	const verify = stepBody(VERIFY_STEP);
	assert.ok(verify.includes('Watch/WatchApp.app/Info.plist'), verify);
	assert.ok(verify.includes('node scripts/ios_watch_runtime_config.mjs verify -'), verify);

	const cleanup = stepBody('Remove the signing keychain and the runtime configs');
	assert.match(cleanup, /if: always\(\)/);
	assert.ok(cleanup.includes('apps/mobile_ios/ios/Flutter/WatchRuntime.xcconfig'), cleanup);
});

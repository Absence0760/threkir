import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import {
	ANY_OS,
	cacheSteps,
	checkCacheKeys,
	checkFlutterSdkCached,
	checkHashFilesPatterns,
	flutterSdkSteps,
	UNCACHED_FLUTTER,
	globToRegExp,
	hashFilesPatterns,
	osOf,
	withInput,
} from './check_cache_keys.mjs';
import { ACTION_DIR, WORKFLOW_DIR, readActions, readWorkflows } from './check_ci_diagnostics.mjs';

/**
 * A workflow with one job per entry, each caching `path` with `key` and
 * `restore`. Indentation matches what the shared step reader expects.
 * @param {{ job: string, runsOn: string, path: string, key: string, restore?: string }[]} jobs
 */
const workflow = (jobs) =>
	[
		'name: t',
		'on: push',
		'jobs:',
		...jobs.flatMap((j) => [
			`  ${j.job}:`,
			`    runs-on: ${j.runsOn}`,
			'    steps:',
			'      - uses: actions/checkout@0000000000000000000000000000000000000000',
			'      - name: Cache',
			'        uses: actions/cache@0000000000000000000000000000000000000000 # v6',
			'        with:',
			`          path: ${j.path}`,
			`          key: ${j.key}`,
			...(j.restore === undefined ? [] : [`          restore-keys: ${j.restore}`]),
		]),
		'',
	].join('\n');

/** @param {string} text */
const run = (text, actions = /** @type {{ name: string, text: string }[]} */ ([])) =>
	checkCacheKeys(cacheSteps([{ name: 'ci.yml', text }], actions));

test('the run 35642229273 shape fails: a bare restore key reaches the other OS', () => {
	const { errors } = run(
		workflow([
			{ job: 'android', runsOn: 'ubuntu-latest', path: '~/.pub-cache', key: "pub-cache-${{ hashFiles('**/pubspec.lock') }}", restore: 'pub-cache-' },
			{ job: 'ios', runsOn: 'macos-latest', path: '~/.pub-cache', key: "pub-cache-macos-${{ hashFiles('**/pubspec.lock') }}", restore: 'pub-cache-macos-' },
		]),
	);
	assert.ok(errors.some((e) => e.includes('(android)') && e.includes('restore key `pub-cache-`')), errors.join('\n'));
	assert.ok(errors.some((e) => e.includes('(ios)') && e.includes('key `pub-cache-macos-')), errors.join('\n'));
});

test('keying only one side apart is still a failure', () => {
	const { errors } = run(
		workflow([
			{ job: 'android', runsOn: 'ubuntu-latest', path: '~/.pub-cache', key: 'pub-cache-${{ hashFiles(\'x\') }}', restore: 'pub-cache-' },
			{ job: 'ios', runsOn: 'macos-latest', path: '~/.pub-cache', key: 'pub-cache-${{ runner.os }}-${{ hashFiles(\'x\') }}', restore: 'pub-cache-${{ runner.os }}-' },
		]),
	);
	assert.equal(errors.length, 2);
	assert.ok(errors.every((e) => e.includes('(android)')));
});

test('the OS in every key and restore key passes', () => {
	const { errors, shared } = run(
		workflow([
			{ job: 'android', runsOn: 'ubuntu-latest', path: '~/.pub-cache', key: 'pub-cache-${{ runner.os }}-${{ hashFiles(\'x\') }}', restore: 'pub-cache-${{ runner.os }}-' },
			{ job: 'ios', runsOn: 'macos-latest', path: '~/.pub-cache', key: 'pub-cache-${{runner.os}}-${{ hashFiles(\'x\') }}', restore: 'pub-cache-${{runner.os}}-' },
		]),
	);
	assert.deepEqual(errors, []);
	assert.equal(shared, 1);
});

test('a path cached on one OS only needs no OS in its key', () => {
	const { errors, shared } = run(
		workflow([
			{ job: 'a', runsOn: 'macos-latest', path: '~/.cocoapods', key: 'cocoapods-1', restore: 'cocoapods-' },
			{ job: 'b', runsOn: 'macos-latest', path: '~/.cocoapods', key: 'cocoapods-2', restore: 'cocoapods-' },
		]),
	);
	assert.deepEqual(errors, []);
	assert.equal(shared, 0);
});

test('different paths never share an entry, whatever the keys', () => {
	const { errors } = run(
		workflow([
			{ job: 'a', runsOn: 'ubuntu-latest', path: '~/.gradle', key: 'k-', restore: 'k-' },
			{ job: 'b', runsOn: 'macos-latest', path: '~/.cocoapods', key: 'k-', restore: 'k-' },
		]),
	);
	assert.deepEqual(errors, []);
});

test('a composite action runs on any OS, so its key must name the OS even alone', () => {
	const action = [
		'name: x',
		'runs:',
		'  using: composite',
		'  steps:',
		'    - uses: actions/cache@0000000000000000000000000000000000000000',
		'      with:',
		'        path: ~/.cache/tool',
		'        key: tool-1.0',
		'',
	].join('\n');
	const { errors } = checkCacheKeys(cacheSteps([], [{ name: 'tool/action.yml', text: action }]));
	assert.equal(errors.length, 1);
	assert.match(errors[0], /tool\/action\.yml:\d+ \(tool\/action\.yml\): the key `tool-1\.0`/);
});

test('block-scalar paths and restore keys are read line by line, comments dropped', () => {
	const body = [
		'      - uses: actions/cache@0000000000000000000000000000000000000000',
		'        with:',
		'          path: |',
		'            ~/.gradle/caches',
		'            # a comment',
		'            ~/.gradle/wrapper',
		"          key: 'gradle-${{ runner.os }}'",
		'          restore-keys: |',
		'            gradle-${{ runner.os }}-',
		'            gradle-',
	].join('\n');
	assert.deepEqual(withInput(body, 'path'), ['~/.gradle/caches', '~/.gradle/wrapper']);
	assert.deepEqual(withInput(body, 'key'), ['gradle-${{ runner.os }}']);
	assert.deepEqual(withInput(body, 'restore-keys'), ['gradle-${{ runner.os }}-', 'gradle-']);
	assert.deepEqual(withInput(body, 'save-always'), []);
});

test('runs-on resolves to runner.os spellings, and an expression to any OS', () => {
	assert.equal(osOf('ubuntu-latest'), 'Linux');
	assert.equal(osOf('macos-15'), 'macOS');
	assert.equal(osOf('windows-2022'), 'Windows');
	assert.equal(osOf('${{ matrix.os }}'), ANY_OS);
	assert.equal(osOf(null), ANY_OS);
});

test('the committed workflows and actions pass, and the reader sees their caches', () => {
	const steps = cacheSteps(readWorkflows(WORKFLOW_DIR), readActions(ACTION_DIR));
	assert.ok(steps.length >= 10, `read only ${steps.length} cache steps; the reader has probably broken`);
	assert.ok(
		steps.some((s) => s.paths.includes('~/.pub-cache') && s.os === 'macOS'),
		'the macOS pub-cache step this guard exists for is no longer read',
	);
	const { errors, shared } = checkCacheKeys(steps);
	assert.deepEqual(errors, []);
	assert.ok(shared >= 1);
});

const TRACKED = [
	'pubspec.lock',
	'apps/mobile_android/pubspec.yaml',
	'apps/mobile_android/android/app/build.gradle.kts',
	'apps/mobile_android/android/gradle/wrapper/gradle-wrapper.properties',
	'apps/custom_watch/core/Cargo.toml',
	'.github/actions/x/action.yml',
];

/** @param {string} key */
const deadIn = (key) => checkHashFilesPatterns(hashFilesPatterns([{ name: 'ci.yml', text: `          key: ${key}\n` }]), TRACKED);

test('the build-mobile-android shape fails: a per-app pubspec.lock in a pub workspace matches nothing', () => {
	const errors = deadIn(
		"gradle-${{ hashFiles('apps/mobile_android/android/**/*.gradle*', 'apps/mobile_android/android/gradle/wrapper/gradle-wrapper.properties', 'apps/mobile_android/pubspec.lock') }}",
	);
	assert.equal(errors.length, 1, errors.join('\n'));
	assert.match(errors[0], /^ci\.yml:1: the hashFiles\(\) pattern `apps\/mobile_android\/pubspec\.lock` matches no tracked file/);
});

test('the root lockfile, recursive globs, dotted paths and a directory pattern all match', () => {
	assert.deepEqual(deadIn("k-${{ hashFiles('pubspec.lock', '**/pubspec.lock', 'apps/custom_watch/**/Cargo.toml') }}"), []);
	assert.deepEqual(deadIn("k-${{ hashFiles('apps/mobile_android/android') }}"), []);
	assert.deepEqual(deadIn("k-${{ hashFiles('.github/**/action.yml') }}"), []);
});

test('a negated pattern that excludes nothing is dead too', () => {
	assert.equal(deadIn("k-${{ hashFiles('**/*.gradle*', '!apps/gone/**') }}").length, 1);
});

test('a non-literal argument is reported rather than skipped', () => {
	const errors = deadIn('k-${{ hashFiles(env.LOCK) }}');
	assert.equal(errors.length, 1);
	assert.match(errors[0], /`env\.LOCK`, which is not a string literal/);
});

test('comment lines are not read, and every call on a line is', () => {
	const patterns = hashFilesPatterns([
		{
			name: 'ci.yml',
			text: [
				"      # was: hashFiles('apps/gone/pubspec.lock')",
				"          key: a-${{ hashFiles('x', 'it''s') }}-${{ hashFiles('y') }}",
			].join('\n'),
		},
	]);
	assert.deepEqual(
		patterns.map((p) => [p.line, p.pattern]),
		[
			[2, 'x'],
			[2, "it's"],
			[2, 'y'],
		],
	);
});

test('glob segments follow @actions/glob: * stays in one segment, ** spans zero or more', () => {
	assert.ok(globToRegExp('apps/*/pubspec.yaml').test('apps/mobile_android/pubspec.yaml'));
	assert.ok(!globToRegExp('apps/*/pubspec.yaml').test('apps/a/b/pubspec.yaml'));
	assert.ok(globToRegExp('**/pubspec.lock').test('pubspec.lock'));
	assert.ok(globToRegExp('a/**/*.gradle*').test('a/b/c/build.gradle.kts'));
	assert.ok(globToRegExp('./deno.lock').test('deno.lock'));
	assert.ok(!globToRegExp('deno.lock').test('denoXlock'));
	assert.ok(globToRegExp('file[0-9].txt').test('file3.txt'));
	assert.ok(globToRegExp('file[!0-9].txt').test('fileA.txt'));
});

test('the reader sees the committed hashFiles() patterns, the workspace lockfile among them', () => {
	const patterns = hashFilesPatterns([...readWorkflows(WORKFLOW_DIR), ...readActions(ACTION_DIR)]);
	assert.ok(patterns.length >= 10, `read only ${patterns.length} hashFiles() patterns; the reader has probably broken`);
	assert.ok(patterns.every((p) => p.pattern !== null));
	assert.ok(
		patterns.some((p) => p.pattern === 'pubspec.lock'),
		'the mobile_android Gradle key no longer hashes the workspace lockfile',
	);
});

/**
 * A workflow whose one job installs Flutter, with or without `cache: true`.
 * @param {boolean} cached
 */
const flutterWorkflow = (cached) =>
	[
		'name: t',
		'on: push',
		'jobs:',
		'  docs:',
		'    runs-on: ubuntu-latest',
		'    steps:',
		'      - uses: subosito/flutter-action@0000000000000000000000000000000000000000 # v2',
		'        with:',
		'          channel: stable',
		'          flutter-version: ${{ env.FLUTTER_VERSION }}',
		...(cached ? ['          cache: true'] : []),
		'      - run: dart run scripts/x.dart',
		'',
	].join('\n');

test('the run 37864887082 shape fails: a Flutter install with no cache downloads the SDK every run', () => {
	const steps = flutterSdkSteps([{ name: 'ci.yml', text: flutterWorkflow(false) }], []);
	assert.equal(steps.length, 1);
	const errors = checkFlutterSdkCached(steps, new Map());
	assert.equal(errors.length, 1);
	assert.ok(errors[0].includes('ci.yml:') && errors[0].includes('(docs)') && errors[0].includes('cache: true'), errors[0]);
});

test('a cached Flutter install passes, and an exemption names its own workflow only', () => {
	const cached = flutterSdkSteps([{ name: 'ci.yml', text: flutterWorkflow(true) }], []);
	assert.deepEqual(checkFlutterSdkCached(cached, new Map()), []);
	const release = flutterSdkSteps([{ name: 'release-x.yml', text: flutterWorkflow(false) }], []);
	assert.deepEqual(checkFlutterSdkCached(release, new Map([['release-x.yml', 'signed release']])), []);
	assert.equal(checkFlutterSdkCached(release, new Map([['other.yml', 'signed release']])).length, 2);
});

test('an exemption for a workflow that now caches, or no longer installs Flutter, is stale', () => {
	const cached = flutterSdkSteps([{ name: 'release-x.yml', text: flutterWorkflow(true) }], []);
	const errors = checkFlutterSdkCached(cached, new Map([['release-x.yml', 'signed release']]));
	assert.equal(errors.length, 1);
	assert.ok(errors[0].includes('UNCACHED_FLUTTER names release-x.yml'), errors[0]);
});

test('every Flutter install in the real tree is cached or a named release exemption', () => {
	const steps = flutterSdkSteps(readWorkflows(WORKFLOW_DIR), readActions(ACTION_DIR));
	assert.ok(steps.length >= 5, `expected the tree's Flutter installs, read ${steps.length}`);
	assert.deepEqual(checkFlutterSdkCached(steps, UNCACHED_FLUTTER), []);
	for (const [file, why] of UNCACHED_FLUTTER) assert.ok(why.length > 20, `${file}'s exemption needs a reason`);
});

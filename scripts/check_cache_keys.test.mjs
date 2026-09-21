import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { ANY_OS, cacheSteps, checkCacheKeys, osOf, withInput } from './check_cache_keys.mjs';
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

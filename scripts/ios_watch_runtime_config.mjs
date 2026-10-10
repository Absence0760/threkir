#!/usr/bin/env node
// Gives the Apple Watch app its Supabase project and its Sentry config in a
// release, and proves the shipped bundle has them.
//
// The watch reads `SupabaseURL` / `SupabaseAnonKey` from its Info.plist, which
// expands them from the build settings `SUPABASE_URL` / `SUPABASE_ANON_KEY`
// (WatchAuth.swift's `SupabaseEnvironment`). `flutter build ipa` defines
// neither: `--dart-define-from-file` reaches Xcode only as Flutter's
// `DART_DEFINES`, one base64 list in Generated.xcconfig that the Dart build
// decodes and nothing on watchOS reads. So every release built before this
// script shipped a watch whose sign-in was fail-closed (decisions § 1810).
//
// The same gap held for `SENTRY_DSN` / `APP_RELEASE`, which `RunApp.init()`
// reads from Info.plist keys of those names: nothing defined either setting for
// the WatchApp target (decisions § 1819). `SENTRY_DSN` is optional — unset, it
// expands to empty and the watch starts no Sentry, as on Wear OS (§ 1763).
// `APP_RELEASE` is the GitHub Release's tag, `mobile_ios@<version>`: the watch
// has no tag of its own and ships only inside that one.
//
// `write` turns the values in the environment into the untracked
// `Flutter/WatchRuntime.xcconfig` that the committed `Flutter/WatchApp.xcconfig`
// `#include?`s. `verify` reads the shipped `WatchApp.app/Info.plist` (as JSON,
// from `plutil -convert json`) and fails unless every key came through equal
// to what was written — an empty DSN staying empty included. Neither prints a
// secret, only its length; the release tag is public and is printed.
//
// Usage (SENTRY_DSN may be unset or empty):
//   SUPABASE_URL=… SUPABASE_ANON_KEY=… SENTRY_DSN=… APP_RELEASE=mobile_ios@1.2.3 node scripts/ios_watch_runtime_config.mjs write <out.xcconfig>
//   plutil -convert json -o - <Info.plist> | SUPABASE_URL=… SUPABASE_ANON_KEY=… SENTRY_DSN=… APP_RELEASE=… node scripts/ios_watch_runtime_config.mjs verify -
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export const URL_SETTING = 'SUPABASE_URL';
export const KEY_SETTING = 'SUPABASE_ANON_KEY';
export const URL_INFO_KEY = 'SupabaseURL';
export const KEY_INFO_KEY = 'SupabaseAnonKey';
export const DSN_SETTING = 'SENTRY_DSN';
export const RELEASE_SETTING = 'APP_RELEASE';
/** `RunApp.swift` reads these Info.plist keys under the settings' own names. */
export const DSN_INFO_KEY = 'SENTRY_DSN';
export const RELEASE_INFO_KEY = 'APP_RELEASE';

/**
 * An origin and nothing else: the watch appends `/auth/v1/…` and `/rest/v1/…`
 * itself, so a path or a trailing slash is a malformed request later.
 */
const URL_SHAPE = /^https:\/\/[A-Za-z0-9.-]+(:[0-9]{1,5})?$/;

/**
 * A legacy anon JWT (three base64url segments) or an `sb_publishable_` key.
 * The character set is also what makes the value safe to write into an
 * xcconfig unescaped: no `$` to expand, no `/` to start a comment, no quote,
 * no whitespace.
 */
const KEY_SHAPE = /^[A-Za-z0-9._-]+$/;

/**
 * A current Sentry DSN: `https://<32-hex public key>@<host>[:port]/[path/]<project id>`.
 * No `key:secret@` form (the legacy secret half is a credential and has no
 * place in a binary), no http, nothing after the project id. The character set
 * also keeps the value xcconfig-safe once `//` is escaped.
 */
const DSN_SHAPE = /^https:\/\/[0-9a-f]{32}@[A-Za-z0-9.-]+(:[0-9]{1,5})?\/([A-Za-z0-9._-]+\/)*[0-9]+$/;

/** The tag a `mobile_ios` release is published under, which the watch ships inside. */
const RELEASE_SHAPE = /^mobile_ios@[0-9]+(\.[0-9]+){0,2}$/;

/**
 * The URL with the trailing slash an operator may have pasted removed, after
 * checking it is an https origin. Throws naming the setting, never the value.
 * @param {string | undefined} raw
 */
export function normalizeUrl(raw) {
	const value = (raw ?? '').trim().replace(/\/$/, '');
	if (value === '') throw new Error(`${URL_SETTING} is empty.`);
	if (!URL_SHAPE.test(value)) {
		throw new Error(
			`${URL_SETTING} is not an https origin (https://host[:port], no path). The watch builds its ` +
				'GoTrue and PostgREST URLs by appending to it, so anything else is a request that fails on the wrist.',
		);
	}
	return value;
}

/**
 * The anon key, after refusing anything that is not a client key. A
 * `service_role` JWT or an `sb_secret_` key in this secret would ship a key
 * that bypasses RLS inside a binary anyone can unzip.
 * @param {string | undefined} raw
 */
export function normalizeKey(raw) {
	const value = (raw ?? '').trim();
	if (value === '') throw new Error(`${KEY_SETTING} is empty.`);
	if (!KEY_SHAPE.test(value)) {
		throw new Error(`${KEY_SETTING} holds characters no Supabase client key has (allowed: A-Z a-z 0-9 . _ -).`);
	}
	if (value.startsWith('sb_secret_')) {
		throw new Error(`${KEY_SETTING} is an sb_secret_ key. A client binary carries the publishable key only.`);
	}
	const parts = value.split('.');
	if (parts.length === 3) {
		let role;
		try {
			role = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8')).role;
		} catch {
			throw new Error(`${KEY_SETTING} has the shape of a JWT and its payload does not decode.`);
		}
		if (role !== 'anon') {
			throw new Error(`${KEY_SETTING} is a JWT whose role is not anon. A client binary carries the anon key only.`);
		}
	} else if (!value.startsWith('sb_publishable_')) {
		throw new Error(`${KEY_SETTING} is neither an anon JWT nor an sb_publishable_ key.`);
	}
	return value;
}

/**
 * The DSN, or '' when the release sets none — which is not an error: an empty
 * `SENTRY_DSN` leaves the watch's Sentry off (`RunApp.init()` gates on it), the
 * contract Wear OS keeps too (decisions § 1763). A set value must be a DSN.
 * @param {string | undefined} raw
 */
export function normalizeDsn(raw) {
	const value = (raw ?? '').trim();
	if (value === '') return '';
	if (/^https:\/\/[^@/]*:[^@/]*@/.test(value)) {
		throw new Error(`${DSN_SETTING} carries a legacy secret key (key:secret@). A client binary carries the public key only.`);
	}
	if (!DSN_SHAPE.test(value)) {
		throw new Error(
			`${DSN_SETTING} is not a Sentry DSN (https://<32-hex key>@<host>/<project id>). ` +
				'Leave it unset to ship the watch without crash reporting.',
		);
	}
	return value;
}

/**
 * The release tag, `mobile_ios@<version>`. Required: it is the GitHub Release
 * the watch shipped inside, and the only tag that resolves to its commit.
 * @param {string | undefined} raw
 */
export function normalizeRelease(raw) {
	const value = (raw ?? '').trim();
	if (value === '') throw new Error(`${RELEASE_SETTING} is empty.`);
	if (!RELEASE_SHAPE.test(value)) {
		throw new Error(`${RELEASE_SETTING} is not a mobile_ios@<version> release tag (one to three dot-separated integers).`);
	}
	return value;
}

/**
 * An xcconfig line runs to its end except that `//` starts a comment, so
 * `https://host` would be read as `https:`. `$()` expands to nothing, and
 * putting one after every slash leaves no two slashes adjacent.
 * @param {string} value
 */
export function xcconfigEscape(value) {
	return value.replaceAll('/', '/$()');
}

/** @typedef {{ url: string, key: string, dsn: string, release: string }} RuntimeConfig */

/**
 * An empty DSN is written as an explicit empty setting rather than left out,
 * so nothing else can define one for the watch.
 * @param {RuntimeConfig} values
 */
export function renderXcconfig({ url, key, dsn, release }) {
	return (
		'// Generated by scripts/ios_watch_runtime_config.mjs in release-ios.yml. Untracked;\n' +
		'// never commit it. Flutter/WatchApp.xcconfig includes it when present.\n' +
		`${URL_SETTING} = ${xcconfigEscape(url)}\n` +
		`${KEY_SETTING} = ${key}\n` +
		(dsn === '' ? `${DSN_SETTING} =\n` : `${DSN_SETTING} = ${xcconfigEscape(dsn)}\n`) +
		`${RELEASE_SETTING} = ${release}\n`
	);
}

/**
 * Reverses what Xcode does to a setting before it lands in the plist, so a
 * test can assert the round trip without Xcode.
 * @param {string} line
 */
export function expandEscapes(line) {
	return line.replaceAll('$()', '');
}

/** @param {string} value */
function shapeOf(value) {
	return `length ${value.length}`;
}

/**
 * Checks the shipped Info.plist against the values the release was given.
 * Returns the summary lines to print; throws naming the key that is wrong.
 * @param {Record<string, unknown>} info
 * @param {RuntimeConfig} expected
 */
export function verifyInfo(info, expected) {
	/** @type {string[]} */ const problems = [];
	/** @param {string} infoKey @param {string} want @param {string} setting @param {string} cost */
	const check = (infoKey, want, setting, cost) => {
		const got = info[infoKey];
		if (typeof got !== 'string' || got.trim() === '') {
			problems.push(`${infoKey} is empty — ${setting} was undefined for the WatchApp target, so ${cost}.`);
		} else if (got.includes('$(')) {
			problems.push(`${infoKey} still holds an unexpanded build-setting reference, so ${cost}.`);
		} else if (got !== want) {
			problems.push(
				`${infoKey} is set but differs from the release value (built ${shapeOf(got)}, release ${shapeOf(want)}). ` +
					'An xcconfig comment or escape has eaten part of it.',
			);
		}
	};
	const signIn = 'sign-in on the wrist is fail-closed';
	check(URL_INFO_KEY, expected.url, URL_SETTING, signIn);
	check(KEY_INFO_KEY, expected.key, KEY_SETTING, signIn);
	check(RELEASE_INFO_KEY, expected.release, RELEASE_SETTING, 'Sentry events from the watch name no release');
	if (expected.dsn === '') {
		const got = info[DSN_INFO_KEY];
		if (got !== undefined && got !== '') {
			problems.push(`${DSN_INFO_KEY} is set in the shipped watch app although the release set no ${DSN_SETTING}.`);
		}
	} else {
		check(DSN_INFO_KEY, expected.dsn, DSN_SETTING, 'the watch ships with crash reporting off');
	}
	if (problems.length > 0) throw new Error(problems.join(' '));
	return [
		`${URL_INFO_KEY}: https origin present, ${shapeOf(expected.url)}, equal to the release secret`,
		`${KEY_INFO_KEY}: present, ${shapeOf(expected.key)}, equal to the release secret`,
		expected.dsn === ''
			? `${DSN_INFO_KEY}: empty, as the release set none, so the watch starts no Sentry`
			: `${DSN_INFO_KEY}: present, ${shapeOf(expected.dsn)}, equal to the release secret`,
		`${RELEASE_INFO_KEY}: ${expected.release}`,
	];
}

/** @param {string[]} argv @param {NodeJS.ProcessEnv} env */
export function main(argv, env) {
	const [command, path] = argv;
	try {
		/** @type {RuntimeConfig} */
		const expected = {
			url: normalizeUrl(env[URL_SETTING]),
			key: normalizeKey(env[KEY_SETTING]),
			dsn: normalizeDsn(env[DSN_SETTING]),
			release: normalizeRelease(env[RELEASE_SETTING]),
		};
		if (command === 'write' && path) {
			writeFileSync(path, renderXcconfig(expected));
			const dsn = expected.dsn === '' ? `${DSN_SETTING} (empty: Sentry off)` : `${DSN_SETTING} (${shapeOf(expected.dsn)})`;
			console.log(
				`Wrote ${URL_SETTING} (${shapeOf(expected.url)}), ${KEY_SETTING} (${shapeOf(expected.key)}), ${dsn} ` +
					`and ${RELEASE_SETTING} (${expected.release}) to ${path}`,
			);
			return 0;
		}
		if (command === 'verify' && path) {
			const info = JSON.parse(readFileSync(path === '-' ? 0 : path, 'utf8'));
			for (const line of verifyInfo(info, expected)) console.log(line);
			return 0;
		}
		console.log('::error::Usage: node scripts/ios_watch_runtime_config.mjs write <out.xcconfig> | verify <Info.json|->');
		return 1;
	} catch (e) {
		console.log(`::error::${e instanceof Error ? e.message : String(e)}`);
		return 1;
	}
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main(process.argv.slice(2), process.env));

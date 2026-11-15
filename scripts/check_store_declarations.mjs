#!/usr/bin/env node
// Guardrail: every permission, foreground service type, Health Connect data
// type, usage description, background mode, HealthKit type, required-reason
// API and collected-data type the shipped code requests is listed in
// docs/compliance/store_declarations.json, with the store-console form that
// must declare it and what that console is known to hold.
//
// Why this exists: watch_wear@1.1.0 was refused by Google Play with a 403,
// "You must let us know whether your app uses any Foreground Service
// permissions". The watch's RunRecordingService declares
// foregroundServiceType="location|health"; since #1380 the watch ships in the
// phone's Play record (com.threkir.app), whose console had only ever declared
// location. Nothing in the repo knew what the consoles hold, so the drift was
// found by the store. A declaration that does not match the binary risks a
// rejection or a removal, not just a failed upload.
//
// The code side is DERIVED from the files that ship (manifests, plists,
// privacy manifests, the HealthKit requests), never restated here; the
// registry is the one place the console side is written down. The check fails
// both ways: a request the registry lacks (declare it in the console, then
// add the entry) and an entry nothing requests any more (undeclare it, then
// delete the entry). Manifest entries Gradle merges in from a plugin are out
// of reach without a build, so the registry names the plugin for each one it
// knows, and the check holds that the plugin is still in pubspec.lock.
//
// Run: `node scripts/check_store_declarations.mjs`
// CI:  the `ios-native-declarations` job in .github/workflows/ci.yml.
// Unit tests: `node --test scripts/check_store_declarations.test.mjs`
// Registry and how to update it: docs/compliance/store_declarations.md

import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parsePlist } from './check_ios_native_declarations.mjs';
import { stripSwiftComments } from './check_watch_ios_source.mjs';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

export const REGISTRY = 'docs/compliance/store_declarations.json';
export const PUBSPEC_LOCK = 'pubspec.lock';
export const STATUSES = ['declared', 'pending', 'unknown', 'not_required'];

/** @typedef {'phone' | 'wear_os' | 'ios' | 'watchos'} Target */

/**
 * The Android sources that ship, per Play form factor. Only `src/main`
 * reaches a release build here: there is no `src/release` set.
 * @type {Array<{ target: Target, manifest: string, healthPermissions?: string }>}
 */
export const ANDROID_SOURCES = [
	{
		target: 'phone',
		manifest: 'apps/mobile_android/android/app/src/main/AndroidManifest.xml',
		healthPermissions: 'apps/mobile_android/android/app/src/main/res/xml/health_permissions.xml',
	},
	{ target: 'wear_os', manifest: 'apps/watch_wear/android/app/src/main/AndroidManifest.xml' },
];

/** Tracked manifests that never reach a store build, and why. */
export const UNSHIPPED_ANDROID_MANIFESTS = new Map([
	['apps/mobile_android/android/app/src/debug/AndroidManifest.xml', 'debug build type only'],
	['apps/mobile_android/android/app/src/profile/AndroidManifest.xml', 'profile build type only'],
]);

/** The roots a new Android manifest would appear under. */
export const ANDROID_ROOTS = ['apps/mobile_android/android/', 'apps/watch_wear/'];

/**
 * The App Store record's bundles, per target. Every bundle's Info.plist and
 * PrivacyInfo.xcprivacy is read.
 * @type {Array<{ target: Target, root: string, bundles: string[] }>}
 */
export const IOS_SOURCES = [
	{ target: 'ios', root: 'apps/mobile_ios/ios', bundles: ['Runner', 'RunActivity', 'ShareExtension'] },
	{ target: 'watchos', root: 'apps/watch_ios', bundles: ['WatchApp', 'Complications'] },
];

/** The roots a new iOS bundle would appear under. */
export const IOS_ROOTS = ['apps/mobile_ios/ios/', 'apps/watch_ios/'];

/** The phone's HealthKit request (the byte-identical twin's copy is the iOS one). */
export const IOS_HEALTH_REQUEST = 'apps/mobile_ios/lib/health_connect_importer.dart';

/** Where the watch's HealthKit types are used. */
export const WATCH_HEALTHKIT_DIR = 'apps/watch_ios/WatchApp';

/** Where each category is declared, for the failure message. */
export const CONSOLE = {
	android_permissions: 'Google Play Console (record com.threkir.app)',
	foreground_service_types: 'Google Play Console → App content → Foreground service permissions',
	health_connect: 'Google Play Console → App content → Health apps (Health Connect data access)',
	data_safety: 'Google Play Console → App content → Data safety',
	usage_descriptions: 'App Store Connect (record com.threkir.app)',
	background_modes: 'App Store Connect → App Review Information → Notes',
	healthkit_types: 'App Store Connect → App Privacy (Health & Fitness)',
	required_reason_apis: 'the bundle PrivacyInfo.xcprivacy (checked by App Store Connect at upload)',
	app_privacy_label: 'App Store Connect → App Privacy',
};

/** @typedef {keyof typeof CONSOLE} Category */

export const PLAY_DERIVED = /** @type {const} */ (['android_permissions', 'foreground_service_types', 'health_connect']);
export const APPLE_DERIVED = /** @type {const} */ ([
	'usage_descriptions',
	'background_modes',
	'healthkit_types',
	'required_reason_apis',
	'app_privacy_label',
]);

/**
 * @typedef {{ key: string, in: Target[], form: string | null, status: string, verified_on?: string,
 *   evidence?: string, note?: string, plugins?: string[], services?: Record<string, string[]>,
 *   apple_equivalent?: string }} Entry
 * @typedef {{ category: string, key: string, status: string, evidence: string }} ConsoleOnly
 * @typedef {{ record: string, form_factors: Target[], android_permissions: Entry[],
 *   foreground_service_types: Entry[], health_connect: Entry[], data_safety: Entry[],
 *   console_only: ConsoleOnly[] }} PlayRecord
 * @typedef {{ record: string, targets: Target[], usage_descriptions: Entry[], background_modes: Entry[],
 *   healthkit_types: Entry[], required_reason_apis: Entry[], app_privacy_label: Entry[] }} AppStoreRecord
 * @typedef {{ play: PlayRecord, app_store: AppStoreRecord }} Registry
 */

/**
 * What the code requests: category → key → target → the file that requests it.
 * @typedef {Map<string, Map<string, Map<Target, string>>>} Derived
 */

/** @returns {Derived} */
export function emptyDerived() {
	return new Map();
}

/**
 * @param {Derived} d
 * @param {string} category
 * @param {string} key
 * @param {Target} target
 * @param {string} file
 */
export function note(d, category, key, target, file) {
	let byKey = d.get(category);
	if (!byKey) d.set(category, (byKey = new Map()));
	let byTarget = byKey.get(key);
	if (!byTarget) byKey.set(key, (byTarget = new Map()));
	if (!byTarget.has(target)) byTarget.set(target, file);
}

// --- Android -----------------------------------------------------------------------

/**
 * The document with its comments removed, read the way an XML parser reads
 * them: a comment runs from `<!--` to the first `-->`, its body may not hold
 * `--`, and it must close. A manifest that breaks any of those is one aapt2
 * refuses, so it is reported rather than guessed at - a regex replace leaves
 * an unterminated comment's commented-out permissions in place, and a nested
 * one's tail outside it.
 * @param {string} xml
 * @param {string} [file]
 */
export function stripXmlComments(xml, file = 'the document') {
	let out = '';
	let at = 0;
	for (;;) {
		const open = xml.indexOf('<!--', at);
		if (open === -1) break;
		out += xml.slice(at, open);
		const close = xml.indexOf('-->', open + 4);
		if (close === -1) throw new Error(`${file}: a comment opened at offset ${open} never closes, so what follows it is not markup the build reads.`);
		const inner = xml.indexOf('--', open + 4);
		if (inner !== close) {
			throw new Error(
				`${file}: the comment opened at offset ${open} holds "--" before its close. XML forbids it, and it is how a nested comment leaves its tail outside the outer one.`,
			);
		}
		at = close + 3;
	}
	out += xml.slice(at);
	if (out.includes('<!--')) throw new Error(`${file}: removing the comments joined two fragments into a new "<!--", which no well-formed document can produce.`);
	return out;
}

/**
 * @param {string} tag
 * @param {string} attr
 * @returns {string | undefined}
 */
function attribute(tag, attr) {
	const name = attr.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
	const m = tag.match(new RegExp(`\\b${name}\\s*=\\s*"([^"]*)"`));
	return m?.[1];
}

/**
 * The permissions and foreground services one manifest declares. A
 * `tools:node="remove"` permission is one the merge deletes, so it does not
 * ship.
 * @param {string} xml
 * @param {string} [file]
 * @returns {{ permissions: string[], services: Array<{ name: string, types: string[] }> }}
 */
export function parseManifest(xml, file) {
	const src = stripXmlComments(xml, file);
	const permissions = [];
	for (const [tag] of src.matchAll(/<uses-permission(?:-sdk-23)?\b[^>]*>/g)) {
		const name = attribute(tag, 'android:name');
		if (!name || attribute(tag, 'tools:node') === 'remove') continue;
		permissions.push(name);
	}
	const services = [];
	for (const [tag] of src.matchAll(/<service\b[^>]*>/g)) {
		const types = attribute(tag, 'android:foregroundServiceType');
		if (!types) continue;
		services.push({ name: attribute(tag, 'android:name') ?? '?', types: types.split('|').map((t) => t.trim()) });
	}
	return { permissions, services };
}

/**
 * @param {string} xml
 * @param {string} [file]
 */
export function parseHealthPermissions(xml, file) {
	return [...stripXmlComments(xml, file).matchAll(/<permission\b[^>]*\bname\s*=\s*"([^"]+)"/g)].map((m) => m[1]);
}

export const HEALTH_PREFIX = 'android.permission.health.';

// --- Apple -------------------------------------------------------------------------

/**
 * @param {unknown} v
 * @returns {unknown[]}
 */
const asArray = (v) => (Array.isArray(v) ? v : []);
/**
 * @param {unknown} v
 * @returns {Map<string, unknown>}
 */
const asMap = (v) => (v instanceof Map ? v : new Map());

/**
 * Usage-description keys and background modes from one Info.plist.
 * @param {string} xml
 */
export function parseInfoPlist(xml) {
	const root = parsePlist(xml) ?? new Map();
	const usage = [...root.keys()].filter((k) => /UsageDescription/.test(k));
	const modes = [...asArray(root.get('UIBackgroundModes')), ...asArray(root.get('WKBackgroundModes'))].map(String);
	return { usage, modes };
}

const API_PREFIX = 'NSPrivacyAccessedAPICategory';
const DATA_PREFIX = 'NSPrivacyCollectedDataType';

/**
 * Required-reason APIs (`Category:reason`), collected data types, and every
 * tracking flag, from one PrivacyInfo.xcprivacy.
 * @param {string} xml
 */
export function parsePrivacyManifest(xml) {
	const root = parsePlist(xml) ?? new Map();
	const apis = [];
	for (const item of asArray(root.get('NSPrivacyAccessedAPITypes'))) {
		const m = asMap(item);
		const category = String(m.get('NSPrivacyAccessedAPIType') ?? '').replace(API_PREFIX, '');
		for (const reason of asArray(m.get('NSPrivacyAccessedAPITypeReasons'))) apis.push(`${category}:${reason}`);
	}
	const collected = [];
	let tracking = root.get('NSPrivacyTracking') === true;
	for (const item of asArray(root.get('NSPrivacyCollectedDataTypes'))) {
		const m = asMap(item);
		collected.push(String(m.get('NSPrivacyCollectedDataType') ?? '').replace(DATA_PREFIX, ''));
		if (m.get('NSPrivacyCollectedDataTypeTracking') === true) tracking = true;
	}
	return { apis, collected, tracking };
}

/**
 * The `health` plugin types the phone asks HealthKit for: the
 * `requestPermission()` list, minus the entries gated on Platform.isAndroid.
 * @param {string} dart
 */
export function iosHealthPluginTypes(dart) {
	const body = dart.match(/static Future<bool> requestPermission\(\)[\s\S]*?final types = \[([\s\S]*?)\];/);
	if (!body) return null;
	const code = body[1].replace(/\/\/.*$/gm, '');
	return [...code.matchAll(/(if\s*\(\s*Platform\.isAndroid\s*\)\s*)?HealthDataType\.(\w+)/g)]
		.filter((m) => !m[1])
		.map((m) => m[2]);
}

/** @param {string} camel */
const upperSnake = (camel) => camel.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toUpperCase();

/**
 * Every HealthKit type the watch's Swift touches, in the `health` plugin's
 * UPPER_SNAKE vocabulary so one key names the same type on both targets
 * (`.heartRate` → HEART_RATE, `workoutType()` → WORKOUT).
 * @param {string} swift comment-stripped source
 */
export function swiftHealthKitTypes(swift) {
	const out = new Set();
	for (const m of swift.matchAll(/HK(?:Quantity|Category)Type(?:Identifier)?\s*(?:\(\s*\.|\.)(\w+)/g)) {
		if (m[1] !== 'init') out.add(upperSnake(m[1]));
	}
	if (/\bworkoutType\(\)/.test(swift)) out.add('WORKOUT');
	if (/HKSeriesType\.workoutRoute\(\)/.test(swift)) out.add('WORKOUT_ROUTE');
	return [...out];
}

// --- Reading the tree --------------------------------------------------------------

/**
 * @param {string} root
 * @returns {string[]}
 */
export function trackedFiles(root = REPO_ROOT) {
	return execFileSync('git', ['ls-files'], { cwd: root, encoding: 'utf8' }).split('\n').filter(Boolean);
}

/**
 * Every shipped source, read and derived. `problems` collects sources the
 * guard does not know how to classify (a new manifest, a new bundle).
 * @param {{ read: (path: string) => string, files: string[] }} io
 */
export function derive({ read, files }) {
	const d = emptyDerived();
	/** @type {string[]} */
	const problems = [];

	const scanned = new Set(ANDROID_SOURCES.map((s) => s.manifest));
	for (const f of files) {
		if (!f.endsWith('/AndroidManifest.xml') || !ANDROID_ROOTS.some((r) => f.startsWith(r))) continue;
		if (/\/src\/(test|androidTest)\//.test(f)) continue;
		if (!scanned.has(f) && !UNSHIPPED_ANDROID_MANIFESTS.has(f)) {
			problems.push(
				`${f} is a manifest this guard does not read. If it ships, add it to ANDROID_SOURCES in scripts/check_store_declarations.mjs; if it does not, add it to UNSHIPPED_ANDROID_MANIFESTS with the reason.`,
			);
		}
	}

	for (const src of ANDROID_SOURCES) {
		let parsed;
		try {
			parsed = parseManifest(read(src.manifest), src.manifest);
		} catch (e) {
			problems.push(e instanceof Error ? e.message : String(e));
			continue;
		}
		const { permissions, services } = parsed;
		const health = [];
		for (const p of permissions) {
			if (p.startsWith(HEALTH_PREFIX)) {
				health.push(p);
				note(d, 'health_connect', p.slice(HEALTH_PREFIX.length), src.target, src.manifest);
			} else note(d, 'android_permissions', p, src.target, src.manifest);
		}
		for (const s of services) for (const t of s.types) note(d, 'foreground_service_types', t, src.target, src.manifest);
		if (src.healthPermissions) {
			let listed;
			try {
				listed = parseHealthPermissions(read(src.healthPermissions), src.healthPermissions);
			} catch (e) {
				problems.push(e instanceof Error ? e.message : String(e));
				continue;
			}
			const a = [...new Set(health)].sort().join(',');
			const b = [...new Set(listed)].sort().join(',');
			if (a !== b) {
				problems.push(
					`${src.healthPermissions} lists [${b}] but ${src.manifest} requests [${a}]. Play's Health Connect review reads the XML; make the two the same set.`,
				);
			}
		} else if (health.length > 0) {
			problems.push(`${src.manifest} requests Health Connect permissions but has no health_permissions.xml registered in ANDROID_SOURCES.`);
		}
	}

	const bundleDirs = new Set(IOS_SOURCES.flatMap((s) => s.bundles.map((b) => `${s.root}/${b}/`)));
	for (const f of files) {
		if (!IOS_ROOTS.some((r) => f.startsWith(r))) continue;
		if (!/\/(Info\.plist|PrivacyInfo\.xcprivacy)$/.test(f)) continue;
		const dir = f.slice(0, f.lastIndexOf('/') + 1);
		if (!bundleDirs.has(dir)) {
			problems.push(
				`${f} belongs to a bundle this guard does not read. If it ships in the App Store record, add the bundle to IOS_SOURCES in scripts/check_store_declarations.mjs.`,
			);
		}
	}

	for (const src of IOS_SOURCES) {
		for (const bundle of src.bundles) {
			const info = `${src.root}/${bundle}/Info.plist`;
			const priv = `${src.root}/${bundle}/PrivacyInfo.xcprivacy`;
			const { usage, modes } = parseInfoPlist(read(info));
			for (const k of usage) note(d, 'usage_descriptions', k, src.target, info);
			for (const m of modes) note(d, 'background_modes', m, src.target, info);
			const { apis, collected, tracking } = parsePrivacyManifest(read(priv));
			for (const a of apis) note(d, 'required_reason_apis', a, src.target, priv);
			for (const c of collected) note(d, 'app_privacy_label', c, src.target, priv);
			if (tracking) {
				problems.push(
					`${priv} declares tracking. Nothing here tracks: App Privacy answers "Used to track" No everywhere and there is no App Tracking Transparency prompt. Changing that is a decision for the owner, not a manifest edit.`,
				);
			}
		}
	}

	const phoneTypes = iosHealthPluginTypes(read(IOS_HEALTH_REQUEST));
	if (phoneTypes === null) {
		problems.push(`${IOS_HEALTH_REQUEST}: requestPermission()'s \`final types = [...]\` list was not found, so the iPhone's HealthKit types cannot be read. Update iosHealthPluginTypes.`);
	} else for (const t of phoneTypes) note(d, 'healthkit_types', t, 'ios', IOS_HEALTH_REQUEST);
	for (const f of files) {
		if (!f.startsWith(`${WATCH_HEALTHKIT_DIR}/`) || !f.endsWith('.swift')) continue;
		for (const t of swiftHealthKitTypes(stripSwiftComments(read(f)))) note(d, 'healthkit_types', t, 'watchos', f);
	}

	return { derived: d, problems };
}

// --- The comparison ---------------------------------------------------------------

/**
 * @param {Registry} registry
 * @param {Derived} derived
 * @param {{ lockedPackages: Set<string> }} ctx
 * @returns {{ errors: string[], notices: string[] }}
 */
export function evaluate(registry, derived, { lockedPackages }) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const notices = [];
	const play = registry.play;
	const apple = registry.app_store;

	/**
	 * @param {Category} category
	 * @param {Entry[]} entries
	 * @param {Target[]} targets
	 */
	const validate = (category, entries, targets) => {
		const seen = new Set();
		for (const e of entries ?? []) {
			const where = `${REGISTRY} ${category} "${e.key}"`;
			if (seen.has(e.key)) errors.push(`${where} is listed twice.`);
			seen.add(e.key);
			if (!STATUSES.includes(e.status)) errors.push(`${where}: status "${e.status}" is not one of ${STATUSES.join(', ')}.`);
			if (e.form === null && e.status !== 'not_required') errors.push(`${where}: form is null, so status must be not_required.`);
			if (e.form !== null && e.status === 'not_required') errors.push(`${where}: status not_required needs form: null.`);
			if (e.form !== null && typeof e.form !== 'string') errors.push(`${where}: form must be a string or null.`);
			if (e.verified_on !== undefined) {
				if (!/^\d{4}-\d{2}-\d{2}$/.test(e.verified_on)) errors.push(`${where}: verified_on must be YYYY-MM-DD.`);
				if (e.status !== 'declared') errors.push(`${where}: only a declared entry carries verified_on.`);
			}
			if (e.form !== null && !e.evidence) errors.push(`${where}: an entry with a console form needs evidence for its status.`);
			for (const t of e.in ?? []) if (!targets.includes(t)) errors.push(`${where}: "${t}" is not one of ${targets.join(', ')}.`);
			if (e.status === 'pending' || e.status === 'unknown') {
				notices.push(`${category} ${e.key} [${(e.in ?? []).join(', ')}] is ${e.status} in ${e.form}.`);
			}
		}
	};

	/**
	 * @param {Category} category
	 * @param {Entry[]} entries
	 * @param {Target[]} targets
	 */
	const compare = (category, entries, targets) => {
		validate(category, entries, targets);
		const byKey = new Map((entries ?? []).map((e) => [e.key, e]));
		const code = derived.get(category) ?? new Map();
		for (const [key, byTarget] of code) {
			const entry = byKey.get(key);
			for (const [target, file] of byTarget) {
				if (entry?.in?.includes(target)) continue;
				const form = entry ? (entry.form ?? 'no console form') : 'decide which console form, if any, declares it';
				errors.push(
					`${category} "${key}" is requested by ${file} (${target}) but ${REGISTRY} does not list it for ${target}. ` +
						`Console: ${entry?.form ?? CONSOLE[category]} (${form}). Declare it there first, then add "${target}" to the entry's "in"` +
						(entry ? '.' : ' in a new entry with the form, status and evidence.'),
				);
			}
		}
		for (const e of entries ?? []) {
			for (const t of e.in ?? []) {
				if (code.get(e.key)?.has(t)) continue;
				errors.push(
					`${category} "${e.key}" is listed for ${t} in ${REGISTRY} but no shipped ${t} source requests it any more. ` +
						`Console: ${e.form ?? CONSOLE[category]}. Remove the declaration there if nothing else needs it, then drop "${t}" from the entry` +
						(e.plugins?.length ? ' (its plugins stay as they are).' : ' (delete the entry once "in" is empty).'),
				);
			}
			if ((e.in ?? []).length === 0 && !(e.plugins?.length)) {
				errors.push(`${category} "${e.key}" in ${REGISTRY} has neither a target nor a plugin that requests it. Delete it, after undeclaring it in ${e.form ?? CONSOLE[category]}.`);
			}
		}
	};

	for (const c of PLAY_DERIVED) compare(c, play[c], play.form_factors);
	for (const c of APPLE_DERIVED) compare(c, apple[c], apple.targets);

	for (const e of play.android_permissions ?? []) {
		for (const p of e.plugins ?? []) {
			if (!lockedPackages.has(p)) {
				errors.push(
					`android_permissions "${e.key}" names plugin ${p}, which ${PUBSPEC_LOCK} no longer resolves. If the permission went with it, undeclare it in ${e.form ?? CONSOLE.android_permissions} and drop the plugin from the entry.`,
				);
			}
		}
	}

	validate('data_safety', play.data_safety, play.form_factors);
	const androidEquivalents = new Set((play.data_safety ?? []).map((e) => e.apple_equivalent));
	for (const e of apple.app_privacy_label ?? []) {
		if (!androidEquivalents.has(e.key)) {
			errors.push(
				`app_privacy_label "${e.key}" has no data_safety entry whose apple_equivalent is "${e.key}". The phone apps share one Dart codebase, so data the iPhone app collects the Android app collects too: declare it in ${CONSOLE.data_safety}, then add the entry.`,
			);
		}
	}
	for (const e of play.data_safety ?? []) {
		if (e.apple_equivalent && !(apple.app_privacy_label ?? []).some((l) => l.key === e.apple_equivalent)) {
			errors.push(`data_safety "${e.key}" names apple_equivalent "${e.apple_equivalent}", which no app_privacy_label entry has.`);
		}
	}

	for (const o of play.console_only ?? []) {
		if (!STATUSES.includes(o.status)) errors.push(`${REGISTRY} console_only "${o.key}": status "${o.status}" is not one of ${STATUSES.join(', ')}.`);
		const live = derived.get(o.category)?.has(o.key);
		if (live) {
			errors.push(`${REGISTRY} console_only "${o.key}" is requested by the code again; move it into ${o.category} as an ordinary entry.`);
		} else {
			notices.push(`console_only ${o.category} ${o.key} is ${o.status}: the code does not request it, so remove it from the console if it is still declared there.`);
		}
	}

	return { errors, notices };
}

/** @param {string} lock */
export function lockedPackageNames(lock) {
	return new Set([...lock.matchAll(/^ {2}([a-z0-9_]+):\s*$/gm)].map((m) => m[1]));
}

export function main(root = REPO_ROOT) {
	/** @param {string} p */
	const read = (p) => readFileSync(join(root, p), 'utf8');
	/** @type {Registry} */
	const registry = JSON.parse(read(REGISTRY));
	const { derived, problems } = derive({ read, files: trackedFiles(root) });
	const { errors, notices } = evaluate(registry, derived, { lockedPackages: lockedPackageNames(read(PUBSPEC_LOCK)) });
	const all = [...problems, ...errors];
	for (const n of notices) console.log(`[OWNER TO CONFIRM] ${n}`);
	for (const e of all) console.error(`[FAIL] ${e}`);
	if (all.length > 0) {
		console.error(
			`\n${all.length} store-declaration problem(s). Update the store console first, then ${REGISTRY}; docs/compliance/store_declarations.md says how.`,
		);
		return 1;
	}
	let count = 0;
	for (const m of derived.values()) count += m.size;
	console.log(`\n${count} code-requested declaration(s) match ${REGISTRY}; ${notices.length} console state(s) still to confirm.`);
	return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());

#!/usr/bin/env node
// Points the iOS release archive at the App Store provisioning profiles CI was
// handed, and writes the ExportOptions.plist that exports it.
//
// The committed Xcode project signs automatically, so a Mac builds and runs on
// a device with no setup. A runner cannot sign automatically: there is no Apple
// account to sign in with, only the distribution certificate and profiles held
// as secrets. `release-ios.yml` runs this after decoding them. It rewrites the
// Release configuration of every signed target in `Runner.xcodeproj` — the
// phone app, the Apple Watch app, the extensions the phone embeds (Live Activity
// widget and share extension) and the watch's complication — to manual signing
// against the profile whose bundle id matches, and leaves every other
// configuration alone. A target added to the project needs an App Store profile
// of its own before the next release, and the guard beside this file is what
// says so on the PR rather than on the Mac runner.
//
// The mapping is derived, not configured. A profile names its own bundle id and
// team, so the profiles are the whole input: a signed target with no profile, a
// profile no target uses, two teams, or a development / ad hoc profile fails
// here naming the bundle id, instead of failing inside xcodebuild as a
// provisioning error that names none of them. decisions.md § 1701.
//
// Usage: node scripts/ios_release_signing.mjs <project.pbxproj> <ExportOptions.plist> <profile.mobileprovision>...
// Reading a profile needs macOS (`security`, `plutil`); planning and editing
// the project are pure, and `ios_release_signing.test.mjs` runs them on Linux
// against the committed project.
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { pbxObject } from './check_watch_ios_source.mjs';

/**
 * @typedef {{ uuid: string, name: string, teamId: string, bundleId: string }} Profile
 * @typedef {{ name: string, bundleId: string, releaseConfigId: string }} SignedTarget
 * @typedef {{ target: SignedTarget, profile: Profile }} Assignment
 * @typedef {{ teamId: string, assignments: Assignment[] }} SigningPlan
 */

/**
 * Product types that are code-signed with a profile of their own when they
 * ship: an app, a watch app, or an extension such as a complication. A target
 * of one of these types with no profile cannot be exported.
 */
export const SIGNED_PRODUCT_TYPES = [
	'com.apple.product-type.application',
	'com.apple.product-type.application.watchapp2',
	'com.apple.product-type.app-extension',
	'com.apple.product-type.extensionkit-extension',
	'com.apple.product-type.watchkit2-extension',
];

/** The identity an Apple Distribution certificate's common name starts with. */
export const DISTRIBUTION_IDENTITY = 'Apple Distribution';

/** Every setting this script owns, including its per-SDK variants. */
export const SIGNING_KEYS = [
	'CODE_SIGN_STYLE',
	'DEVELOPMENT_TEAM',
	'PROVISIONING_PROFILE_SPECIFIER',
	'PROVISIONING_PROFILE',
	'CODE_SIGN_IDENTITY',
];

/**
 * A profile's identity, from the fields a decoded `.mobileprovision` carries.
 * Only an App Store profile is accepted: one listing devices is development or
 * ad hoc, one provisioning all devices is enterprise, and `get-task-allow` is a
 * debugger entitlement App Store Connect refuses.
 * @param {{ path: string, uuid: string | null, name: string | null, teamId: string | null,
 *   applicationIdentifier: string | null, listsDevices: boolean, provisionsAllDevices: boolean,
 *   getTaskAllow: boolean }} f
 * @returns {Profile}
 */
export function profileFromFields(f) {
	const where = `${f.path}${f.name ? ` ("${f.name}")` : ''}`;
	if (!f.uuid || !f.teamId || !f.applicationIdentifier) {
		throw new Error(`${where} is not a readable provisioning profile: UUID, TeamIdentifier or application-identifier is missing.`);
	}
	if (f.listsDevices || f.provisionsAllDevices || f.getTaskAllow) {
		throw new Error(
			`${where} is not an App Store profile (it lists devices, provisions all devices, or allows a debugger). ` +
				'Create an "App Store Connect" distribution profile for this bundle id.',
		);
	}
	const prefix = `${f.teamId}.`;
	if (!f.applicationIdentifier.startsWith(prefix)) {
		throw new Error(`${where} names application-identifier ${f.applicationIdentifier}, which is not under its own team ${f.teamId}.`);
	}
	const bundleId = f.applicationIdentifier.slice(prefix.length);
	if (bundleId.includes('*')) {
		throw new Error(`${where} is a wildcard profile (${bundleId}); HealthKit, push and App Groups need an explicit App ID.`);
	}
	return { uuid: f.uuid, name: f.name ?? f.uuid, teamId: f.teamId, bundleId };
}

/**
 * @param {string} block
 * @param {RegExp} re
 */
function capture(block, re) {
	const m = re.exec(block);
	return m === null ? null : m[1].trim().replace(/^"(.*)"$/, '$1');
}

/**
 * Every signed target in a pbxproj, with its Release configuration's object id
 * and bundle id. An object id is any unquoted token: Xcode writes 24 hex
 * characters, but a hand-added target is often shorter, and Xcode reads both.
 * @param {string} src
 * @returns {SignedTarget[]}
 */
export function signedTargets(src) {
	const from = src.indexOf('/* Begin PBXNativeTarget section */');
	const to = src.indexOf('/* End PBXNativeTarget section */');
	if (from === -1 || to === -1) throw new Error('The project has no PBXNativeTarget section.');
	/** @type {SignedTarget[]} */
	const out = [];
	for (const block of src.slice(from, to).split('\n\t\t};')) {
		const productType = capture(block, /\n\t\t\tproductType = ([^;]+);/);
		if (productType === null || !SIGNED_PRODUCT_TYPES.includes(productType)) continue;
		const name = capture(block, /\n\t\t\tname = ([^;]+);/) ?? '(unnamed)';
		const listId = capture(block, /\n\t\t\tbuildConfigurationList = ([A-Za-z0-9_]+)/);
		const list = listId === null ? null : pbxObject(src, listId);
		if (list === null) throw new Error(`Target ${name} has no build configuration list.`);
		/** @type {string | null} */
		let releaseConfigId = null;
		for (const m of list.matchAll(/\n\t{4}([A-Za-z0-9_]+) \/\* [^*]+ \*\/,/g)) {
			const config = pbxObject(src, m[1]);
			if (config !== null && capture(config, /\n\t\t\tname = ([^;]+);/) === 'Release') releaseConfigId = m[1];
		}
		if (releaseConfigId === null) throw new Error(`Target ${name} has no Release configuration.`);
		const bundleId = readSetting(releaseSettings(src, releaseConfigId).body, 'PRODUCT_BUNDLE_IDENTIFIER');
		if (bundleId === null || bundleId.includes('$(')) {
			throw new Error(`Target ${name}'s Release configuration sets no literal PRODUCT_BUNDLE_IDENTIFIER, so no profile can be matched to it.`);
		}
		out.push({ name, bundleId, releaseConfigId });
	}
	return out;
}

/**
 * The span of one configuration's `buildSettings = { … }` body: from the line
 * after the opening brace to the start of the `\t\t\t};` that closes it.
 * @param {string} src
 * @param {string} configId
 */
function releaseSettings(src, configId) {
	const at = src.indexOf(`\n\t\t${configId} `);
	const open = at === -1 ? -1 : src.indexOf('\n\t\t\tbuildSettings = {\n', at);
	const start = open === -1 ? -1 : open + '\n\t\t\tbuildSettings = {\n'.length;
	const end = start === -1 ? -1 : src.indexOf('\n\t\t\t};', start - 1);
	const objectEnd = at === -1 ? -1 : src.indexOf('\n\t\t};', at);
	if (start === -1 || end === -1 || end > objectEnd) {
		throw new Error(`Configuration ${configId} has no buildSettings block this script can edit.`);
	}
	return { start, end: end + 1, body: src.slice(start, end + 1) };
}

/**
 * One setting's unquoted value in a buildSettings body. The key is matched
 * literally, so a per-SDK key such as `CODE_SIGN_IDENTITY[sdk=iphoneos*]` reads
 * as itself.
 * @param {string} body
 * @param {string} key
 */
export function readSetting(body, key) {
	for (const line of body.split('\n')) {
		const m = /^\t{4}(?:"([^"]+)"|([^\s"=]+)) = (.*);$/.exec(line);
		if (m !== null && (m[1] ?? m[2]) === key) return m[3].replace(/^"(.*)"$/, '$1');
	}
	return null;
}

/**
 * The signing settings a Release configuration is rewritten to. The per-SDK
 * identities are set as well as the plain one because the project level
 * declares `CODE_SIGN_IDENTITY[sdk=iphoneos*]`, and a conditional setting is
 * only overridden by a setting with the same condition.
 * @param {string} teamId
 * @param {string} profileUuid
 * @returns {[string, string][]}
 */
export function releaseSigningSettings(teamId, profileUuid) {
	return [
		['CODE_SIGN_IDENTITY', DISTRIBUTION_IDENTITY],
		['CODE_SIGN_IDENTITY[sdk=iphoneos*]', DISTRIBUTION_IDENTITY],
		['CODE_SIGN_IDENTITY[sdk=watchos*]', DISTRIBUTION_IDENTITY],
		['CODE_SIGN_STYLE', 'Manual'],
		['DEVELOPMENT_TEAM', teamId],
		['PROVISIONING_PROFILE_SPECIFIER', profileUuid],
	];
}

/** @param {string} s */
function plistAtom(s) {
	return /^[A-Za-z0-9_./]+$/.test(s) ? s : `"${s.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}

/**
 * Match every signed target to exactly one profile, in both directions.
 * @param {string} src
 * @param {Profile[]} profiles
 * @returns {SigningPlan}
 */
export function planSigning(src, profiles) {
	const targets = signedTargets(src);
	if (targets.length === 0) throw new Error('The project has no signed target, so there is nothing to archive.');
	const teams = [...new Set(profiles.map((p) => p.teamId))];
	if (teams.length > 1) throw new Error(`The profiles belong to ${teams.length} teams (${teams.join(', ')}); one archive is signed by one team.`);
	/** @type {Assignment[]} */
	const assignments = [];
	for (const target of targets) {
		const matches = profiles.filter((p) => p.bundleId === target.bundleId);
		if (matches.length === 0) {
			throw new Error(
				`No App Store provisioning profile for ${target.bundleId} (target ${target.name}). Every target the archive embeds is signed ` +
					'with its own profile: register its App ID and make the profile (docs/ops/apple_provisioning.md steps 4 and 15), pass it to ' +
					'this script from release-ios.yml under a secret of its own, and give ios_release_signing.test.mjs a profile for it.',
			);
		}
		if (matches.length > 1) throw new Error(`${matches.length} profiles are for ${target.bundleId}; pass one.`);
		assignments.push({ target, profile: matches[0] });
	}
	for (const p of profiles) {
		if (!targets.some((t) => t.bundleId === p.bundleId)) {
			throw new Error(`Profile "${p.name}" is for ${p.bundleId}, which no signed target in the project builds.`);
		}
	}
	return { teamId: teams[0], assignments };
}

/**
 * Rewrite each assigned Release configuration's signing settings, removing
 * every existing variant of the keys first. Nothing outside those bodies moves.
 * @param {string} src
 * @param {SigningPlan} plan
 */
export function applySigning(src, plan) {
	let out = src;
	for (const { target, profile } of plan.assignments) {
		const { start, end, body } = releaseSettings(out, target.releaseConfigId);
		const kept = body.split('\n').filter((line) => {
			const m = /^\t{4}"?([A-Z_]+)(?:\[[^\]]*\])?"? = /.exec(line);
			return m === null || !SIGNING_KEYS.includes(m[1]);
		});
		const added = releaseSigningSettings(plan.teamId, profile.uuid).map(
			([k, v]) => `\t\t\t\t${plistAtom(k)} = ${plistAtom(v)};`,
		);
		out = out.slice(0, start) + [...added, ...kept].join('\n') + out.slice(end);
	}
	return out;
}

/** @param {string} s */
function xmlEscape(s) {
	return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

/**
 * The ExportOptions.plist `xcodebuild -exportArchive` reads: an App Store
 * Connect export, signed manually with the same profiles the archive used.
 * @param {SigningPlan} plan
 */
export function exportOptionsPlist(plan) {
	const profiles = plan.assignments
		.map(({ target, profile }) => `\t\t<key>${xmlEscape(target.bundleId)}</key>\n\t\t<string>${xmlEscape(profile.uuid)}</string>`)
		.join('\n');
	return [
		'<?xml version="1.0" encoding="UTF-8"?>',
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
		'<plist version="1.0">',
		'<dict>',
		'\t<key>method</key>\n\t<string>app-store-connect</string>',
		'\t<key>signingStyle</key>\n\t<string>manual</string>',
		`\t<key>teamID</key>\n\t<string>${xmlEscape(plan.teamId)}</string>`,
		`\t<key>signingCertificate</key>\n\t<string>${DISTRIBUTION_IDENTITY}</string>`,
		`\t<key>provisioningProfiles</key>\n\t<dict>\n${profiles}\n\t</dict>`,
		'\t<key>uploadSymbols</key>\n\t<true/>',
		'\t<key>manageAppVersionAndBuildNumber</key>\n\t<false/>',
		'</dict>',
		'</plist>',
		'',
	].join('\n');
}

/**
 * Decode a `.mobileprovision` with the tools macOS ships.
 * @param {string} path
 * @returns {Profile}
 */
function readProfile(path) {
	const plist = join(mkdtempSync(join(tmpdir(), 'profile-')), 'profile.plist');
	writeFileSync(plist, execFileSync('security', ['cms', '-D', '-i', path]));
	/** @param {string} key @param {string} fmt */
	const extract = (key, fmt) => {
		try {
			return execFileSync('plutil', ['-extract', key, fmt, '-o', '-', plist], {
				encoding: 'utf8',
				stdio: ['ignore', 'pipe', 'ignore'],
			}).trim();
		} catch {
			return null;
		}
	};
	return profileFromFields({
		path,
		uuid: extract('UUID', 'raw'),
		name: extract('Name', 'raw'),
		teamId: extract('TeamIdentifier.0', 'raw'),
		applicationIdentifier: extract('Entitlements.application-identifier', 'raw'),
		listsDevices: extract('ProvisionedDevices', 'xml1') !== null,
		provisionsAllDevices: extract('ProvisionsAllDevices', 'raw') === 'true',
		getTaskAllow: extract('Entitlements.get-task-allow', 'raw') === 'true',
	});
}

/**
 * Xcode 16 moved the directory it reads profiles from; installing into both
 * keeps the step working on either side of that move.
 * @param {string} path
 * @param {Profile} profile
 */
function installProfile(path, profile) {
	for (const dir of [
		join(homedir(), 'Library', 'MobileDevice', 'Provisioning Profiles'),
		join(homedir(), 'Library', 'Developer', 'Xcode', 'UserData', 'Provisioning Profiles'),
	]) {
		mkdirSync(dir, { recursive: true });
		copyFileSync(path, join(dir, `${profile.uuid}.mobileprovision`));
	}
}

/** @param {string[]} argv */
function main(argv) {
	const [pbxproj, exportOptions, ...profilePaths] = argv;
	if (!pbxproj || !exportOptions || profilePaths.length === 0) {
		console.log('::error::Usage: node scripts/ios_release_signing.mjs <project.pbxproj> <ExportOptions.plist> <profile.mobileprovision>...');
		return 1;
	}
	try {
		const profiles = profilePaths.map(readProfile);
		const src = readFileSync(pbxproj, 'utf8');
		const plan = planSigning(src, profiles);
		writeFileSync(pbxproj, applySigning(src, plan));
		writeFileSync(exportOptions, exportOptionsPlist(plan));
		profilePaths.forEach((p, i) => installProfile(p, profiles[i]));
		for (const { target, profile } of plan.assignments) {
			console.log(`${target.name} (${target.bundleId}) -> "${profile.name}" ${profile.uuid}, team ${plan.teamId}`);
		}
		return 0;
	} catch (e) {
		console.log(`::error::${e instanceof Error ? e.message : String(e)}`);
		return 1;
	}
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main(process.argv.slice(2)));

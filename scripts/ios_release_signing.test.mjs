import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
	applySigning,
	exportOptionsPlist,
	planSigning,
	profileFromFields,
	readSetting,
	signedTargets,
} from './ios_release_signing.mjs';

/**
 * Every case runs against the committed `Runner.xcodeproj`, because the only
 * question worth asking of this script is whether it still edits THAT project
 * correctly. A fixture project would keep passing after Xcode restructured the
 * real one, and the first sign of it would be a failed release on a Mac runner.
 */

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const PBXPROJ = readFileSync(resolve(root, 'apps/mobile_ios/ios/Runner.xcodeproj/project.pbxproj'), 'utf8');

const TEAM = 'ABCDE12345';
const PHONE = profileFromFields({
	path: 'phone.mobileprovision',
	uuid: '11111111-2222-3333-4444-555555555555',
	name: 'Threkir App Store',
	teamId: TEAM,
	applicationIdentifier: `${TEAM}.com.threkir.app`,
	listsDevices: false,
	provisionsAllDevices: false,
	getTaskAllow: false,
});
const WATCH = profileFromFields({
	path: 'watch.mobileprovision',
	uuid: '66666666-7777-8888-9999-000000000000',
	name: 'Threkir Watch App Store',
	teamId: TEAM,
	applicationIdentifier: `${TEAM}.com.threkir.app.watchapp`,
	listsDevices: false,
	provisionsAllDevices: false,
	getTaskAllow: false,
});

/**
 * Where one configuration's buildSettings body sits: from the line after its
 * opening brace to the start of the line that closes it. Found by the
 * configuration's object id, because the watch app's Release and Profile
 * bodies are identical text and a search by content would find the wrong one.
 * @param {string} src
 * @param {string} configId
 */
function bodySpan(src, configId) {
	const at = src.indexOf(`\n\t\t${configId} `);
	assert.notEqual(at, -1, `configuration ${configId} is in the project`);
	const open = src.indexOf('buildSettings = {\n', at) + 'buildSettings = {\n'.length;
	return { open, close: src.indexOf('\n\t\t\t};', open - 1) + 1 };
}

/** @param {string} src @param {string} configId */
const settingsOf = (src, configId) => {
	const { open, close } = bodySpan(src, configId);
	return src.slice(open, close);
};

/** @param {string} src @param {string} configId */
const withoutBody = (src, configId) => {
	const { open, close } = bodySpan(src, configId);
	return src.slice(0, open) + src.slice(close);
};

test('the committed project signs exactly the phone app and the watch app it embeds', () => {
	const targets = signedTargets(PBXPROJ).map((t) => `${t.name} ${t.bundleId}`);
	assert.deepEqual(targets.sort(), ['Runner com.threkir.app', 'WatchApp com.threkir.app.watchapp']);
});

test('each Release configuration is switched to manual App Store signing with its own profile', () => {
	const plan = planSigning(PBXPROJ, [PHONE, WATCH]);
	const out = applySigning(PBXPROJ, plan);
	for (const { target, profile } of plan.assignments) {
		const body = settingsOf(out, target.releaseConfigId);
		assert.equal(readSetting(body, 'CODE_SIGN_STYLE'), 'Manual', target.name);
		assert.equal(readSetting(body, 'DEVELOPMENT_TEAM'), TEAM, target.name);
		assert.equal(readSetting(body, 'PROVISIONING_PROFILE_SPECIFIER'), profile.uuid, target.name);
		for (const key of ['CODE_SIGN_IDENTITY', 'CODE_SIGN_IDENTITY[sdk=iphoneos*]', 'CODE_SIGN_IDENTITY[sdk=watchos*]']) {
			assert.equal(readSetting(body, key), 'Apple Distribution', `${target.name} ${key}`);
		}
		assert.doesNotMatch(body, /CODE_SIGN_STYLE = Automatic/, `${target.name} keeps no automatic-signing line`);
		assert.equal(readSetting(body, 'PRODUCT_BUNDLE_IDENTIFIER'), target.bundleId, 'the rest of the body survives');
	}
});

test('nothing outside the two Release bodies changes, so Debug and Profile still sign automatically', () => {
	const plan = planSigning(PBXPROJ, [PHONE, WATCH]);
	const out = applySigning(PBXPROJ, plan);
	let strippedIn = PBXPROJ;
	let strippedOut = out;
	for (const { target } of plan.assignments) {
		strippedIn = withoutBody(strippedIn, target.releaseConfigId);
		strippedOut = withoutBody(strippedOut, target.releaseConfigId);
	}
	assert.equal(strippedOut, strippedIn);
	assert.equal((out.match(/CODE_SIGN_STYLE = Automatic;/g) ?? []).length, (PBXPROJ.match(/CODE_SIGN_STYLE = Automatic;/g) ?? []).length - 1);
});

test('applying twice is the same as applying once', () => {
	const plan = planSigning(PBXPROJ, [PHONE, WATCH]);
	const once = applySigning(PBXPROJ, plan);
	assert.equal(applySigning(once, planSigning(once, [PHONE, WATCH])), once);
});

test('a target whose object ids are not 24 hex characters is still read', () => {
	// The watch complication target was added by hand with 12-character ids,
	// and a reader that assumed Xcode's generated 24 failed with "has no build
	// configuration list". The ids below must not already name an object, or
	// the rename would merge two objects into one.
	const [shortList, shortRelease] = ['5407E0000001', '5407E0000002'];
	for (const id of [shortList, shortRelease]) assert.equal(PBXPROJ.includes(id), false, `${id} is unused in the project`);
	const watch = signedTargets(PBXPROJ).find((t) => t.name === 'WatchApp');
	assert.ok(watch);
	const listId = /buildConfigurationList = (\w+) \/\* Build configuration list for PBXNativeTarget "WatchApp"/.exec(PBXPROJ);
	assert.ok(listId);
	const shortened = PBXPROJ.split(listId[1]).join(shortList).split(watch.releaseConfigId).join(shortRelease);
	const again = signedTargets(shortened).find((t) => t.name === 'WatchApp');
	assert.deepEqual(again, { name: 'WatchApp', bundleId: 'com.threkir.app.watchapp', releaseConfigId: shortRelease });
	const out = applySigning(shortened, { teamId: TEAM, assignments: [{ target: again, profile: WATCH }] });
	assert.equal(readSetting(settingsOf(out, shortRelease), 'PROVISIONING_PROFILE_SPECIFIER'), WATCH.uuid);
});

test('a missing watch profile fails naming the watch bundle id, not inside xcodebuild', () => {
	assert.throws(() => planSigning(PBXPROJ, [PHONE]), /com\.threkir\.app\.watchapp \(target WatchApp\)/);
});

test('a profile for a bundle no target builds fails', () => {
	const stray = { ...WATCH, bundleId: 'com.threkir.app.widgets', name: 'Stray' };
	assert.throws(() => planSigning(PBXPROJ, [PHONE, WATCH, stray]), /"Stray" is for com\.threkir\.app\.widgets/);
});

test('profiles from two teams fail', () => {
	assert.throws(() => planSigning(PBXPROJ, [PHONE, { ...WATCH, teamId: 'ZZZZZ99999' }]), /2 teams/);
});

test('only an explicit App Store profile is accepted', () => {
	const base = {
		path: 'p.mobileprovision',
		uuid: 'u',
		name: 'n',
		teamId: TEAM,
		applicationIdentifier: `${TEAM}.com.threkir.app`,
		listsDevices: false,
		provisionsAllDevices: false,
		getTaskAllow: false,
	};
	assert.throws(() => profileFromFields({ ...base, listsDevices: true }), /not an App Store profile/);
	assert.throws(() => profileFromFields({ ...base, provisionsAllDevices: true }), /not an App Store profile/);
	assert.throws(() => profileFromFields({ ...base, getTaskAllow: true }), /not an App Store profile/);
	assert.throws(() => profileFromFields({ ...base, applicationIdentifier: `${TEAM}.*` }), /wildcard/);
	assert.throws(() => profileFromFields({ ...base, applicationIdentifier: 'OTHER12345.com.threkir.app' }), /not under its own team/);
	assert.throws(() => profileFromFields({ ...base, uuid: null }), /not a readable provisioning profile/);
	assert.equal(profileFromFields(base).bundleId, 'com.threkir.app');
});

test('the export options name every signed bundle with its profile', () => {
	const xml = exportOptionsPlist(planSigning(PBXPROJ, [PHONE, WATCH]));
	assert.match(xml, /<key>method<\/key>\n\t<string>app-store-connect<\/string>/);
	assert.match(xml, /<key>signingStyle<\/key>\n\t<string>manual<\/string>/);
	assert.match(xml, new RegExp(`<key>teamID</key>\\n\\t<string>${TEAM}</string>`));
	assert.match(xml, new RegExp(`<key>com\\.threkir\\.app</key>\\n\\t\\t<string>${PHONE.uuid}</string>`));
	assert.match(xml, new RegExp(`<key>com\\.threkir\\.app\\.watchapp</key>\\n\\t\\t<string>${WATCH.uuid}</string>`));
	assert.equal((xml.match(/<dict>/g) ?? []).length, (xml.match(/<\/dict>/g) ?? []).length);
});

test('readSetting reads a quoted per-SDK key literally', () => {
	const body = '\t\t\t\t"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "iPhone Developer";\n\t\t\t\tCODE_SIGN_IDENTITY = X;\n';
	assert.equal(readSetting(body, 'CODE_SIGN_IDENTITY[sdk=iphoneos*]'), 'iPhone Developer');
	assert.equal(readSetting(body, 'CODE_SIGN_IDENTITY'), 'X');
});

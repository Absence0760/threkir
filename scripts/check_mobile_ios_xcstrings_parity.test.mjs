// Unit tests for apps/mobile_ios/scripts/check_xcstrings_parity.sh — the
// iPhone's consent-prompt catalog guard, a thin wrapper over the engine the
// watch shares, scripts/xcstrings_parity.py.
//
// The failure it exists to catch is silent on the platform: a usage
// description with no `InfoPlist.xcstrings` entry, or a catalog the Runner
// target never copies, renders the Info.plist English on every iPhone, and no
// build, test or crash report mentions it. That was the app's state for all
// eleven prompts in all seven locales until #964. So it is measured the way
// its watch sibling is: by mutating a copy of the real tree and asserting the
// guard refuses, with the unmutated copy as the positive control.
//
// The engine's generic claims (plural categories, the ja exemption, an empty
// catalog) are exercised by scripts/check_xcstrings_parity.test.mjs against
// the watch tree, which is the one with a UI catalog to exercise them on. The
// cases here are the ones that depend on the PHONE's files being wired right.
//
// Run: node --test scripts/check_mobile_ios_xcstrings_parity.test.mjs
// CI:  the `ios-native-declarations` job in .github/workflows/ci.yml.

import { spawnSync } from 'node:child_process';
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const MOBILE_IOS = join(REPO_ROOT, 'apps', 'mobile_ios');
const PLIST_CATALOG = join('ios', 'Runner', 'InfoPlist.xcstrings');
const PLIST = join('ios', 'Runner', 'Info.plist');
const PBXPROJ = join('ios', 'Runner.xcodeproj', 'project.pbxproj');
const SCRIPT = join('scripts', 'check_xcstrings_parity.sh');
const ENGINE = join('scripts', 'xcstrings_parity.py');

/** Stage the guard's inputs in a throwaway repo-shaped tree; returns its `apps/mobile_ios`. */
function stage() {
	const root = mkdtempSync(join(tmpdir(), 'mobile-xcstrings-'));
	const dir = join(root, 'apps', 'mobile_ios');
	for (const rel of [PLIST_CATALOG, PLIST, PBXPROJ, SCRIPT]) {
		mkdirSync(join(dir, dirname(rel)), { recursive: true });
		cpSync(join(MOBILE_IOS, rel), join(dir, rel));
	}
	mkdirSync(join(root, 'scripts'), { recursive: true });
	cpSync(join(REPO_ROOT, ENGINE), join(root, ENGINE));
	return dir;
}

/**
 * Stage, mutate, run, clean up.
 * @param {(dir: string) => void} mutate
 */
function runMutated(mutate) {
	const dir = stage();
	try {
		mutate(dir);
		const r = spawnSync('bash', [join(dir, SCRIPT)], { encoding: 'utf8' });
		return { status: r.status, out: `${r.stdout}${r.stderr}` };
	} finally {
		rmSync(join(dir, '..', '..'), { recursive: true, force: true });
	}
}

/** @param {string} dir */
const readPlistCatalog = (dir) => JSON.parse(readFileSync(join(dir, PLIST_CATALOG), 'utf8'));
/** @param {string} dir @param {unknown} cat */
const writePlistCatalog = (dir, cat) =>
	writeFileSync(join(dir, PLIST_CATALOG), JSON.stringify(cat, null, 2));
/** @param {string} dir @param {string} rel @param {(src: string) => string} edit */
function editFile(dir, rel, edit) {
	const p = join(dir, rel);
	const src = readFileSync(p, 'utf8');
	const next = edit(src);
	assert.notEqual(next, src, `the ${rel} mutation matched nothing`);
	writeFileSync(p, next);
}

// Derived from Info.plist with the test's own regex, never restated as a
// count: a number here is a second place a new permission has to be added.
const PLIST_USAGE_KEYS = [
	...readFileSync(join(MOBILE_IOS, PLIST), 'utf8').matchAll(/<key>(NS\w*UsageDescription)<\/key>/g),
].map((m) => m[1]);

const ABSENT_USAGE_KEY = 'NSThrekirNeverDeclaredUsageDescription';

test('the shipped iPhone consent catalog, Info.plist, knownRegions and Runner target agree', () => {
	const { status, out } = runMutated(() => {});
	assert.equal(status, 0, out);
	assert.ok(PLIST_USAGE_KEYS.length > 0, 'no NS*UsageDescription keys parsed out of Info.plist');
	assert.match(out, /^OK: \d+ string\(s\) across 1 catalog\(s\)/, out);
	assert.match(
		out,
		new RegExp(`\\b${PLIST_USAGE_KEYS.length} NS\\*UsageDescription key\\(s\\) localized`),
		out,
	);
	assert.match(out, /bundled by Runner/, out);
});

test('the key the absence tests mutate with is declared nowhere', () => {
	assert.ok(!readFileSync(join(MOBILE_IOS, PLIST), 'utf8').includes(ABSENT_USAGE_KEY));
	assert.ok(
		!(ABSENT_USAGE_KEY in JSON.parse(readFileSync(join(MOBILE_IOS, PLIST_CATALOG), 'utf8')).strings),
	);
});

test('a permission added to Info.plist and not to the catalog is refused', () => {
	// The regression the guard exists for: the next capability adds a purpose
	// string and nothing asks for its six translations.
	const { status, out } = runMutated((dir) =>
		editFile(dir, PLIST, (src) =>
			src.replace(
				'<key>NSCameraUsageDescription</key>',
				`<key>${ABSENT_USAGE_KEY}</key>\n\t<string>Threkir needs this.</string>\n\t<key>NSCameraUsageDescription</key>`,
			),
		),
	);
	assert.equal(status, 1, out);
	assert.match(out, new RegExp(`Info\\.plist declares ${ABSENT_USAGE_KEY} with no catalog entry`));
	assert.match(out, /renders English on every iPhone/);
});

test('a catalog entry for a permission Info.plist no longer declares is refused', () => {
	const { status, out } = runMutated((dir) =>
		editFile(dir, PLIST, (src) =>
			src.replace(/\t<key>NSCameraUsageDescription<\/key>\n\t<string>[^<]*<\/string>\n/, ''),
		),
	);
	assert.equal(status, 1, out);
	assert.match(out, /\[NSCameraUsageDescription\]: no such NS\*UsageDescription key in Info\.plist/);
});

test('a consent prompt that never translated a shipped locale is refused', () => {
	const { status, out } = runMutated((dir) => {
		const cat = readPlistCatalog(dir);
		delete cat.strings.NSHealthShareUsageDescription.localizations['pt-PT'];
		writePlistCatalog(dir, cat);
	});
	assert.equal(status, 1, out);
	assert.match(out, /\[NSHealthShareUsageDescription\] pt-PT: missing translation/);
});

test('a consent prompt with no English localization is refused', () => {
	// The key is a plist key name, so an implicit source would ship the
	// identifier itself as the prompt.
	const { status, out } = runMutated((dir) => {
		const cat = readPlistCatalog(dir);
		delete cat.strings.NSLocationWhenInUseUsageDescription.localizations.en;
		writePlistCatalog(dir, cat);
	});
	assert.equal(status, 1, out);
	assert.match(out, /no source-language localization/);
});

test('a catalog with no explicit sourceLanguage is refused', () => {
	const { status, out } = runMutated((dir) => {
		const cat = readPlistCatalog(dir);
		delete cat.sourceLanguage;
		writePlistCatalog(dir, cat);
	});
	assert.equal(status, 1, out);
	assert.match(out, /declares no sourceLanguage/);
});

test('English that has drifted from the Info.plist fallback is refused', () => {
	const { status, out } = runMutated((dir) => {
		const cat = readPlistCatalog(dir);
		cat.strings.NSHealthUpdateUsageDescription.localizations.en.stringUnit.value =
			'Threkir would like to write to Health.';
		writePlistCatalog(dir, cat);
	});
	assert.equal(status, 1, out);
	assert.match(out, /\[NSHealthUpdateUsageDescription\]: en value differs/);
});

test('a plist string carrying an XML entity is compared decoded', () => {
	// Info.plist is XML: `&amp;` in the plist is `&` on screen and in the
	// catalog. Comparing the raw text would refuse a correct pair.
	const { status, out } = runMutated((dir) => {
		editFile(dir, PLIST, (src) =>
			src.replace('lets you attach photos', 'lets you attach photos &amp; videos'),
		);
		const cat = readPlistCatalog(dir);
		const unit = cat.strings.NSPhotoLibraryUsageDescription.localizations.en.stringUnit;
		unit.value = unit.value.replace('lets you attach photos', 'lets you attach photos & videos');
		writePlistCatalog(dir, cat);
	});
	assert.equal(status, 0, out);
});

test('a locale missing from CFBundleLocalizations is refused', () => {
	const { status, out } = runMutated((dir) =>
		editFile(dir, PLIST, (src) => src.replace('<string>pt-PT</string>', '')),
	);
	assert.equal(status, 1, out);
	assert.match(out, /CFBundleLocalizations/);
});

test('a locale missing from knownRegions is refused', () => {
	const { status, out } = runMutated((dir) =>
		editFile(dir, PBXPROJ, (src) => src.replace(/^\s*"?pt-PT"?,?\s*$\n/m, '')),
	);
	assert.equal(status, 1, out);
	assert.match(out, /knownRegions/);
});

/**
 * The phone's and the watch's InfoPlist.xcstrings references in Runner.xcodeproj
 * (which builds both apps), told apart by which group lists them, and the
 * phone's build file. Derived, so an Xcode re-save that renumbers them is fine.
 * @param {string} src
 */
function catalogIds(src) {
	const refs = [
		...src.matchAll(/^\t\t(\w{24}) \/\* InfoPlist\.xcstrings \*\/ = \{isa = PBXFileReference;/gm),
	].map((m) => m[1]);
	assert.equal(refs.length, 2, 'expected one phone and one watch InfoPlist.xcstrings reference');
	const runnerGroup = src.match(/\/\* Runner \*\/ = \{\n\t\t\tisa = PBXGroup;[\s\S]*?\n\t\t\};/);
	assert.ok(runnerGroup, 'no Runner group');
	const phoneRef = refs.find((r) => runnerGroup[0].includes(r));
	const watchRef = refs.find((r) => r !== phoneRef);
	assert.ok(phoneRef && watchRef, 'the Runner group lists neither or both references');
	const build = src.match(
		new RegExp(
			`^\\t\\t(\\w{24}) /\\* InfoPlist\\.xcstrings in Resources \\*/ = \\{isa = PBXBuildFile; fileRef = ${phoneRef}\\b`,
			'm',
		),
	);
	assert.ok(build, 'no build file for the phone catalog');
	return { phoneRef, watchRef, phoneBuild: build[1] };
}

test('a catalog dropped from the Runner Resources phase is refused', () => {
	// On disk, in the group, and never copied into the .app: every prompt
	// reads English and every other claim passes.
	const { status, out } = runMutated((dir) =>
		editFile(dir, PBXPROJ, (src) => {
			const { phoneBuild } = catalogIds(src);
			return src.replace(
				new RegExp(`^\\t\\t\\t\\t${phoneBuild} /\\* InfoPlist\\.xcstrings in Resources \\*/,\\n`, 'm'),
				'',
			);
		}),
	);
	assert.equal(status, 1, out);
	assert.match(out, /InfoPlist\.xcstrings: not in the Runner target's Resources phase/);
});

test("the watch app's catalog in the same project does not satisfy the Runner target", () => {
	// Runner.xcodeproj also builds the watch app, whose own InfoPlist.xcstrings
	// is a Resources member of the WatchApp target. Pointing Runner's build
	// file at that reference must not read as the phone being localized.
	const { status, out } = runMutated((dir) =>
		editFile(dir, PBXPROJ, (src) => {
			const { phoneRef, watchRef, phoneBuild } = catalogIds(src);
			return src.replace(
				new RegExp(
					`(${phoneBuild} /\\* InfoPlist\\.xcstrings in Resources \\*/ = \\{isa = PBXBuildFile; fileRef = )${phoneRef}`,
				),
				`$1${watchRef}`,
			);
		}),
	);
	assert.equal(status, 1, out);
	assert.match(out, /not in the Runner target's Resources phase as Runner\/InfoPlist\.xcstrings/);
});

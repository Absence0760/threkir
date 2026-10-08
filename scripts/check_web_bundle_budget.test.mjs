import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import {
	ASSET_EXEMPTIONS,
	CATALOGUE_SOURCE,
	CORE_PART,
	MAX_AREA_CATALOGUE_KB,
	MAX_ASSET_KB,
	MAX_CODE_KB,
	MAX_CORE_CATALOGUE_KB,
	MAX_LARGEST_CHUNK_KB,
	catalogueChunks,
	catalogueSentinel,
	checkBudgets,
	collectEmitted,
	gzipKb,
	isCodeFile,
	localeTags,
	renderSummary,
} from './check_web_bundle_budget.mjs';

/// The ceiling this guard replaces: one number over every emitted file, which
/// is what let a language move it and a dep hide under it. The fixtures below
/// are scored against it as well as against the new rule, because "the new rule
/// is better" is a claim about a disagreement, and a test that only ran the new
/// rule could not show one.
const RETIRED_TOTAL_KB = 2700;
/// The retired walk matched `*.js` and `*.css`, so it is scored over those —
/// which is also the hole the asset ceiling closes: the 3866 KB font this
/// population was written for was invisible to that total as well as to the
/// three ceilings that replaced it.
/** @param {readonly {path: string, kb: number}[]} files */
const retiredTotalPasses = (files) =>
	files.filter((f) => isCodeFile(f.path)).reduce((sum, f) => sum + f.kb, 0) <=
	RETIRED_TOTAL_KB;

/// apps/web as measured on 2026-10-08, after the area split (decisions § 1802):
/// 2065 KB of code in 431 files (largest chunk 277 KB), the English core inside
/// it, and every other catalogue part lazy. Collapsed to a handful of entries
/// whose sizes add up to the real ones — the arithmetic under test is the
/// partition, not the file count — and to two areas per locale, the largest
/// (settings) and a typical one (gym).
const CORE_KB = { de: 24, es: 23, fr: 24, ja: 25, 'pt-BR': 23, 'pt-PT': 23 };
const AREA_KB = { settings: 11, gym: 3 };
const LOCALES = ['de', 'en', 'es', 'fr', 'ja', 'pt-BR', 'pt-PT'];

/// The non-JS/CSS half of the same build: 33 files, 266 KB gzipped, collapsed
/// to the nine that carry all but a kilobyte of it. The font is the whole
/// reason this population exists — it was 3866 KB, 1.8x the code ceiling, and
/// outside every metric until it was measured; subsetting it to the icons the
/// app names (decisions § 780) is what took it to 74 KB and retired the
/// exemption that carried it in the meantime.
const ASSET_KB = [
	{ path: '_app/immutable/assets/material-symbols-subset.CFBkXaJ5.woff2', kb: 74 },
	{ path: 'icon-512.png', kb: 68 },
	{ path: 'og-default.png', kb: 20 },
	{ path: 'icon-192.png', kb: 11 },
	{ path: 'apple-touch-icon.png', kb: 10 },
	{ path: 'learn/couch-to-5k.html', kb: 5 },
	{ path: 'learn.html', kb: 5 },
	{ path: 'learn/category/gear.html', kb: 4 },
	{ path: 'index.html', kb: 2 },
];

/// `tag -> { part -> kb }` for the default fixture: every locale's areas, and a
/// core for every locale but English, whose core is inside the store chunk.
/** @param {readonly string[]} tags */
function partsFor(tags) {
	/** @type {Record<string, number>} */
	const out = {};
	for (const tag of tags) {
		if (tag !== 'en') out[`${tag}/${CORE_PART}`] = CORE_KB[/** @type {keyof typeof CORE_KB} */ (tag)] ?? 24;
		for (const [area, kb] of Object.entries(AREA_KB)) out[`${tag}/${area}`] = kb;
	}
	return out;
}

/**
 * @param {{
 *   extraCatalogues?: Record<string, number>,
 *   extraCode?: {path: string, kb: number}[],
 *   assets?: {path: string, kb: number}[],
 *   extraLocales?: string[],
 * }} [opts]
 */
function fixture({ extraCatalogues = {}, extraCode = [], assets = ASSET_KB, extraLocales = [] } = {}) {
	/** @type {Map<string, string>} */
	const catalogues = new Map();
	const files = [
		{ path: '_app/immutable/chunks/largest.js', kb: 277 },
		// The English core is inside this one: store.svelte.ts imports it
		// statically as the fallback dict, so it is never its own chunk.
		{ path: '_app/immutable/chunks/store.js', kb: 80 },
	];
	// The remaining 1708 KB of code, spread so no single chunk is the largest.
	for (let i = 0; i < 7; i++) files.push({ path: `_app/immutable/nodes/${i}.js`, kb: 244 });
	const locales = [...new Set([...LOCALES, ...extraLocales])].sort();
	for (const [id, kb] of Object.entries({ ...partsFor(locales), ...extraCatalogues })) {
		const path = `_app/immutable/chunks/${id.replace('/', '-')}.js`;
		catalogues.set(id, path);
		files.push({ path, kb });
	}
	files.push(...extraCode, ...assets);
	return { files, catalogues, locales };
}

test('the shipped ceilings pass against the measured build', () => {
	const { errors, summary } = checkBudgets(fixture());
	assert.deepEqual(errors, []);
	assert.equal(summary.codeKb, 2065);
	assert.equal(summary.catalogueKb, 142 + 7 * 14);
	assert.equal(summary.catalogueFiles.length, 6 + 7 * 2);
	assert.equal(summary.largest.kb, 277);
	assert.equal(summary.largestCore.kb, 25);
	assert.equal(summary.largestArea.kb, 11);
	assert.equal(summary.assetFileCount, 9);
	assert.equal(summary.assetKb, 199);
	assert.equal(summary.largestAsset.kb, 74);
});

test('a dozen more languages move no budget, where the retired total ceiling fails', () => {
	const tags = ['it', 'nl', 'ko', 'pl', 'sv', 'da', 'nb', 'fi', 'tr', 'cs', 'el', 'he'];
	const grown = fixture({ extraLocales: tags });

	assert.equal(
		retiredTotalPasses(grown.files),
		false,
		'the retired rule summed catalogues, so languages alone pushed the total past ' +
			'2700 and would have forced another bump',
	);

	const { errors, summary } = checkBudgets(grown);
	assert.deepEqual(errors, [], 'nineteen languages cost a reader exactly what seven did');
	assert.equal(summary.codeKb, 2065, 'the code budget does not know a language was added');
	assert.equal(summary.catalogueFiles.filter((c) => c.part === CORE_PART).length, 18);
});

test('a rogue dep the retired total ceiling had room for trips the code budget', () => {
	const rogue = fixture({
		extraCode: [{ path: '_app/immutable/chunks/rogue-dep.js', kb: 200 }],
	});

	assert.equal(
		retiredTotalPasses(rogue.files),
		true,
		'2065 + 240 KB of catalogue parts + 200 = 2505 sits under 2700 — the catalogues ' +
			'in that total were the cover the dep hid behind',
	);

	const { errors } = checkBudgets(rogue);
	assert.equal(errors.length, 1);
	assert.equal(errors[0].budget, 'code');
	assert.match(errors[0].message, /code is 2265 KB gzipped, over the 2251 KB ceiling by 14 KB/);
	assert.match(
		errors[0].message,
		/a new locale cannot have caused it/,
		'the diagnosis has to point at the population that actually moved',
	);
});

test('an oversized core names its own locale and its own budget', () => {
	const { errors } = checkBudgets(fixture({ extraCatalogues: { 'ja/core': 40 } }));
	assert.equal(errors.length, 1);
	assert.equal(errors[0].budget, 'catalogue');
	assert.match(errors[0].message, /the ja core catalogue is 40 KB/);
	assert.match(errors[0].message, /over the 28 KB per-core ceiling by 12 KB/);
	assert.match(errors[0].message, /adding a language cannot trip it/);
	assert.match(errors[0].message, /keys moved into core/);
});

test('an oversized area names its locale, its area and its own budget', () => {
	const { errors } = checkBudgets(fixture({ extraCatalogues: { 'ja/settings': 20 } }));
	assert.deepEqual(errors.map((e) => e.budget), ['catalogue']);
	assert.match(errors[0].message, /the ja 'settings' area catalogue is 20 KB/);
	assert.match(errors[0].message, /over the 14 KB per-area ceiling by 6 KB/);
	assert.match(errors[0].message, /split along its sub-routes/);
});

test('a catalogue is not measured against the largest-code-chunk ceiling', () => {
	const { errors } = checkBudgets(fixture({ extraCatalogues: { 'ja/settings': 400 } }));
	assert.deepEqual(
		errors.map((e) => e.budget),
		['catalogue'],
		'400 KB is over MAX_LARGEST_CHUNK_KB too, but a catalogue part is already a ' +
			'lazy chunk — one budget owns it, and it is not that one',
	);
});

test('an oversized code chunk trips the largest-chunk budget alone', () => {
	const big = fixture();
	big.files = big.files.map((f) =>
		f.path.endsWith('largest.js') ? { ...f, kb: 380 } : f,
	);
	const { errors } = checkBudgets(big);
	assert.deepEqual(errors.map((e) => e.budget), ['largest-chunk']);
	assert.match(errors[0].message, /380 KB gzipped, over the 350 KB ceiling by 30 KB/);
	assert.match(errors[0].message, /largest\.js/);
});

test('a catalogue the manifest names but the build lacks fails classification', () => {
	const f = fixture();
	f.files = f.files.filter((x) => !x.path.endsWith('/ja-core.js'));
	const { errors } = checkBudgets(f);
	assert.deepEqual(errors.map((e) => e.budget), ['classification']);
	assert.match(errors[0].message, /catalogue ja\/core to _app\/immutable\/chunks\/ja-core\.js/);
	assert.match(errors[0].message, /no ceiling below means anything/);
});

test('a second statically-bundled core is named, not absorbed into code', () => {
	const f = fixture();
	// What a part merging into a shared chunk looks like from here: it leaves
	// the manifest, so its bytes land in the code budget under a message about
	// deps unless the grid is checked.
	f.catalogues.delete('ja/core');
	f.files = f.files.map((x) =>
		x.path.endsWith('/ja-core.js') ? { ...x, path: '_app/immutable/chunks/store.js' } : x,
	);
	const { errors } = checkBudgets(f);
	const classification = errors.filter((e) => e.budget === 'classification');
	assert.equal(classification.length, 1);
	assert.match(classification[0].message, /found 2 — en\/core, ja\/core/);
});

test('an area merged into a shared chunk is named too', () => {
	const f = fixture();
	f.catalogues.delete('ja/gym');
	const { errors } = checkBudgets(f);
	const classification = errors.filter((e) => e.budget === 'classification');
	assert.equal(classification.length, 1);
	assert.match(classification[0].message, /found 2 — en\/core, ja\/gym/);
});

test('the one static part must be a core, not an area', () => {
	const f = fixture({ extraCatalogues: { 'en/core': 21 } });
	f.catalogues.delete('en/gym');
	const { errors } = checkBudgets(f);
	assert.deepEqual(errors.map((e) => e.budget), ['classification']);
	assert.match(errors[0].message, /found 1 — en\/gym/);
});

test('every catalogue going lazy is a classification failure too', () => {
	const f = fixture({ extraCatalogues: { 'en/core': 21 } });
	const { errors } = checkBudgets(f);
	assert.deepEqual(errors.map((e) => e.budget), ['classification']);
	assert.match(errors[0].message, /found 0\./);
});

test('a whole catalogue bundled into code is a leak, named by the chunk carrying it', () => {
	// Every part is still lazy and in the manifest, and 90 KB fits inside the
	// code ceiling's cover, so nothing above can see this. It is what one client
	// page calling `englishBadge` (which imports locales/en.ts) did mid-split.
	const f = fixture();
	const sentinels = new Map([
		['en/gym', '"gym.title":`Gym`'],
		['en/settings', '"settings.title":`Settings`'],
		['de/gym', '"gym.empty":`Noch nichts`'],
	]);
	const leaked = new Set(['"gym.title":`Gym`', '"settings.title":`Settings`']);
	const { errors } = checkBudgets({
		...f,
		sentinels,
		codeContains: (path, needle) => path.endsWith('nodes/3.js') && leaked.has(needle),
	});
	assert.deepEqual(errors.map((e) => e.budget), ['catalogue-leak']);
	assert.match(errors[0].message, /nodes\/3\.js carries the strings of 2 catalogue part\(s\) — en\/gym, en\/settings/);
	assert.match(errors[0].message, /through m\(\)/);
});

test('a lazy part is not a leak of itself', () => {
	const f = fixture();
	const { errors } = checkBudgets({
		...f,
		sentinels: new Map([['de/gym', '"gym.empty":`Noch nichts`']]),
		codeContains: (path) => path.endsWith('/de-gym.js'),
	});
	assert.deepEqual(errors, [], 'the part chunk holds its own sentinel by construction; it is not code');
});

test('catalogueSentinel takes the first property in any quote style the minifier picks', () => {
	assert.equal(
		catalogueSentinel('var e={"admin.reports.title":`通報キュー`,"admin.x":`y`};export{e as default};'),
		'"admin.reports.title":`通報キュー`',
	);
	assert.equal(catalogueSentinel(`var e={"a.b":"it's",}`), '"a.b":"it\'s"');
	assert.equal(catalogueSentinel(`var e={"a.b":'say "hi"'}`), `"a.b":'say "hi"'`);
	assert.equal(catalogueSentinel('var e={};export{e as default};'), null);
});

test('catalogueChunks reads hyphenated tags and parts, and ignores everything else', () => {
	const chunks = catalogueChunks({
		'virtual:i18n-catalogue/pt-BR/core': { file: 'chunks/a.js' },
		'virtual:i18n-catalogue/de/settingsAccount': { file: 'chunks/b.js' },
		'virtual:i18n-catalogues': { file: 'chunks/c.js' },
		'virtual:i18n-catalogue/de/nested/gym': { file: 'chunks/d.js' },
		'src/lib/i18n/locales/de.ts': { file: 'chunks/e.js' },
		'virtual:i18n-catalogue/fr/core': {},
	});
	assert.deepEqual([...chunks], [
		['pt-BR/core', 'chunks/a.js'],
		['de/settingsAccount', 'chunks/b.js'],
	]);
	assert.equal(CATALOGUE_SOURCE.test('virtual:i18n-catalogue/en/gym'), true);
});

test('localeTags reads the catalogue directory and skips its tests', () => {
	const dir = mkdtempSync(join(tmpdir(), 'budget-locales-'));
	try {
		for (const f of ['en.ts', 'pt-BR.ts', 'de.ts', 'messages.test.ts', 'README.md']) {
			writeFileSync(join(dir, f), '');
		}
		assert.deepEqual(localeTags(dir), ['de', 'en', 'pt-BR']);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
});

test('collectEmitted walks nested output and returns every emitted file', () => {
	// It used to return JS and CSS only, which is how a font twice the size of
	// the whole code budget sat outside all three ceilings. Classification is
	// checkBudgets' job; the walk's job is to miss nothing.
	const dir = mkdtempSync(join(tmpdir(), 'budget-build-'));
	try {
		mkdirSync(join(dir, '_app', 'immutable', 'chunks'), { recursive: true });
		writeFileSync(join(dir, '_app', 'immutable', 'chunks', 'a.js'), 'x'.repeat(4096));
		writeFileSync(join(dir, '_app', 'b.css'), 'y'.repeat(4096));
		writeFileSync(join(dir, '_app', 'font.woff2'), 'w'.repeat(4096));
		writeFileSync(join(dir, 'index.html'), 'z'.repeat(4096));
		const files = collectEmitted(dir);
		assert.deepEqual(files.map((f) => f.path), [
			'_app/b.css',
			'_app/font.woff2',
			'_app/immutable/chunks/a.js',
			'index.html',
		]);
		for (const f of files) assert.equal(f.kb, 1, 'a compressible 4 KiB file ceils to 1 KB');
		assert.deepEqual(files.filter((f) => !isCodeFile(f.path)).map((f) => f.path), [
			'_app/font.woff2',
			'index.html',
		]);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
});

test('gzipKb rounds a part-kilobyte up', () => {
	assert.equal(gzipKb(Buffer.alloc(0)), 1);
});

test('the summary states the catalogue total without gating on it', () => {
	const text = renderSummary(checkBudgets(fixture()).summary);
	assert.match(text, /Code \(every reader, any language\) \| 2065 KB across 9 files \| 2251 KB/);
	assert.match(text, /Largest core catalogue \(ja\) \| 25 KB \| 28 KB, per core/);
	assert.match(text, /Largest area catalogue \(de\/settings\) \| 11 KB \| 14 KB, per area/);
	assert.match(text, /ungated in total \(240 KB across 20 parts; a reader fetches one core/);
	assert.match(text, /Largest single asset[^|]*\| 74 KB \| 100 KB, per asset/);
	assert.match(text, /ungated in total too \(199 KB across 9/);
});

test('the shipped ceilings are the ones this suite reasons about', () => {
	assert.equal(MAX_CODE_KB, 2251);
	assert.equal(MAX_CORE_CATALOGUE_KB, 28);
	assert.equal(MAX_AREA_CATALOGUE_KB, 14);
	assert.equal(MAX_LARGEST_CHUNK_KB, 350);
	assert.equal(MAX_ASSET_KB, 100);
	assert.equal(
		ASSET_EXEMPTIONS.length,
		0,
		'every emitted asset clears the ceiling on its own. The list stays for the ' +
			'next one that cannot, and the cases below exercise it with fixtures — an ' +
			'exemption nothing needs is a hole nobody is watching.',
	);
});

test('an oversized asset the exemptions do not name is reported', () => {
	const { errors } = checkBudgets(
		fixture({ assets: [...ASSET_KB, { path: 'hero-photo.png', kb: 240 }] }),
	);
	assert.deepEqual(errors.map((e) => e.budget), ['asset']);
	assert.match(errors[0].message, /hero-photo\.png is 240 KB gzipped, over the 100 KB/);
	assert.match(errors[0].message, /never summed/);
});

test('prerendering /learn once per language moves no ceiling', () => {
	// The question this population was added for. Eight guides plus a category
	// index across six more languages is 54 more prerendered pages and ~250 KB
	// of HTML nobody downloads together, because a reader loads ONE page.
	const perLocale = [];
	for (const tag of ['de', 'es', 'fr', 'ja', 'pt-BR', 'pt-PT']) {
		for (let i = 0; i < 9; i++) perLocale.push({ path: `${tag}/learn/guide-${i}.html`, kb: 5 });
	}
	const grown = fixture({ assets: [...ASSET_KB, ...perLocale] });
	const { errors, summary } = checkBudgets(grown);
	assert.deepEqual(errors, []);
	assert.equal(summary.assetFileCount, 63);
	assert.equal(summary.assetKb, 469);
	assert.equal(summary.largestAsset.kb, 74, 'the largest asset is still the font');
});

/// The shipped list is empty, so the three cases below drive the mechanism with
/// the entry that used to be in it — the unsubsetted font at its 3900 KB
/// ceiling. Keeping the real shape means the arithmetic is still tested against
/// a plausible exemption rather than a synthetic one.
const RETIRED_FONT_EXEMPTION = Object.freeze({
	pattern: /^_app\/immutable\/assets\/material-symbols-outlined\.[^/]+\.woff2$/,
	maxKb: 3900,
	why: 'the full unsubsetted Material Symbols Outlined variable font',
});
const UNSUBSET_FONT = {
	path: '_app/immutable/assets/material-symbols-outlined.CqIkmgaP.woff2',
	kb: 3866,
};
/** @param {{path: string, kb: number}[]} assets */
const withRetiredExemption = (assets) => ({
	...fixture({ assets }),
	assetExemptions: [RETIRED_FONT_EXEMPTION],
});

test('an exempt asset is held to its own ceiling, and a version bump keeps it', () => {
	const rehashed = { path: UNSUBSET_FONT.path.replace('CqIkmgaP', 'Zq7Kb2Lm'), kb: 3870 };
	assert.deepEqual(
		checkBudgets(withRetiredExemption([rehashed, ...ASSET_KB.slice(1)])).errors,
		[],
		'vite content-hashes the asset, so the exemption must survive a font update',
	);

	const grown = { path: UNSUBSET_FONT.path, kb: 4100 };
	const { errors } = checkBudgets(withRetiredExemption([grown, ...ASSET_KB.slice(1)]));
	assert.deepEqual(errors.map((e) => e.budget), ['asset-exemption']);
	assert.match(errors[0].message, /over its own 3900 KB exemption ceiling by 200 KB/);
});

test('an exemption that names nothing in the build is reported', () => {
	const { errors } = checkBudgets(withRetiredExemption(ASSET_KB.slice(1)));
	assert.deepEqual(errors.map((e) => e.budget), ['asset-exemption']);
	assert.match(errors[0].message, /emits no such file/);
});

test('an exempt asset that has shrunk under the ceiling loses its exemption', () => {
	// This is the case that actually fired: the subset landed at 74 KB under an
	// exemption written for 3900, and the guard demanded the entry go rather
	// than sit there covering nothing.
	const subset = { path: UNSUBSET_FONT.path, kb: 74 };
	const { errors } = checkBudgets(withRetiredExemption([subset, ...ASSET_KB.slice(1)]));
	assert.deepEqual(errors.map((e) => e.budget), ['asset-exemption']);
	assert.match(errors[0].message, /no longer needs the exemption/);
});

test('assets are outside the code and largest-chunk budgets, not silently inside them', () => {
	// The font this population was written for is 1.8x MAX_CODE_KB on its own.
	// If the widened walk let it into the code population, the code ceiling
	// would fail on the first run and the largest-chunk one would name a woff2.
	const { errors, summary } = checkBudgets(withRetiredExemption([
		UNSUBSET_FONT,
		...ASSET_KB.slice(1),
	]));
	assert.deepEqual(errors, []);
	assert.equal(summary.codeKb, 2065);
	assert.match(summary.largest.path, /\.js$/);
	assert.ok(summary.largestAsset.kb > MAX_CODE_KB, 'the font outweighs the entire code ceiling');
});

/// decisions.md § 775 turned on this guard's own input. Every ceiling is an
/// upper bound, so an empty walk clears all four: a build directory the walk
/// never found reads exactly like a bundle under budget.
test('an empty build directory fails rather than clearing every ceiling', () => {
	const { errors, summary } = checkBudgets({
		files: [],
		catalogues: new Map(),
		locales: ['en'],
	});
	assert.equal(summary.codeKb, 0);
	assert.ok(
		errors.some((e) => e.budget === 'classification' && /no emitted files at all/.test(e.message)),
		`expected the empty walk to be reported, got ${JSON.stringify(errors)}`,
	);
});

test('a build with files but no JS or CSS is a walk pointed somewhere else', () => {
	// Reachable without touching the i18n store: the manifest and the locale
	// directory can both be intact while the walk reads a directory holding
	// only prerendered HTML.
	const { errors } = checkBudgets({
		files: [
			{ path: 'index.html', kb: 2 },
			{ path: 'favicon.png', kb: 1 },
		],
		catalogues: new Map(),
		locales: ['en'],
	});
	assert.ok(
		errors.some((e) => /not one of them is JS or CSS/.test(e.message)),
		`expected the code population to be reported empty, got ${JSON.stringify(errors)}`,
	);
});

test('the empty-walk floor does not fire on a real build', () => {
	const { errors } = checkBudgets(fixture());
	assert.ok(!errors.some((e) => /no emitted files at all|not one of them is JS or CSS/.test(e.message)));
});

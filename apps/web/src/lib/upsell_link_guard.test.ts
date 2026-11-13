import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { en } from './i18n/locales/en';

// Every upsell opens Pro (issue #1374, decisions § 2494; twin of mobile's
// `upsell_link_guard_test.dart`). Prompts said "Upgrade to enhance" or
// "Upgrade to Pro" as plain text, or linked the Pro page under a label that
// named something else ("Enhance with AI"), so a runner who wanted to pay was
// left to find the page. `ProUpsellLink` draws the reason with a "See Pro"
// link; these keep a new prompt from going back to prose.
//
//   1. No English string sends the reader to Settings to upgrade.
//   2. Every English string outside the Pro page's own keys that names Pro is
//      an upsell (in UPSELLS, and every file that reads it renders
//      `ProUpsellLink`) or exempt with the reason it sells nothing.
//   3. Both lists only shrink: an entry that no longer matches fails.

const UPSELLS = new Set([
	'coachChat.limitUpgrade',
	'routeDetail.enhanceUpgradeHint',
	'routeNew.generateProUpsell',
	'routeNew.aiRequestProOnly',
	'coachAssist.errorUpgrade',
	'nutrition.platePhotoErrorPro',
]);

const EXEMPT: Record<string, string> = {
	'billingIssue.headline': "a billing notice about the reader's own Pro, with its own fix-payment action",
	'routeNew.aiRequestHint': 'the caption of a control only a Pro account is shown',
	'settingsAccount.cloudExportFootnoteSuffix': 'states each tier\'s export allowance on the export itself',
	'settingsAccount.fullArchiveFootnoteSuffix': 'states each tier\'s export allowance on the export itself',
	'compare.metaDescription': "names Strava's Pro, not ours",
	'compare.heroHeading': "names Strava's Pro, not ours",
	'compare.tagline': "names Strava's Pro, not ours",
	'compare.linkStravaProPricing': "names Strava's Pro, not ours",
	'proGate.cta': "the caption above ProGate's own Upgrade button, which opens Pro",
	'features.aiCoach.description': "the feature registry's description, shown on the Pro page and in ProGate",
	'features.priorityProcessing.description': "the feature registry's description, shown on the Pro page and in ProGate",
	'settingsLayout.tabProSupport': 'the settings nav entry for the Pro page itself',
	'nutrition.platePhotoProBadge': 'a tag on the photo entry, beside which nothing is sold',
	'help.requiresPro': 'a tag on a help guide, beside which nothing is sold',
	'login.brandFoot': 'the sign-in page tagline, read before there is an account to upgrade',
	'login.formFoot': 'the sign-in page tagline, read before there is an account to upgrade',
};

// The Pro page's own copy is about Pro by definition.
const PRO_PAGE_PREFIXES = ['upgrade.', 'proGate.badge', 'proGate.upgrade', 'proUpsell.'];

const NAMES_PRO = /\bPro\b/;
const DEAD_END = /\b(upgrade|subscribe|go pro|get pro)\b[^.]*\b(in|from|under|via)\s+(the\s+)?Settings\b/i;

const english = en as Record<string, string>;
const SRC = resolve(new URL('.', import.meta.url).pathname, '..');

function sources(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		if (entry.name === 'node_modules' || entry.name === 'i18n') continue;
		const path = join(dir, entry.name);
		if (entry.isDirectory()) sources(path, out);
		else if (/\.(svelte|ts)$/.test(entry.name) && !entry.name.endsWith('.test.ts')) out.push(path);
	}
	return out;
}

test('the dead-end matcher flags directions to Settings and spares the rest', () => {
	assert.ok(DEAD_END.test('Upgrade to Pro in Settings.'));
	assert.ok(DEAD_END.test('You can subscribe from the Settings page.'));
	assert.ok(!DEAD_END.test('AI descriptions are a Pro feature.'));
	assert.ok(!DEAD_END.test('Upgrade to Pro for a higher daily cap. Settings are unchanged.'));
});

test('no English string sends the reader to Settings to upgrade', () => {
	const offenders = Object.entries(english)
		.filter(([, v]) => DEAD_END.test(v))
		.map(([k, v]) => `${k}: ${v}`);
	assert.deepEqual(offenders, [], 'Show the reason with ProUpsellLink, which opens Pro; the string gives no directions.');
});

test('every string that names Pro is a registered upsell or exempt', () => {
	const unclassified = Object.entries(english)
		.filter(([k, v]) => NAMES_PRO.test(v) && !PRO_PAGE_PREFIXES.some((p) => k.startsWith(p)))
		.filter(([k]) => !UPSELLS.has(k) && !Object.hasOwn(EXEMPT, k))
		.map(([k, v]) => `${k}: ${v}`);
	assert.deepEqual(
		unclassified,
		[],
		'A new string that names Pro is an upsell: add it to UPSELLS and draw it with ProUpsellLink, or exempt it with the reason it sells nothing.',
	);
});

test('every file that reads an upsell renders ProUpsellLink', () => {
	const readers = new Map<string, number>([...UPSELLS].map((k) => [k, 0]));
	const offenders: string[] = [];
	for (const path of sources(SRC)) {
		const src = readFileSync(path, 'utf8');
		for (const key of UPSELLS) {
			if (!src.includes(`'${key}'`)) continue;
			readers.set(key, readers.get(key)! + 1);
			if (!src.includes('<ProUpsellLink')) offenders.push(`src/${relative(SRC, path)}: ${key}`);
		}
	}
	assert.deepEqual(offenders, [], 'An upsell drawn as plain text is a dead end; render it through ProUpsellLink.');
	assert.deepEqual(
		[...readers].filter(([, n]) => n === 0).map(([k]) => k),
		[],
		'An upsell no file reads any more: drop it from UPSELLS.',
	);
});

test('the registry and exemptions only name live strings that name Pro', () => {
	const stale = [...UPSELLS, ...Object.keys(EXEMPT)].filter(
		(k) => !Object.hasOwn(english, k) || !NAMES_PRO.test(english[k]),
	);
	assert.deepEqual(stale, []);
	for (const [k, why] of Object.entries(EXEMPT)) assert.ok(why.trim().length > 0, `${k}: an exemption needs a reason`);
});

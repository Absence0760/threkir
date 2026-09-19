// Every setting in the registry is reachable from exactly the settings pages
// this file says it is (issue #905). `/settings/preferences` held 32 settings
// on one page before it was split into topical pages; a split, a merge or a
// quiet delete that drops a control leaves a preference nobody can change, and
// nothing else in the suite would notice. So the registry
// (docs/backend/settings.md § Keys) is read, every settings page is scanned for
// the keys it edits, and the two must agree in both directions: a key with no
// declared home fails, a home whose page no longer names the key fails, and a
// page that starts editing a key somewhere undeclared fails.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
	BODY_METRICS_PAGE,
	LEGACY_PREFERENCES_ANCHORS,
	PREFERENCES_PAGES,
	legacyPreferencesTarget,
} from '../../lib/settings/preferences_ia';
import { stripSvelteComments } from '../../lib/core/strip_comments';
import { WEEKLY_GOAL_KEY } from '../../lib/settings/weekly_goal';
import { PRIVACY_ZONES_KEY } from '../../lib/routes/privacy';
import { DISCLOSURE_LEVEL_KEY } from '../../lib/settings/disclosure';

const SETTINGS_DIR = dirname(fileURLToPath(import.meta.url));
const SRC_DIR = resolve(SETTINGS_DIR, '../..');
const REGISTRY = resolve(SETTINGS_DIR, '../../../../../docs/backend/settings.md');

/// Where a registry key is edited on web. `page` is the settings page that owns
/// it; `also` names every other settings page that edits the same key, each
/// with the reason it is a second editor rather than a duplicate. `via` is the
/// exported constant a page names the key through, when it does not spell it.
/// `none` is a key with no web settings control, and says why.
type Home =
	| { page: string; via?: string; also?: Record<string, string> }
	| { none: string };

const PER_DEVICE_OVERRIDE = 'the per-device override editor for a UD key';
const ACCOUNT_PROFILE_CARD =
	"the account profile card's explicit Save writes the same prefs mirror (decisions § 718)";

const HOMES: Record<string, Home> = {
	preferred_unit: { page: 'display', also: { devices: PER_DEVICE_OVERRIDE } },
	default_activity_type: { page: 'recording', also: { devices: PER_DEVICE_OVERRIDE } },
	hr_zones: { page: 'training' },
	resting_hr_bpm: { page: 'training', also: { account: ACCOUNT_PROFILE_CARD } },
	max_hr_bpm: { page: 'training', also: { account: ACCOUNT_PROFILE_CARD } },
	date_of_birth: { page: 'body', also: { account: ACCOUNT_PROFILE_CARD } },
	cycle_tracking_mode: { page: 'account' },
	cycle_length_days: { page: 'account' },
	cycle_last_period_start: { page: 'account' },
	pregnancy_due_date: { page: 'account' },
	privacy_default: { page: 'privacy' },
	strava_auto_share: { page: 'privacy' },
	email_notifications: { page: 'notifications' },
	push_notifications: { page: 'notifications' },
	email_weekly_digest: { page: 'notifications' },
	email_lifecycle_drip: { page: 'notifications' },
	notify_data_export_ready: { page: 'notifications' },
	locale: { page: 'display' },
	discoverable_in_search: { page: 'privacy' },
	discoverable_nearby: { page: 'privacy' },
	trusted_contacts: { none: 'dormant: no surface reads or writes it (safety.md)' },
	primary_goal: { none: 'written by /onboarding, which is not a settings page' },
	disclosure_level: { page: 'display', via: 'DISCLOSURE_LEVEL_KEY' },
	dashboard_training_load_expanded: {
		none: "the /dashboard expander's own remembered state, not a control",
	},
	coach_personality: { page: 'training' },
	multi_modal_nav: { none: 'dormant: read by nothing since the § 63 amendment' },
	voice_feedback_enabled: { page: 'recording', also: { devices: PER_DEVICE_OVERRIDE } },
	voice_feedback_verbosity: { page: 'recording' },
	voice_feedback_interval_km: { page: 'recording', also: { devices: PER_DEVICE_OVERRIDE } },
	voice_cue_types: { page: 'recording' },
	haptic_feedback_enabled: { page: 'devices' },
	keep_screen_on: { page: 'devices' },
	dim_screen_while_recording: { none: 'phone-only recording preference, edited on mobile' },
	push_subscription: { page: 'devices' },
	map_style: { page: 'display', also: { devices: PER_DEVICE_OVERRIDE } },
	units_pace_format: { page: 'display', also: { devices: PER_DEVICE_OVERRIDE } },
	undo_window_s: { page: 'display' },
	weight_unit: {
		page: 'display',
		also: { body: 'reads it to show and parse body weight in the chosen unit; it has no control for it' },
	},
	body_weight_kg: {
		none: 'seeded by onboarding and the Health Connect importer; the body page records weight into body_metrics',
	},
	weekly_mileage_goal_m: { page: 'training', via: 'WEEKLY_GOAL_KEY' },
	nutrition_activity_level: { page: 'body' },
	nutrition_goal: { page: 'body' },
	carbs_per_hour: { page: 'training' },
	fluid_per_hour: { page: 'training' },
	show_calories: { page: 'display' },
	exclude_gym_from_readiness: { page: 'training' },
	week_start_day: { page: 'display' },
	privacy_zones: { page: 'privacy', via: 'PRIVACY_ZONES_KEY' },
	safety_overdue_minutes: { page: 'safety' },
	safety_off_route_alerts: { page: 'safety' },
	auto_live_share: { none: 'device-only recording preference, edited on mobile' },
	safety_nudge_dismissed_at: { none: 'written by the mobile run screen, not a control' },
};

function registryKeys(): string[] {
	const doc = readFileSync(REGISTRY, 'utf8');
	const start = doc.indexOf('\n## Keys');
	assert.ok(start >= 0, 'docs/backend/settings.md has no "## Keys" section');
	const end = doc.indexOf('\n#', start + 1);
	const section = doc.slice(start, end < 0 ? undefined : end);
	return [...section.matchAll(/^\| `([a-z0-9_]+)` \|/gm)].map((m) => m[1]);
}

function settingsPages(): Map<string, string> {
	const pages = new Map<string, string>();
	for (const entry of readdirSync(SETTINGS_DIR, { withFileTypes: true })) {
		if (!entry.isDirectory()) continue;
		const file = join(SETTINGS_DIR, entry.name, '+page.svelte');
		if (existsSync(file)) pages.set(entry.name, readFileSync(file, 'utf8'));
	}
	return pages;
}

/// Comments are blanked first: a page explaining that it no longer writes a
/// key is not an editor of it.
function code(source: string): string {
	return stripSvelteComments(source);
}

function names(source: string, key: string, via?: string): boolean {
	const k = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
	const spelled = new RegExp(`(['"\`])${k}\\1|\\b${k}\\s*:|\\.${k}\\b|\\[\\s*${k}\\s*\\]`);
	if (spelled.test(source)) return true;
	return via !== undefined && new RegExp(`\\b${via}\\b`).test(source);
}

function hrefPath(href: string): string {
	return href.split('#')[0].replace(/^\/settings\//, '');
}

test('the registry and the homes declared here name the same keys', () => {
	const registry = registryKeys();
	assert.ok(registry.length >= 40, `only ${registry.length} registry keys parsed — the table moved`);
	assert.deepEqual(
		[...registry].sort(),
		Object.keys(HOMES).sort(),
		'a registry key has no declared home here, or a home names a key the registry dropped',
	);
});

test('the key constants a page names a setting through still spell that key', () => {
	assert.equal(WEEKLY_GOAL_KEY, 'weekly_mileage_goal_m');
	assert.equal(PRIVACY_ZONES_KEY, 'privacy_zones');
	assert.equal(DISCLOSURE_LEVEL_KEY, 'disclosure_level');
});

test('every setting is edited on exactly the settings pages declared for it', () => {
	const pages = settingsPages();
	for (const [key, home] of Object.entries(HOMES)) {
		const via = 'via' in home ? home.via : undefined;
		const editing = [...pages]
			.filter(([, source]) => names(code(source), key, via))
			.map(([name]) => name)
			.sort();
		const declared = 'none' in home ? [] : [home.page, ...Object.keys(home.also ?? {})].sort();
		assert.deepEqual(
			editing,
			declared,
			`${key} is edited on [${editing.join(', ')}] but declared on [${declared.join(', ')}]`,
		);
	}
});

test('the settings nav and the preferences landing page offer every split page', () => {
	const pages = settingsPages();
	const layout = readFileSync(join(SETTINGS_DIR, '+layout.svelte'), 'utf8');
	assert.match(layout, /PREFERENCES_PAGES/, 'the settings nav no longer lists PREFERENCES_PAGES');
	assert.match(layout, /BODY_METRICS_PAGE/, 'the settings nav no longer lists BODY_METRICS_PAGE');
	const landing = pages.get('preferences') ?? '';
	assert.match(landing, /PREFERENCES_PAGES/);
	assert.match(landing, /BODY_METRICS_PAGE/);
	for (const page of [...PREFERENCES_PAGES, BODY_METRICS_PAGE]) {
		assert.ok(pages.has(hrefPath(page.href)), `${page.href} has no +page.svelte`);
	}
});

test('the landing page edits nothing, so no setting can hide there again', () => {
	const landing = settingsPages().get('preferences') ?? '';
	assert.doesNotMatch(landing, /createPrefsPage|updateUniversal|<input|<select/);
});

test('every section anchor the single page carried lands on a page that still has it', () => {
	const pages = settingsPages();
	for (const [anchor, target] of Object.entries(LEGACY_PREFERENCES_ANCHORS)) {
		const [path, id] = target.split('#');
		const source = pages.get(hrefPath(path));
		assert.ok(source, `${anchor} redirects to ${path}, which is not a settings page`);
		assert.match(source, new RegExp(`id="${id}"`), `${path} has no id="${id}" for #${anchor}`);
	}
});

test('an old section link resolves, and anything else stays on the landing page', () => {
	assert.equal(legacyPreferencesTarget('#heart-rate-zones'), '/settings/training#heart-rate-zones');
	assert.equal(legacyPreferencesTarget('#weekly-mileage-goal'), '/settings/training#weekly-distance-goal');
	assert.equal(legacyPreferencesTarget('body-metrics'), '/settings/body#body-metrics');
	for (const hash of ['', '#', '#units', '#toString', '#__proto__']) {
		assert.equal(legacyPreferencesTarget(hash), null, hash);
	}
});

test('in-app code links a moved section at its new page, never through the landing redirect', () => {
	const offenders: string[] = [];
	const walk = (dir: string) => {
		for (const entry of readdirSync(dir, { withFileTypes: true })) {
			const path = join(dir, entry.name);
			if (entry.isDirectory()) walk(path);
			else if (/\.(svelte|ts)$/.test(entry.name) && !/\.test\.ts$/.test(entry.name)) {
				for (const m of readFileSync(path, 'utf8').matchAll(/\/settings\/preferences#([\w-]+)/g)) {
					const target = legacyPreferencesTarget(m[1]);
					offenders.push(`${path}: #${m[1]} -> ${target ?? 'no settings page carries this section'}`);
				}
			}
		}
	};
	walk(SRC_DIR);
	assert.deepEqual(
		offenders,
		[],
		'the #anchor redirect exists for bookmarks and old emails; a link the app renders itself names the page the section lives on'
	);
});

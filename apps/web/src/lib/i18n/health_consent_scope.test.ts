import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { en } from './locales/en';

// Health-data consent names exactly what it covers, and every consent and
// withdrawal string names it the same way (decisions § 2512, § 2514). The
// Account checkbox once listed date of birth, heart rate and the food log while
// withdrawing it also erased height, gender, weight history and cycle and
// pregnancy details. Each item below is one effect of
// `withdraw_health_data_consent()` (or of `private.erase_health_records`, which
// the consent transition runs), so a new erasure that no string names fails here
// once its needle is added, and a needle the SQL drops fails too.

const ITEMS: Array<[phrase: string, sql: string]> = [
	['gender', 'gender = null'],
	['height', 'height_cm = null'],
	['weight history', 'delete from body_metrics'],
	['any cycle or pregnancy details', "'pregnancy_due_date'"],
	['the heart rate recorded with {p} activities', 'erase_health_records'],
	['the heart-rate targets in {p} plans', 'target_hr_min_bpm = null'],
	['{p} heart-rate medication setting', "'hr_medication_affected'"],
	['{p} food log', 'delete from public.food_log'],
];

function list(p: 'my' | 'your'): string {
	const items = ITEMS.map(([phrase]) => phrase.replace('{p}', p));
	return `${p} ${items.slice(0, -1).join(', ')} and ${items.at(-1)}`;
}

const CONSENT_KEYS = [
	'settingsAccount.healthConsentLabel',
	'prefs.demographicsConsent',
	'onboarding.healthConsent',
] as const;
const WITHDRAW_KEYS = [
	'settingsAccount.consentRecorded',
	'prefs.consentRecordedOn',
	'prefs.withdrawConsentMessage',
] as const;

const ARB = JSON.parse(
	readFileSync(resolve('../mobile_android/lib/l10n/app_en.arb'), 'utf8')
) as Record<string, string>;
const MIGRATIONS = resolve('../backend/supabase/migrations');

test('every consent statement is the same sentence and names the whole list', () => {
	const statement = en['settingsAccount.healthConsentLabel'];
	for (const k of CONSENT_KEYS) assert.equal(en[k], statement, `${k} differs`);
	assert.equal(ARB.setupHealthConsent, statement, 'mobile setupHealthConsent differs');
	assert.ok(statement.includes(list('my')), `the statement does not name: ${list('my')}`);
	assert.match(statement, /^I consent\b/);
	assert.doesNotMatch(statement, /\byou\b/i, 'the statement switches person');
	assert.ok(ARB.bodyMetricsConsentSubtitle.includes(list('your')), 'mobile switch subtitle');
});

test('every withdrawal string erases the same list and keeps the age record', () => {
	const texts: Array<[string, string]> = [
		...WITHDRAW_KEYS.map((k): [string, string] => [k, en[k]]),
		['mobile:bodyMetricsWithdrawBody', ARB.bodyMetricsWithdrawBody],
	];
	for (const [k, s] of texts) {
		assert.ok(s.includes(list('your')), `${k} does not name: ${list('your')}`);
		assert.ok(s.includes('your date of birth stays as your age record'), `${k}: age record`);
	}
});

test('the legal pages name the same list', () => {
	for (const page of ['privacy', 'health-data-notice']) {
		const s = readFileSync(resolve(`src/routes/${page}/+page.svelte`), 'utf8').replace(/\s+/g, ' ');
		assert.ok(s.includes(`erases ${list('your')}`), `/${page} does not name: ${list('your')}`);
	}
});

test('each item is still an effect of the withdrawal', () => {
	const files = readdirSync(MIGRATIONS).filter((f) => f.endsWith('.sql')).sort();
	const body = (name: string): string => {
		const f = files.filter((x) => readFileSync(resolve(MIGRATIONS, x), 'utf8').includes(`function ${name}`)).at(-1);
		assert.ok(f, `no migration defines ${name}`);
		return readFileSync(resolve(MIGRATIONS, f), 'utf8');
	};
	const sql = body('withdraw_health_data_consent()') + body('private.erase_health_records(');
	for (const [phrase, needle] of ITEMS) assert.ok(sql.includes(needle), `${phrase}: "${needle}" is gone`);
});

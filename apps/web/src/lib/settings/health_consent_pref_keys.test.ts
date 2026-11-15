// The consent-gated settings keys are named three times: the database's
// private.health_consent_pref_keys() (what a withdrawal clears), web's
// HEALTH_CONSENT_PREF_KEYS and Dart's healthConsentPrefKeys (what a restore
// and a queued write leave out without consent). A key added to one and not
// the others is a value one side erases and another writes back, or a restore
// that fails on a refusal (decisions § 2542).
import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { HEALTH_CONSENT_PREF_KEYS } from './settings_write';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '../../../../..');
const MIGRATIONS = resolve(ROOT, 'apps/backend/supabase/migrations');
const DART = resolve(ROOT, 'packages/api_client/lib/src/settings_service.dart');

function sqlKeys(): string[] {
	const files = readdirSync(MIGRATIONS)
		.filter((f) => f.endsWith('.sql'))
		.sort();
	let body: string | null = null;
	for (const f of files) {
		const src = readFileSync(resolve(MIGRATIONS, f), 'utf-8');
		const m = src.match(
			/function\s+private\.health_consent_pref_keys\(\)[\s\S]*?\$\$([\s\S]*?)\$\$/,
		);
		if (m) body = m[1];
	}
	assert.ok(body, 'no migration defines private.health_consent_pref_keys()');
	return [...body.matchAll(/'([a-z0-9_]+)'/g)].map((m) => m[1]).sort();
}

function dartKeys(): string[] {
	const src = readFileSync(DART, 'utf-8');
	const m = src.match(/const Set<String> healthConsentPrefKeys = \{([\s\S]*?)\};/);
	assert.ok(m, 'healthConsentPrefKeys not found in settings_service.dart');
	return [...m[1].matchAll(/'([a-z0-9_]+)'/g)].map((x) => x[1]).sort();
}

test('web names the same consent-gated keys as the database', () => {
	assert.deepEqual([...HEALTH_CONSENT_PREF_KEYS].sort(), sqlKeys());
});

test('Dart names the same consent-gated keys as the database', () => {
	assert.deepEqual(dartKeys(), sqlKeys());
});

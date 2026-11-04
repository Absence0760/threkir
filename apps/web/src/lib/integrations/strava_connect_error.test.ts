// Run with `npx tsx --test src/lib/integrations/strava_connect_error.test.ts`.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { AppError } from '../core/app_error';
import { errorCopy } from '../i18n/error_copy';
import { en } from '../i18n/locales/en';
import { stravaConnectAppError } from './strava_connect_error';

const t = (key: string) => (en as Record<string, string>)[key] ?? key;

test('a worded refusal throws its catalogue key and keeps the code for the log', () => {
	const err = stravaConnectAppError('missing_scope');
	assert.ok(err instanceof AppError);
	assert.equal(err.key, 'settingsIntegrations.stravaErrMissingScope');
	assert.equal(err.message, 'missing_scope');
});

test('the card shows the sentence, never the code', () => {
	for (const code of ['missing_scope', 'strava_token_exchange_failed', 'strava_not_configured', 'unauthorized']) {
		const shown = errorCopy(stravaConnectAppError(code), t, 'test');
		assert.ok(!shown.includes(code), `${code} reached the card: ${shown}`);
		assert.ok(!shown.includes('settingsIntegrations.'), `${code} rendered a key: ${shown}`);
	}
});

test('an unworded refusal is left to the caller to rethrow as it came', () => {
	assert.equal(stravaConnectAppError('store_tokens_failed'), null);
	assert.equal(stravaConnectAppError(null), null);
});

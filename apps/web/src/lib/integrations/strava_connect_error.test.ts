// Run with `npx tsx --test src/lib/integrations/strava_connect_error.test.ts`.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { AppError } from '../core/app_error';
import { errorCopy } from '../i18n/error_copy';
import { en } from '../i18n/locales/en';
import { stravaConnectAppError, stravaRefusal } from './strava_connect_error';

const t = (key: string) => (en as Record<string, string>)[key] ?? key;

test('a worded refusal throws its catalogue key and keeps the code for the log', () => {
	const err = stravaConnectAppError('missing_scope');
	assert.ok(err instanceof AppError);
	assert.equal(err.key, 'settingsIntegrations.stravaErrMissingScope');
	assert.equal(err.message, 'missing_scope');
});

test('the card shows the sentence, never the code', () => {
	for (const code of ['missing_scope', 'strava_token_exchange_failed', 'strava_not_configured', 'unauthorized', 'refresh_failed']) {
		const shown = errorCopy(stravaConnectAppError(code), t, 'test');
		assert.ok(!shown.includes(code), `${code} reached the card: ${shown}`);
		assert.ok(!shown.includes('settingsIntegrations.'), `${code} rendered a key: ${shown}`);
	}
});

test('an unworded refusal is left to the caller to rethrow as it came', () => {
	assert.equal(stravaConnectAppError('store_tokens_failed'), null);
	assert.equal(stravaConnectAppError(null), null);
});

/// A FunctionsHttpError's shape: the function's envelope rides on `context`.
function httpError(status: number, body: string): Error & { context: Response } {
	return Object.assign(new Error('Edge Function returned a non-2xx status code'), {
		name: 'FunctionsHttpError',
		context: new Response(body, { status, headers: { 'Content-Type': 'application/json' } }),
	});
}

test('a refused sync or disconnect shows the sentence for a worded code, never the code', async () => {
	const err = await stravaRefusal(httpError(503, JSON.stringify({ error: 'strava_not_configured' })));
	assert.ok(err instanceof AppError);
	const shown = errorCopy(err, t, 'test');
	assert.equal(shown, t('settingsIntegrations.stravaNotConfigured'));
	assert.ok(!shown.includes('strava_not_configured'));
});

test('an unworded code is rethrown bare, so errorCopy classifies it and never shows it', async () => {
	const limited = await stravaRefusal(httpError(429, JSON.stringify({ error: 'rate_limit_exceeded' })));
	assert.equal(errorCopy(limited, t, 'test'), t('errorCopy.tooManyRequests'));
	const unworded = await stravaRefusal(httpError(400, JSON.stringify({ error: 'strava_not_connected' })));
	const shown = errorCopy(unworded, t, 'test');
	assert.ok(!shown.includes('strava_not_connected'), shown);
	assert.ok(!/non-2xx|Edge Function/.test(shown), shown);
});

test('a grant Strava refuses tells the runner to connect again, not that something went wrong', async () => {
	// What `sync` answers when Strava rejects the stored refresh token.
	const revoked = await stravaRefusal(
		httpError(401, JSON.stringify({ error: 'refresh_failed', reconnect_required: true })),
	);
	assert.ok(revoked instanceof AppError);
	assert.equal(revoked.key, 'settingsIntegrations.stravaErrReconnect');
	const shown = errorCopy(revoked, t, 'test');
	assert.equal(shown, t('settingsIntegrations.stravaErrReconnect'));
	assert.ok(!shown.includes('refresh_failed'), shown);
});

test('with no readable envelope the transport error goes through as it came', async () => {
	const unreadable = httpError(500, 'not json at all');
	assert.equal(await stravaRefusal(unreadable), unreadable);
	const dropped = Object.assign(new Error('Failed to send a request to the Edge Function'), {
		name: 'FunctionsFetchError',
	});
	const err = await stravaRefusal(dropped);
	assert.equal(err, dropped);
	assert.equal(errorCopy(err, t, 'test'), t('errorCopy.offline'));
});

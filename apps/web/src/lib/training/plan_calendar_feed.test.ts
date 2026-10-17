import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	fetchPlanCalendarFeedStatus,
	isPlanCalendarFeedToken,
	planCalendarFeedUrl,
	revokePlanCalendarFeed,
	rotatePlanCalendarFeed,
	webcalUrl,
} from './plan_calendar_feed.ts';

const TOKEN = 'a'.repeat(32) + '0123456789abcdef'.repeat(4);

function rpcClient(result: { data: unknown; error: unknown }, calls: string[] = []) {
	return {
		rpc: async (name: string) => {
			calls.push(name);
			return result;
		},
	} as unknown as Parameters<typeof fetchPlanCalendarFeedStatus>[0];
}

test('a token is exactly the 96 lowercase hex characters rotate_plan_calendar_feed mints', () => {
	assert.equal(isPlanCalendarFeedToken(TOKEN), true);
	assert.equal(isPlanCalendarFeedToken(TOKEN.slice(1)), false);
	assert.equal(isPlanCalendarFeedToken(TOKEN.toUpperCase()), false);
	assert.equal(isPlanCalendarFeedToken(`${TOKEN.slice(1)}/`), false);
});

test('the feed URL is the plan-calendar function under the project URL', () => {
	assert.equal(
		planCalendarFeedUrl('https://abc.supabase.co', TOKEN),
		`https://abc.supabase.co/functions/v1/plan-calendar/${TOKEN}.ics`,
	);
	assert.equal(
		planCalendarFeedUrl('https://abc.supabase.co/', TOKEN),
		`https://abc.supabase.co/functions/v1/plan-calendar/${TOKEN}.ics`,
	);
	assert.equal(
		planCalendarFeedUrl('http://127.0.0.1:24321', TOKEN),
		`http://127.0.0.1:24321/functions/v1/plan-calendar/${TOKEN}.ics`,
	);
});

test('nothing that is not a minted token becomes a link', () => {
	assert.equal(planCalendarFeedUrl('https://abc.supabase.co', '../../rest/v1/runs'), null);
	assert.equal(planCalendarFeedUrl('https://abc.supabase.co', ''), null);
	assert.equal(planCalendarFeedUrl('not a url', TOKEN), null);
});

test('only an https feed becomes a webcal subscribe link', () => {
	assert.equal(webcalUrl('https://abc.supabase.co/x.ics'), 'webcal://abc.supabase.co/x.ics');
	assert.equal(webcalUrl('http://127.0.0.1:24321/x.ics'), null);
});

test('status reads the two timestamps, and no row means no feed', async () => {
	const row = { created_at: '2031-01-01T00:00:00Z', last_fetched_at: null };
	assert.deepEqual(await fetchPlanCalendarFeedStatus(rpcClient({ data: [row], error: null })), {
		createdAt: '2031-01-01T00:00:00Z',
		lastFetchedAt: null,
	});
	assert.equal(await fetchPlanCalendarFeedStatus(rpcClient({ data: [], error: null })), null);
	await assert.rejects(fetchPlanCalendarFeedStatus(rpcClient({ data: null, error: { message: 'boom' } })));
});

test('rotate returns the token and refuses anything that is not one', async () => {
	const calls: string[] = [];
	assert.equal(await rotatePlanCalendarFeed(rpcClient({ data: TOKEN, error: null }, calls)), TOKEN);
	assert.deepEqual(calls, ['rotate_plan_calendar_feed']);
	await assert.rejects(rotatePlanCalendarFeed(rpcClient({ data: 'short', error: null })));
	await assert.rejects(rotatePlanCalendarFeed(rpcClient({ data: null, error: { message: 'rate limit' } })));
});

test('revoke surfaces a failure instead of reporting the link gone', async () => {
	const calls: string[] = [];
	await revokePlanCalendarFeed(rpcClient({ data: true, error: null }, calls));
	assert.deepEqual(calls, ['revoke_plan_calendar_feed']);
	await assert.rejects(revokePlanCalendarFeed(rpcClient({ data: null, error: { message: 'boom' } })));
});

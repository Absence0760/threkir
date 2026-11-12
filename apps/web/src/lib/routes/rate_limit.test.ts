import assert from 'node:assert/strict';
import { test } from 'node:test';

import type { SupabaseClient } from '@supabase/supabase-js';

import { checkRouteRateLimit, refundRouteRateLimitSlot, spendRouteRateLimitSlot } from './rate_limit';

/// Minimal fake that records the `check_rate_limit` RPC args and returns
/// a scripted `{ data, error }`. Only `.rpc` is exercised by the helper.
function fakeClient(
	respond: (args: Record<string, unknown>) => { data: unknown; error: unknown },
): { client: SupabaseClient; calls: Record<string, unknown>[] } {
	const calls: Record<string, unknown>[] = [];
	const client = {
		rpc: async (_fn: string, args: Record<string, unknown>) => {
			calls.push(args);
			return respond(args);
		},
	} as unknown as SupabaseClient;
	return { client, calls };
}

test('checkRouteRateLimit passes the caller id + bucket + window to the RPC', async () => {
	const { client, calls } = fakeClient(() => ({ data: [{ allowed: true }], error: null }));
	const v = await checkRouteRateLimit(client, 'user-1', 'generate-route', 60, 3600);
	assert.equal(v, 'ok');
	assert.deepEqual(calls[0], {
		p_user_id: 'user-1',
		p_bucket: 'generate-route',
		p_max: 60,
		p_window_seconds: 3600,
	});
});

test('checkRouteRateLimit denies once the per-user ceiling is passed', async () => {
	// Simulate the SECURITY DEFINER counter: allowed while count <= max,
	// denied after. The helper must flip to 'limited' on the (max+1)th call.
	const MAX = 3;
	let count = 0;
	const { client } = fakeClient(() => {
		count += 1;
		return { data: [{ allowed: count <= MAX, retry_after_seconds: count <= MAX ? 0 : 42 }], error: null };
	});

	const verdicts: string[] = [];
	for (let i = 0; i < MAX + 2; i++) {
		verdicts.push(await checkRouteRateLimit(client, 'user-1', 'generate-route', MAX, 3600));
	}
	assert.deepEqual(verdicts, ['ok', 'ok', 'ok', 'limited', 'limited']);
});

test('checkRouteRateLimit fails closed on an RPC error', async () => {
	const { client } = fakeClient(() => ({ data: null, error: { message: 'db down' } }));
	assert.equal(await checkRouteRateLimit(client, 'user-1', 'osrm-proxy', 1200, 3600), 'error');
});

test('checkRouteRateLimit fails closed on a malformed / empty result row', async () => {
	const empty = fakeClient(() => ({ data: [], error: null }));
	assert.equal(await checkRouteRateLimit(empty.client, 'u', 'osrm-proxy', 10, 3600), 'error');

	const notArray = fakeClient(() => ({ data: { allowed: true }, error: null }));
	assert.equal(await checkRouteRateLimit(notArray.client, 'u', 'osrm-proxy', 10, 3600), 'error');
});

test('checkRouteRateLimit treats a non-true allowed field as limited (fail-closed shape)', async () => {
	// A row that isn't a genuine `allowed: true` must never be read as ok —
	// a missing/garbled field is a denial, not a grant.
	const missing = fakeClient(() => ({ data: [{ retry_after_seconds: 5 }], error: null }));
	assert.equal(await checkRouteRateLimit(missing.client, 'u', 'osrm-proxy', 10, 3600), 'limited');

	const stringy = fakeClient(() => ({ data: [{ allowed: 'true' }], error: null }));
	assert.equal(await checkRouteRateLimit(stringy.client, 'u', 'osrm-proxy', 10, 3600), 'limited');
});

/// A fake of the two ticketed RPCs over one window: an allowed spend issues a
/// ticket, a refund for a live ticket gives the slot back once.
function ticketedClient(max: number, opts: { refundError?: boolean } = {}) {
	let count = 0;
	let next = 0;
	const live = new Set<string>();
	const calls: { fn: string; args: Record<string, unknown> }[] = [];
	const client = {
		rpc: async (fn: string, args: Record<string, unknown>) => {
			calls.push({ fn, args });
			if (fn === 'spend_rate_limit_slot') {
				count += 1;
				if (count > max) return { data: [{ allowed: false, retry_after_seconds: 9, spend_id: null }], error: null };
				const id = `ticket-${++next}`;
				live.add(id);
				return { data: [{ allowed: true, retry_after_seconds: 0, spend_id: id }], error: null };
			}
			if (fn === 'refund_rate_limit_slot') {
				if (opts.refundError) return { data: null, error: { message: 'db down' } };
				const ok = live.delete(args.p_spend_id as string);
				if (ok) count = Math.max(0, count - 1);
				return { data: ok, error: null };
			}
			throw new Error(`unexpected rpc ${fn}`);
		},
	} as unknown as SupabaseClient;
	return { client, calls, count: () => count };
}

test('spendRouteRateLimitSlot spends one slot and hands back its ticket', async () => {
	const fake = ticketedClient(20);
	const slot = await spendRouteRateLimitSlot(fake.client, 'user-1', 'plate-photo', 20, 3600);
	assert.deepEqual(slot, { verdict: 'ok', spendId: 'ticket-1' });
	assert.equal(fake.count(), 1);
	assert.deepEqual(fake.calls[0], {
		fn: 'spend_rate_limit_slot',
		args: { p_user_id: 'user-1', p_bucket: 'plate-photo', p_max: 20, p_window_seconds: 3600 },
	});
});

test('a refunded ticket gives the slot back, once', async () => {
	const fake = ticketedClient(1);
	const slot = await spendRouteRateLimitSlot(fake.client, 'user-1', 'plate-photo', 1, 3600);
	assert.equal((await spendRouteRateLimitSlot(fake.client, 'user-1', 'plate-photo', 1, 3600)).verdict, 'limited');

	await refundRouteRateLimitSlot(fake.client, 'user-1', 'plate-photo', slot.spendId, 'provider_error');
	assert.deepEqual(fake.calls.at(-1), {
		fn: 'refund_rate_limit_slot',
		args: { p_user_id: 'user-1', p_bucket: 'plate-photo', p_spend_id: 'ticket-1' },
	});
	assert.equal(fake.count(), 1, 'the refused call still counted; only the refunded slot came back');

	await refundRouteRateLimitSlot(fake.client, 'user-1', 'plate-photo', slot.spendId, 'provider_error');
	assert.equal(fake.count(), 1, 'a second refund of the same ticket gives nothing back');
});

test('spendRouteRateLimitSlot fails closed and refuses a garbled row', async () => {
	const down = fakeClient(() => ({ data: null, error: { message: 'db down' } }));
	assert.deepEqual(await spendRouteRateLimitSlot(down.client, 'u', 'plate-photo', 20, 3600), {
		verdict: 'error',
		spendId: null,
	});
	const stringy = fakeClient(() => ({ data: [{ allowed: 'true', spend_id: 'x' }], error: null }));
	assert.deepEqual(await spendRouteRateLimitSlot(stringy.client, 'u', 'plate-photo', 20, 3600), {
		verdict: 'limited',
		spendId: null,
	});
});

test('refundRouteRateLimitSlot is a no-op without a ticket and never throws', async () => {
	const fake = ticketedClient(5, { refundError: true });
	await refundRouteRateLimitSlot(fake.client, 'u', 'plate-photo', null, 'refusal');
	assert.equal(fake.calls.length, 0, 'no ticket, no call');

	const errors: unknown[] = [];
	const original = console.error;
	console.error = (...args: unknown[]) => errors.push(args);
	try {
		await refundRouteRateLimitSlot(fake.client, 'u', 'plate-photo', 'ticket-9', 'refusal');
		const throwing = { rpc: async () => { throw new Error('socket hang up'); } } as unknown as SupabaseClient;
		await refundRouteRateLimitSlot(throwing, 'u', 'plate-photo', 'ticket-9', 'refusal');
	} finally {
		console.error = original;
	}
	assert.equal(errors.length, 2, 'both the RPC error and the throw are logged, not raised');
});

/// Strava deauthorization: the webhook's athlete-revoked event and the
/// user-initiated Disconnect share one local teardown.
///
/// Run with:
///   cd apps/backend && deno test supabase/functions/_shared/strava_disconnect.test.ts

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import type { DbClient } from './database.ts';
import {
	disconnectDeauthorizedAthlete,
	disconnectStravaLocally,
	isAthleteDeauthorization,
} from './strava_disconnect.ts';

type Filter = [string, string, unknown];
type FromCall = { kind: 'select' | 'update'; payload?: Record<string, unknown>; filters: Filter[] };

function makeMock(opts: {
	linked?: Array<{ user_id: string }>;
	lookupError?: boolean;
	rpcErrorFor?: string;
	updateError?: boolean;
} = {}) {
	const rpcCalls: Array<{ name: string; args: Record<string, unknown> }> = [];
	const fromCalls: FromCall[] = [];

	const builder = () => {
		const call: FromCall = { kind: 'select', filters: [] };
		fromCalls.push(call);
		const b: Record<string, unknown> = {};
		b.select = () => b;
		b.update = (payload: Record<string, unknown>) => {
			call.kind = 'update';
			call.payload = payload;
			return b;
		};
		b.eq = (col: string, v: unknown) => {
			call.filters.push(['eq', col, v]);
			return b;
		};
		b.is = (col: string, v: unknown) => {
			call.filters.push(['is', col, v]);
			return b;
		};
		b.then = (onF: (v: unknown) => unknown, onR?: (e: unknown) => unknown) => {
			const result = call.kind === 'update'
				? { error: opts.updateError ? { code: '42501' } : null }
				: opts.lookupError
				? { data: null, error: { code: '57014' } }
				: { data: opts.linked ?? [], error: null };
			return Promise.resolve(result).then(onF, onR);
		};
		return b;
	};

	const supabase = {
		from: () => builder(),
		rpc: (name: string, args: Record<string, unknown>) => {
			rpcCalls.push({ name, args });
			const failed = opts.rpcErrorFor !== undefined && args.p_user_id === opts.rpcErrorFor;
			return Promise.resolve({ data: null, error: failed ? { code: 'P0001' } : null });
		},
	} as unknown as DbClient;

	return { supabase, rpcCalls, fromCalls };
}

Deno.test('isAthleteDeauthorization matches only the athlete authorized=false update', () => {
	const base = { object_type: 'athlete', aspect_type: 'update', owner_id: 42, event_time: 1 };
	assertEquals(isAthleteDeauthorization({ ...base, updates: { authorized: 'false' } }), true);
	assertEquals(isAthleteDeauthorization({ ...base, updates: { authorized: false } }), true);
	assertEquals(isAthleteDeauthorization({ ...base, updates: { authorized: 'true' } }), false);
	assertEquals(isAthleteDeauthorization({ ...base, updates: { title: 'x' } }), false);
	assertEquals(isAthleteDeauthorization({ ...base, updates: null }), false);
	assertEquals(isAthleteDeauthorization({ ...base }), false);
	assertEquals(
		isAthleteDeauthorization({ ...base, object_type: 'activity', updates: { authorized: 'false' } }),
		false,
	);
	assertEquals(
		isAthleteDeauthorization({ ...base, aspect_type: 'create', updates: { authorized: 'false' } }),
		false,
	);
});

Deno.test('disconnectStravaLocally drops the vault tokens, then stamps the row with the reason', async () => {
	const { supabase, rpcCalls, fromCalls } = makeMock();
	assertEquals(await disconnectStravaLocally(supabase, 'u1', 'athlete_deauthorized'), 'ok');
	assertEquals(rpcCalls, [
		{ name: 'delete_user_provider_secrets', args: { p_user_id: 'u1', p_provider: 'strava' } },
	]);
	assertEquals(fromCalls.length, 1);
	const update = fromCalls[0];
	assertEquals(update.kind, 'update');
	assertEquals(update.payload?.disconnected_reason, 'athlete_deauthorized');
	assertEquals(update.payload?.sync_cursor, null);
	assertEquals(typeof update.payload?.disconnected_at, 'string');
	assertEquals(update.filters, [['eq', 'user_id', 'u1'], ['eq', 'provider', 'strava']]);
});

Deno.test('disconnectStravaLocally does not stamp the row when the vault cleanup fails', async () => {
	const { supabase, fromCalls } = makeMock({ rpcErrorFor: 'u1' });
	assertEquals(await disconnectStravaLocally(supabase, 'u1', 'user_initiated'), 'vault_cleanup_failed');
	assertEquals(fromCalls.length, 0);
});

Deno.test('disconnectStravaLocally reports a failed stamp', async () => {
	const { supabase } = makeMock({ updateError: true });
	assertEquals(await disconnectStravaLocally(supabase, 'u1', 'user_initiated'), 'stamp_failed');
});

Deno.test('disconnectDeauthorizedAthlete disconnects every live integration for the athlete', async () => {
	const { supabase, rpcCalls, fromCalls } = makeMock({ linked: [{ user_id: 'u1' }, { user_id: 'u2' }] });
	assertEquals(await disconnectDeauthorizedAthlete(supabase, 12345), { disconnected: 2, failed: 0 });
	assertEquals(fromCalls[0].kind, 'select');
	assertEquals(fromCalls[0].filters, [
		['eq', 'provider', 'strava'],
		['eq', 'external_id', '12345'],
		['is', 'disconnected_at', null],
	]);
	assertEquals(rpcCalls.map((c) => c.args.p_user_id), ['u1', 'u2']);
	const stamps = fromCalls.filter((c) => c.kind === 'update');
	assertEquals(stamps.map((c) => c.payload?.disconnected_reason), ['athlete_deauthorized', 'athlete_deauthorized']);
});

Deno.test('disconnectDeauthorizedAthlete is a no-op for an athlete nobody has linked', async () => {
	const { supabase, rpcCalls } = makeMock({ linked: [] });
	assertEquals(await disconnectDeauthorizedAthlete(supabase, 999), { disconnected: 0, failed: 0 });
	assertEquals(rpcCalls.length, 0);
});

Deno.test('disconnectDeauthorizedAthlete keeps going past one failed user and counts it', async () => {
	const { supabase, rpcCalls } = makeMock({
		linked: [{ user_id: 'u1' }, { user_id: 'u2' }],
		rpcErrorFor: 'u1',
	});
	assertEquals(await disconnectDeauthorizedAthlete(supabase, 7), { disconnected: 1, failed: 1 });
	assertEquals(rpcCalls.length, 2);
});

Deno.test('disconnectDeauthorizedAthlete counts a failed lookup as a failure', async () => {
	const { supabase, rpcCalls } = makeMock({ lookupError: true });
	assertEquals(await disconnectDeauthorizedAthlete(supabase, 7), { disconnected: 0, failed: 1 });
	assertEquals(rpcCalls.length, 0);
});

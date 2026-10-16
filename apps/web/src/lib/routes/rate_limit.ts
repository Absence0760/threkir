// Per-user rate-limit gate for the web handlers that reach a billed
// upstream: the route engines (generate-route, osrm-proxy) and the three
// Anthropic handlers (route-describe, route-request, plate-photo), which
// spend through `spendRouteRateLimitSlot` so a failed model call can give
// its slot back. Web-side
// sibling of the Edge Function helper
// `apps/backend/supabase/functions/_shared/rate_limit.ts`.
//
// Both handlers already resolve the caller on a JWT-bound anon client
// via `auth.getUser`; this helper reuses that same client to call the
// SECURITY DEFINER `check_rate_limit` RPC (migration 20260604_001)
// with the caller's OWN id, so the user-context guard added in
// 20260616_001 (`auth.uid() = p_user_id`) is satisfied without a
// service-role key. The RPC takes an arbitrary `p_bucket` text key, so
// no migration is needed to register a new bucket.
//
// Per-IP AWS WAF rules are the only other backstop, and a single JWT
// spread across a small IP pool stays under the per-IP cap while
// fanning out up to 32 billed upstream fetches per generate call
// (issue #339) — or one Opus request per route-describe / route-request
// call, on a subscription priced per month rather than per call. The
// per-user ceiling here is the durable guard the WAF can't provide.

import type { SupabaseClient } from '@supabase/supabase-js';

import { supabaseErrorFields, thrownMessage } from '../core/supabase_error';

export type RateLimitVerdict = 'ok' | 'limited' | 'error';

/// Increment + check the caller's fixed-window bucket. `'ok'` when the
/// call is under the ceiling, `'limited'` when it is over.
///
/// Fail-closed: an RPC error or a malformed result row returns
/// `'error'`, which the calling handler maps to a denial. These paths
/// fan out to billed upstream providers, so a throttle that silently
/// fell open on a transient DB blip would be a free cost-abuse vector —
/// the same posture export-data and clip-public-track take.
export async function checkRouteRateLimit(
	supabase: SupabaseClient,
	userId: string,
	bucket: string,
	max: number,
	windowSeconds: number,
): Promise<RateLimitVerdict> {
	const { data, error } = await supabase.rpc('check_rate_limit', {
		p_user_id: userId,
		p_bucket: bucket,
		p_max: max,
		p_window_seconds: windowSeconds,
	});
	if (error || !Array.isArray(data) || data.length === 0) {
		// The `?? error` this replaces put the whole PostgrestError in the
		// log line whenever `.message` was absent — exactly the case the
		// scrub exists for.
		console.error(
			`[rate_limit] check_rate_limit(${bucket}) failed; denying fail-closed:`,
			supabaseErrorFields(error),
		);
		return 'error';
	}
	const row = data[0] as { allowed?: unknown };
	return row.allowed === true ? 'ok' : 'limited';
}

export type RateLimitSpend = { verdict: RateLimitVerdict; spendId: string | null };

/// `checkRouteRateLimit` for a handler that may have to give the slot back:
/// the same counter and the same fail-closed verdicts, plus the refund ticket
/// `spend_rate_limit_slot` returns for an allowed spend. The ticket stays on
/// the server. A bare per-bucket decrement is not offered because the handler
/// holds only the caller's JWT, so anything it can call the runner can call
/// too; a ticket they were never given refunds nothing.
export async function spendRouteRateLimitSlot(
	supabase: SupabaseClient,
	userId: string,
	bucket: string,
	max: number,
	windowSeconds: number,
): Promise<RateLimitSpend> {
	const { data, error } = await supabase.rpc('spend_rate_limit_slot', {
		p_user_id: userId,
		p_bucket: bucket,
		p_max: max,
		p_window_seconds: windowSeconds,
	});
	if (error || !Array.isArray(data) || data.length === 0) {
		console.error(
			`[rate_limit] spend_rate_limit_slot(${bucket}) failed; denying fail-closed:`,
			supabaseErrorFields(error),
		);
		return { verdict: 'error', spendId: null };
	}
	const row = data[0] as { allowed?: unknown; spend_id?: unknown };
	if (row.allowed !== true) return { verdict: 'limited', spendId: null };
	return { verdict: 'ok', spendId: typeof row.spend_id === 'string' ? row.spend_id : null };
}

/// Give back a slot taken by `spendRouteRateLimitSlot` when the billed call
/// produced nothing the runner can use. Fail-soft: the caller is already on
/// its unhappy path, so a refund failure is logged and swallowed rather than
/// replacing the original error. A null ticket is a no-op.
export async function refundRouteRateLimitSlot(
	supabase: SupabaseClient,
	userId: string,
	bucket: string,
	spendId: string | null,
	reason: string,
): Promise<void> {
	if (!spendId) return;
	try {
		const { error } = await supabase.rpc('refund_rate_limit_slot', {
			p_user_id: userId,
			p_bucket: bucket,
			p_spend_id: spendId,
		});
		if (error) {
			console.error(`[rate_limit] refund_rate_limit_slot(${bucket}) failed`, {
				reason,
				...supabaseErrorFields(error),
			});
		}
	} catch (e) {
		console.error(`[rate_limit] refund_rate_limit_slot(${bucket}) threw`, {
			reason,
			err: thrownMessage(e),
		});
	}
}

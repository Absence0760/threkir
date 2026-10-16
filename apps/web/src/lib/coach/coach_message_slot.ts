// The AI Coach daily counter as a cost rail for the one-shot AI endpoints that
// spend the Coach's key (the plan assistant, AI plan edits — decisions § 1930,
// § 1981). One copy, so both endpoints take the slot, deny and refund the same
// way: the tier from `is_pro()`, the slot from `spend_coach_usage_slot`, an
// unreadable count denying (fail-closed) rather than granting, and a refund
// through `refund_coach_usage_slot` with that spend's ticket whenever the
// billed call yields nothing.
//
// The ticket is the refund's whole authority (decisions § 1990): these
// handlers hold only the caller's JWT, so any refund they can call the runner
// can call too, and a bare per-user decrement let a runner reset their own
// cap after every successful call. The ticket stays on the server; one the
// runner was never given refunds nothing.

import type Anthropic from '@anthropic-ai/sdk';
import type { SupabaseClient } from '@supabase/supabase-js';

import { dbError, thrownMessage } from '../core/supabase_error';
import { resolveUsageSpend } from './limits';
import { TIER_LIMITS, type Tier } from './types';

export type CoachMessageSlot =
	| { ok: true; spendId: string | null }
	| { ok: false; status: 429 | 503; payload: Record<string, unknown> };

/// Take one slot of the caller's daily Coach budget. Call it before the billed
/// provider call and refund with `refundCoachMessage` and the returned
/// `spendId` if that call yields nothing. `unavailableError` is the
/// endpoint's own 503 wording.
export async function spendCoachMessage(
	supabase: SupabaseClient,
	userId: string,
	logTag: string,
	unavailableError: string,
): Promise<CoachMessageSlot> {
	const proRes = await supabase.rpc('is_pro', undefined, { get: true });
	const tier: Tier = proRes.data === true ? 'pro' : 'free';
	const dailyLimit = TIER_LIMITS[tier].dailyLimit;
	const { data: spend, error: spendErr } = await supabase.rpc('spend_coach_usage_slot', {
		p_user_id: userId,
	});
	const usage = resolveUsageSpend(spend, spendErr);
	if (!usage.ok) {
		console.error(`[${logTag}] spend_coach_usage_slot failed — denying to keep the cap enforced`, {
			tier,
			error: spendErr?.message ?? 'unreadable spend row',
		});
		return { ok: false, status: 503, payload: { error: unavailableError } };
	}
	if (usage.usedToday > dailyLimit) {
		return {
			ok: false,
			status: 429,
			payload: { error: 'daily_limit', used: usage.usedToday, limit: dailyLimit, tier },
		};
	}
	return { ok: true, spendId: usage.spendId };
}

/// Hand back the slot `spendId` was issued for. Never throws: a failed refund
/// is logged and the caller's original answer stands. A null ticket is a
/// no-op, so a bypassed paywall or an unreadable ticket refunds nothing.
export async function refundCoachMessage(
	supabase: SupabaseClient,
	userId: string,
	spendId: string | null,
	logTag: string,
	reason: string,
): Promise<void> {
	if (!spendId) return;
	try {
		const { error } = await supabase.rpc('refund_coach_usage_slot', {
			p_user_id: userId,
			p_spend_id: spendId,
		});
		if (error) throw dbError(error);
	} catch (e) {
		console.error(`[${logTag}] refund_coach_usage_slot failed`, { reason, err: thrownMessage(e) });
	}
}

/// The forced tool's block in a model reply, or undefined when the model
/// answered without it.
export function forcedToolUse(
	message: Anthropic.Message,
	toolName: string,
): Anthropic.ToolUseBlock | undefined {
	return message.content.find(
		(b): b is Anthropic.ToolUseBlock => b.type === 'tool_use' && b.name === toolName,
	);
}

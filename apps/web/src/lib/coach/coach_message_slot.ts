// The AI Coach daily counter as a cost rail for the one-shot AI endpoints that
// spend the Coach's key (the plan assistant, AI plan edits — decisions § 1930,
// § 1981). One copy, so both endpoints take the slot, deny and refund the same
// way: the tier from `is_pro()`, the slot from `increment_coach_usage`, an
// unreadable count denying (fail-closed) rather than granting, and a refund
// through `decrement_coach_usage` whenever the billed call yields nothing.

import type Anthropic from '@anthropic-ai/sdk';
import type { SupabaseClient } from '@supabase/supabase-js';

import { dbError, thrownMessage } from '../core/supabase_error';
import { resolveUsageCount } from './limits';
import { TIER_LIMITS, type Tier } from './types';

export type CoachMessageSlot =
	| { ok: true }
	| { ok: false; status: 429 | 503; payload: Record<string, unknown> };

/// Take one slot of the caller's daily Coach budget. Call it before the billed
/// provider call and refund with `refundCoachMessage` if that call yields
/// nothing. `unavailableError` is the endpoint's own 503 wording.
export async function spendCoachMessage(
	supabase: SupabaseClient,
	userId: string,
	logTag: string,
	unavailableError: string,
): Promise<CoachMessageSlot> {
	const proRes = await supabase.rpc('is_pro', undefined, { get: true });
	const tier: Tier = proRes.data === true ? 'pro' : 'free';
	const dailyLimit = TIER_LIMITS[tier].dailyLimit;
	const { data: newCount, error: incrErr } = await supabase.rpc('increment_coach_usage', {
		p_user_id: userId,
	});
	const usage = resolveUsageCount(newCount, incrErr);
	if (!usage.ok) {
		console.error(`[${logTag}] increment_coach_usage failed — denying to keep the cap enforced`, {
			tier,
			error: incrErr?.message ?? `non-numeric count: ${typeof newCount}`,
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
	return { ok: true };
}

/// Hand a slot back. Never throws: a failed refund is logged and the caller's
/// original answer stands.
export async function refundCoachMessage(
	supabase: SupabaseClient,
	userId: string,
	logTag: string,
	reason: string,
): Promise<void> {
	try {
		const { error } = await supabase.rpc('decrement_coach_usage', { p_user_id: userId });
		if (error) throw dbError(error);
	} catch (e) {
		console.error(`[${logTag}] decrement_coach_usage failed`, { reason, err: thrownMessage(e) });
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

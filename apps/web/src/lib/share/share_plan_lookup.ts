/// Single source of truth for the share-plan fetch shape. Used by
///   - apps/web/src/routes/share/plan/[id]/+page.ts (dev-server SSR + SPA
///     hydration)
///   - apps/web/lambda/share-entity (the production per-request head)
///
/// A public-library plan's tables are readable by signed-in users only, so the
/// logged-out page reads the `public_plan_share` RPC instead: a SECURITY
/// DEFINER projection that returns the goal, the weeks and their workouts by
/// day offset, and the author's name only when their profile is visible to the
/// caller. No physiology, no paces, no notes, no dates, no user id
/// (decisions § 2262). It returns null for a plan that is not public, and for
/// every plan while the `public_plan_share` gate is closed.

import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { isEntityId } from '../core/entity_id';
import { thrownMessage } from '../core/supabase_error';

export interface SharedPlanWorkout {
	/// Days from the plan's first day; 0 is the first day.
	day: number;
	kind: string;
	target_distance_m: number | null;
	target_duration_seconds: number | null;
	pace_zone: string | null;
	target_rpe_min: number | null;
	target_rpe_max: number | null;
}

export interface SharedPlanWeek {
	week_index: number;
	phase: string | null;
	target_volume_m: number | null;
	workouts: SharedPlanWorkout[];
}

export interface SharedPlanAuthor {
	name: string | null;
	handle: string | null;
}

export interface SharedPlan {
	id: string;
	name: string;
	goal_event: string;
	goal_distance_m: number;
	days_per_week: number;
	author: SharedPlanAuthor | null;
	weeks: SharedPlanWeek[];
}

export interface SharedPlanLookupConfig {
	supabaseUrl: string;
	supabaseAnonKey: string;
}

function num(v: unknown): number | null {
	if (v == null) return null;
	const n = typeof v === 'number' ? v : Number(v);
	return Number.isFinite(n) ? n : null;
}

function str(v: unknown): string | null {
	return typeof v === 'string' ? v : null;
}

function obj(v: unknown): Record<string, unknown> | null {
	return v != null && typeof v === 'object' && !Array.isArray(v)
		? (v as Record<string, unknown>)
		: null;
}

function parseWorkout(v: unknown): SharedPlanWorkout | null {
	const o = obj(v);
	const day = num(o?.day);
	const kind = str(o?.kind);
	if (!o || day == null || !kind) return null;
	return {
		day,
		kind,
		target_distance_m: num(o.target_distance_m),
		target_duration_seconds: num(o.target_duration_seconds),
		pace_zone: str(o.pace_zone),
		target_rpe_min: num(o.target_rpe_min),
		target_rpe_max: num(o.target_rpe_max),
	};
}

function parseWeek(v: unknown): SharedPlanWeek | null {
	const o = obj(v);
	const index = num(o?.week_index);
	if (!o || index == null) return null;
	const workouts = Array.isArray(o.workouts) ? o.workouts : [];
	return {
		week_index: index,
		phase: str(o.phase),
		target_volume_m: num(o.target_volume_m),
		workouts: workouts.map(parseWorkout).filter((w): w is SharedPlanWorkout => w !== null),
	};
}

/// The RPC's jsonb document as a typed plan, or null when it is not the shape
/// the migration builds. Reads only the documented keys, so a key the RPC
/// gained later never reaches the page or the unfurl.
export function parseSharedPlan(v: unknown): SharedPlan | null {
	const o = obj(v);
	const id = str(o?.id);
	const name = str(o?.name);
	const goalEvent = str(o?.goal_event);
	const goalDistance = num(o?.goal_distance_m);
	const days = num(o?.days_per_week);
	if (!o || !id || name == null || !goalEvent || goalDistance == null || days == null) {
		return null;
	}
	const author = obj(o.author);
	const weeks = Array.isArray(o.weeks) ? o.weeks : [];
	return {
		id,
		name,
		goal_event: goalEvent,
		goal_distance_m: goalDistance,
		days_per_week: days,
		author: author ? { name: str(author.name), handle: str(author.handle) } : null,
		weeks: weeks
			.map(parseWeek)
			.filter((w): w is SharedPlanWeek => w !== null)
			.sort((a, b) => a.week_index - b.week_index),
	};
}

/// Fetch a public plan through the redacted share view. Returns `{ plan: null }`
/// when config is missing, the id is malformed, the plan is not public, the
/// gate is closed, or the fetch fails.
export async function lookupSharedPlan(
	id: string,
	config: SharedPlanLookupConfig | null,
	makeClient: (url: string, key: string) => SupabaseClient = (url, key) =>
		createClient(url, key, { auth: { persistSession: false } }),
): Promise<{ plan: SharedPlan | null }> {
	if (!config?.supabaseUrl || !config?.supabaseAnonKey) return { plan: null };
	// A non-uuid argument raises 22P02, which PostgREST returns as an error —
	// indistinguishable here from an outage — so reject it before calling.
	if (!isEntityId(id)) return { plan: null };
	try {
		const supabase = makeClient(config.supabaseUrl, config.supabaseAnonKey);
		const { data, error } = await supabase.rpc('public_plan_share', { p_id: id }, { get: true });
		// A clean null is "not public / gate closed"; an error is Supabase being
		// unreachable, tagged for the share-plan-upstream-unreachable alarm.
		if (error) {
			console.error('[share-plan] upstream_unreachable');
			return { plan: null };
		}
		return { plan: parseSharedPlan(data) };
	} catch (err) {
		console.error('[share-plan] upstream_unreachable', thrownMessage(err));
		return { plan: null };
	}
}

import { thrownMessage } from './supabase_error';
// Versioned AI-disclosure consent — the gate every endpoint that ships a
// user's data to Anthropic runs before it fans out. GDPR Art 6(1)(a).
//
// The consent record is `user_profiles.ai_disclosure_version` (which
// disclosure was accepted) paired with `coach_consent_at` (when). Neither
// is in the public-safe column grant, so the record is read through the
// SECURITY DEFINER `get_my_profile()` RPC and written only by
// `record_ai_disclosure_consent()` (migration 20270511_001).
//
// Versions are a monotone ladder — each one is a strict superset of the
// last — which is what makes "accepted >= required" sound:
//
//   1  AI Coach only.
//   2  The Coach plus the AI route assistant.
//   3  v2 plus the AI plan assistant (the typed plan description, sent
//      only to extract plan-wizard settings).
//   4  v3 plus AI plan edits (the active plan's upcoming workouts and the
//      typed change request, sent only to propose edits the runner
//      reviews before anything is saved).
//   5  All AI features: v4 plus the plate-photo logger (one meal photo,
//      sent only to propose food-log rows the runner edits before saving).
//
// Every AI endpoint declares its minimum. Adding the next AI feature means
// a new version with new copy, not a new boolean column and not quietly
// widening what an existing acceptance covers.
//
// This module lives outside `#lib/coach` on purpose: the route-AI handlers
// need it, and importing from the coach barrel drags the Anthropic SDK
// into bundles that have no business carrying it.

/** Minimum disclosure version /api/coach requires. */
export const AI_DISCLOSURE_VERSION_COACH = 1;

/**
 * Minimum disclosure version the AI route assistant requires
 * (/api/coach/route-describe + /api/coach/route-request). Higher than the
 * Coach's because the route endpoints send a different payload — the typed
 * request text and a coarse location label — for a different purpose than
 * the Coach copy described.
 */
export const AI_DISCLOSURE_VERSION_ROUTE_AI = 2;

/**
 * Minimum disclosure version /api/coach/plan-request requires. Its own rung
 * because it sends the typed plan description (goal race, target and recent
 * times, training days) to extract plan-wizard settings — a payload and
 * purpose neither the Coach nor the route copy described.
 */
export const AI_DISCLOSURE_VERSION_PLAN_AI = 3;

/**
 * Minimum disclosure version /api/coach/plan-edit requires. Its own rung even
 * though the v1 Coach copy already names the active plan: the Coach sends the
 * plan so it can comment on it, while plan edits send it with the runner's
 * change request so the model can propose changes to it — a new purpose
 * (decisions § 571).
 */
export const AI_DISCLOSURE_VERSION_PLAN_EDIT_AI = 4;

/**
 * Minimum disclosure version /api/coach/plate-photo requires. Its own rung
 * because it sends a photograph of the runner's meal — a payload that can
 * carry anything in frame — to estimate food_log rows, a purpose no earlier
 * copy described (decisions § 1972). Rung 4 belongs to AI plan edits.
 */
export const AI_DISCLOSURE_VERSION_FOOD_PHOTO_AI = 5;

/**
 * The newest disclosure this build knows how to present. Must equal the
 * SQL `ai_disclosure_current_version()`; `ai_disclosure.test.ts` reads the
 * newest migration that defines it and fails if they drift.
 */
export const AI_DISCLOSURE_CURRENT_VERSION = AI_DISCLOSURE_VERSION_FOOD_PHOTO_AI;

/**
 * Where every AI feature sends a runner its endpoint refused for consent.
 * Settings → Account records the disclosure from every state — never
 * accepted, withdrawn, or accepted at an older version — while /coach only
 * asks a runner with no record at all, so a stale acceptance sent there would
 * land in a working chat with nothing to accept.
 */
export const AI_CONSENT_HREF = '/settings/account#ai-consent';

/**
 * Machine-readable marker on every AI-consent denial. It rides a `code`
 * field rather than `error` because the three endpoints already use `error`
 * for their own (differently-shaped) strings — clients branch on `code`.
 */
export const AI_DISCLOSURE_ERROR = 'ai_disclosure_required';

/**
 * - `missing` — nothing on record (never accepted, or withdrawn).
 * - `stale`   — accepted an older disclosure that did not cover this use.
 * - `unknown` — the record is unreadable or names a version this build
 *               cannot describe. Denied rather than trusted: a disclosure
 *               we cannot render is a disclosure we cannot prove was made.
 */
export type AiDisclosureDenial = 'missing' | 'stale' | 'unknown';

export interface AiDisclosureRecord {
	version: unknown;
	acceptedAt: unknown;
}

export type AiDisclosureCheck =
	| { ok: true; version: number }
	| { ok: false; reason: AiDisclosureDenial };

/** Pull the consent record out of a `get_my_profile()` row of unknown shape. */
export function aiDisclosureFromProfileRow(row: unknown): AiDisclosureRecord {
	if (!row || typeof row !== 'object') return { version: null, acceptedAt: null };
	const o = row as Record<string, unknown>;
	return { version: o.ai_disclosure_version, acceptedAt: o.coach_consent_at };
}

/** Fail-closed: anything that is not a complete, known, sufficient record denies. */
export function checkAiDisclosure(
	record: AiDisclosureRecord,
	requiredVersion: number,
): AiDisclosureCheck {
	const acceptedAt = record.acceptedAt;
	const hasAcceptedAt = typeof acceptedAt === 'string' && acceptedAt.length > 0;
	if (record.version == null || !hasAcceptedAt) return { ok: false, reason: 'missing' };
	const version = record.version;
	if (typeof version !== 'number' || !Number.isInteger(version)) {
		return { ok: false, reason: 'unknown' };
	}
	if (version < 1 || version > AI_DISCLOSURE_CURRENT_VERSION) {
		return { ok: false, reason: 'unknown' };
	}
	if (version < requiredVersion) return { ok: false, reason: 'stale' };
	return { ok: true, version };
}

/** Fields every AI endpoint merges into its 403 so clients can prompt, not just fail. */
export function aiDisclosureDenialBody(requiredVersion: number): Record<string, unknown> {
	return { code: AI_DISCLOSURE_ERROR, required_version: requiredVersion };
}

/// `PromiseLike`, not `Promise`: PostgREST's `.maybeSingle()` returns a
/// thenable builder, and a handler should be able to hand it over as-is.
type ProfileLookup = () => PromiseLike<{
	data: unknown;
	error: { code?: string; message?: string } | null;
}>;

export type AiDisclosureGate =
	| { ok: true; version: number }
	| { ok: false; status: 500; reason: 'lookup_failed' }
	| { ok: false; status: 403; reason: AiDisclosureDenial };

/**
 * Load the caller's consent record and grade it. Takes the loader rather
 * than the Supabase client so a handler can pass
 * `() => supabase.rpc('get_my_profile', undefined, { get: true }).maybeSingle()` and a test can pass
 * a stub without standing up a client.
 */
export async function gateAiDisclosure(
	loadProfile: ProfileLookup,
	requiredVersion: number,
	logTag: string,
): Promise<AiDisclosureGate> {
	let res: Awaited<ReturnType<ProfileLookup>>;
	try {
		res = await loadProfile();
	} catch (e) {
		console.error(`[${logTag}] ai disclosure lookup threw`, {
			message: thrownMessage(e),
		});
		return { ok: false, status: 500, reason: 'lookup_failed' };
	}
	if (res.error) {
		console.error(`[${logTag}] ai disclosure lookup failed`, {
			code: res.error.code,
			message: res.error.message,
		});
		return { ok: false, status: 500, reason: 'lookup_failed' };
	}
	const check = checkAiDisclosure(aiDisclosureFromProfileRow(res.data), requiredVersion);
	if (!check.ok) {
		// `unknown` means the stored version is outside this build's ladder —
		// a corrupt record or a deployment lagging the database. It denies
		// like the others, but an operator needs to be able to tell them
		// apart, so the reason is on the log line.
		console.error(`[${logTag}] ai disclosure denied`, {
			reason: check.reason,
			required_version: requiredVersion,
		});
		return { ok: false, status: 403, reason: check.reason };
	}
	return check;
}

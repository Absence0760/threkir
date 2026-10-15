// Network glue for the plan wizard's "Describe the plan you want" box. It
// posts the runner's description to /api/coach/plan-request and resolves to
// validated `PlanRequestInputs` the wizard fills its own fields from. The AI is
// the interface, never the planner: the generator builds the plan from those
// fields exactly as it does for a hand-filled form.
//
// The manual wizard is the fallback, so every non-200 throws a typed
// `PlanRequestError` and the caller keeps the form working. Refreshes the JWT
// once on a 401, mirroring route_request_client.

import { supabase } from '../core/supabase';
import { AI_DISCLOSURE_ERROR } from '../core/ai_disclosure';
import { payloadSha256Hex } from '../util/payload_hash';
import type { PlanRequestInputs } from './plan_request/inputs';

export type { PlanRequestInputs, PlanRequestAssumption } from './plan_request/inputs';

export type PlanRequestErrorKind =
	| 'not_authenticated'
	| 'consent'
	| 'daily_limit'
	| 'invalid'
	| 'not_understood'
	| 'unavailable';

export class PlanRequestError extends Error {
	kind: PlanRequestErrorKind;
	constructor(kind: PlanRequestErrorKind, message?: string) {
		super(message ?? kind);
		this.name = 'PlanRequestError';
		this.kind = kind;
	}
}

export function planRequestErrorKind(status: number, code: string | undefined): PlanRequestErrorKind {
	if (status === 401) return 'not_authenticated';
	if (status === 403 && code === AI_DISCLOSURE_ERROR) return 'consent';
	if (status === 429) return 'daily_limit';
	if (status === 400) return 'invalid';
	if (status === 422) return 'not_understood';
	return 'unavailable';
}

/**
 * Extract plan-wizard inputs from a plain-English description. `todayIso` is
 * the runner's calendar day, so relative dates resolve against it; the server
 * only trusts it within a day of its own.
 */
export async function requestPlanInputs(
	request: string,
	todayIso: string,
): Promise<PlanRequestInputs> {
	const body = JSON.stringify({ request, today: todayIso });
	// CloudFront's Lambda OAC can't hash the body itself — the client
	// supplies the sigv4 payload hash or the Function URL 403s (#590).
	const bodyHash = await payloadSha256Hex(body);
	const post = (token: string) =>
		fetch('/api/coach/plan-request', {
			method: 'POST',
			headers: {
				'content-type': 'application/json',
				'X-Supabase-Authorization': `Bearer ${token}`,
				'x-amz-content-sha256': bodyHash,
			},
			body,
		});

	let token = (await supabase.auth.getSession()).data.session?.access_token;
	if (!token) throw new PlanRequestError('not_authenticated');

	let res = await post(token);
	if (res.status === 401) {
		try {
			const refreshed = await supabase.auth.refreshSession();
			token = refreshed.data.session?.access_token ?? token;
			res = await post(token);
		} catch (_) {
			/* fall through to the status check below */
		}
	}

	if (!res.ok) {
		const errBody = (await res.json().catch(() => null)) as { code?: string } | null;
		throw new PlanRequestError(planRequestErrorKind(res.status, errBody?.code));
	}

	const data = (await res.json().catch(() => null)) as { inputs?: PlanRequestInputs } | null;
	if (!data || typeof data.inputs !== 'object' || data.inputs === null) {
		throw new PlanRequestError('unavailable');
	}
	return data.inputs;
}

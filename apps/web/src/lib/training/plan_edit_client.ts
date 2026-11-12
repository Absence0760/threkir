// Network glue for "Adjust with AI" on /plans/[id]. It posts the plan id and
// the runner's change request to /api/coach/plan-edit and resolves to the
// server-validated operations, which the page applies with the deterministic
// plan helpers (plan_edit/apply.ts) and shows as a diff before anything is
// saved. The server reads the plan itself; the client never sends it.
//
// Every non-200 throws a typed `PlanEditError` so the page keeps the manual
// Adjust options working. Refreshes the JWT once on a 401, like
// plan_request_client.

import { supabase } from '../core/supabase';
import { AI_DISCLOSURE_ERROR } from '../core/ai_disclosure';
import { payloadSha256Hex } from '../util/payload_hash';
import type { PlanEditProposal } from './plan_edit/ops';

export type PlanEditErrorKind =
	| 'not_authenticated'
	| 'consent'
	| 'daily_limit'
	| 'invalid'
	| 'not_found'
	| 'nothing_to_adjust'
	| 'not_understood'
	| 'unavailable';

export class PlanEditError extends Error {
	kind: PlanEditErrorKind;
	constructor(kind: PlanEditErrorKind, message?: string) {
		super(message ?? kind);
		this.name = 'PlanEditError';
		this.kind = kind;
	}
}

export function planEditErrorKind(status: number, code: string | undefined): PlanEditErrorKind {
	if (status === 401) return 'not_authenticated';
	if (status === 403 && code === AI_DISCLOSURE_ERROR) return 'consent';
	if (status === 429) return 'daily_limit';
	if (status === 400) return 'invalid';
	if (status === 404) return 'not_found';
	if (status === 409) return 'nothing_to_adjust';
	if (status === 422) return 'not_understood';
	return 'unavailable';
}

export async function requestPlanEdits(
	planId: string,
	request: string,
	todayIso: string,
): Promise<PlanEditProposal> {
	const body = JSON.stringify({ plan_id: planId, request, today: todayIso });
	// CloudFront's Lambda OAC can't hash the body itself — the client
	// supplies the sigv4 payload hash or the Function URL 403s (#590).
	const bodyHash = await payloadSha256Hex(body);
	const post = (token: string) =>
		fetch('/api/coach/plan-edit', {
			method: 'POST',
			headers: {
				'content-type': 'application/json',
				'X-Supabase-Authorization': `Bearer ${token}`,
				'x-amz-content-sha256': bodyHash,
			},
			body,
		});

	let token = (await supabase.auth.getSession()).data.session?.access_token;
	if (!token) throw new PlanEditError('not_authenticated');

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
		throw new PlanEditError(planEditErrorKind(res.status, errBody?.code));
	}

	const data = (await res.json().catch(() => null)) as Partial<PlanEditProposal> | null;
	if (!data || !Array.isArray(data.ops)) throw new PlanEditError('unavailable');
	return {
		ops: data.ops,
		dropped: typeof data.dropped === 'number' ? data.dropped : 0,
		notes: Array.isArray(data.notes) ? data.notes : [],
	};
}

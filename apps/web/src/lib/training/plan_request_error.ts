// The typed failure both AI planner boxes throw — the single-race plan
// assistant (`plan_request_client`) and the season request
// (`season_request_client`) — and the one status-to-kind mapping they share.
// Kept apart from the clients so it carries no Supabase import and the
// transport around it is unit-testable.

import { AI_DISCLOSURE_ERROR } from '../core/ai_disclosure';

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

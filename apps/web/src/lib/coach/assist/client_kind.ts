// How the coach assistant panel reads each refusal of /api/coach/assist.
// Kept apart from client.ts so it can be unit-tested without a browser client.

import { AI_DISCLOSURE_ERROR } from '../../core/ai_disclosure';
import { ATHLETE_CONSENT_REQUIRED } from './handler_codes';

export type CoachAssistErrorKind =
	| 'not_authenticated'
	| 'coach_consent'
	| 'athlete_consent'
	| 'upgrade'
	| 'rate_limited'
	| 'not_your_athlete'
	| 'unavailable';

export class CoachAssistError extends Error {
	kind: CoachAssistErrorKind;
	constructor(kind: CoachAssistErrorKind) {
		super(kind);
		this.name = 'CoachAssistError';
		this.kind = kind;
	}
}

export function coachAssistErrorKind(
	status: number,
	body: { code?: unknown; upgrade?: unknown } | null,
): CoachAssistErrorKind {
	if (status === 401) return 'not_authenticated';
	if (status === 403 && body?.code === AI_DISCLOSURE_ERROR) return 'coach_consent';
	if (status === 403 && body?.code === ATHLETE_CONSENT_REQUIRED) return 'athlete_consent';
	if (status === 403 && body?.upgrade === true) return 'upgrade';
	if (status === 403) return 'not_your_athlete';
	if (status === 429) return 'rate_limited';
	return 'unavailable';
}

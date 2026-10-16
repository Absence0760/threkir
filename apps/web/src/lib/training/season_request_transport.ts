// The season request's transport, with its session and fetch injected so it
// is unit-testable without a browser Supabase client. `season_request_client`
// binds it to the real ones. Same body shape, headers, status-to-kind mapping
// and single 401 refresh-and-replay as `plan_request_client`.

import { payloadSha256Hex } from '../util/payload_hash';
import { PlanRequestError, planRequestErrorKind } from './plan_request_error';
import {
	MAX_SEASON_RACES,
	MAX_SEASON_RACE_DISTANCE_M,
	MIN_SEASON_RACE_DISTANCE_M,
	SEASON_REQUEST_ASSUMPTIONS,
} from './season_request/races';
import type { SeasonRace, SeasonRequestResult } from './season_types';

export const SEASON_REQUEST_PATH = '/api/coach/season-request';

export interface SeasonRequestDeps {
	fetch: (url: string, init: RequestInit) => Promise<Response>;
	currentToken: () => Promise<string | null | undefined>;
	refreshToken: () => Promise<string | null | undefined>;
}

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
const KNOWN_ASSUMPTIONS: ReadonlySet<string> = new Set(SEASON_REQUEST_ASSUMPTIONS);

function parseRace(raw: unknown): SeasonRace | null {
	if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
	const o = raw as Record<string, unknown>;
	const { name, date, distanceM, priority, goalTimeSec } = o;
	if (typeof name !== 'string' || name.trim().length === 0) return null;
	if (typeof date !== 'string' || !ISO_DATE.test(date)) return null;
	if (
		typeof distanceM !== 'number' ||
		!Number.isFinite(distanceM) ||
		distanceM < MIN_SEASON_RACE_DISTANCE_M ||
		distanceM > MAX_SEASON_RACE_DISTANCE_M
	) {
		return null;
	}
	if (priority !== 'A' && priority !== 'B' && priority !== 'C') return null;
	if (goalTimeSec !== null && (typeof goalTimeSec !== 'number' || !Number.isInteger(goalTimeSec) || goalTimeSec <= 0)) {
		return null;
	}
	return { name, date, distanceM, priority, goalTimeSec };
}

/// Parse the endpoint's 200 body. The server already validates every race,
/// so anything outside that contract — a malformed race, more races than the
/// cap, an assumption this build cannot explain — means the two halves
/// disagree, and the whole answer is refused rather than partly shown.
export function parseSeasonRequestResult(raw: unknown): SeasonRequestResult | null {
	if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
	const { races, assumptions } = raw as Record<string, unknown>;
	if (!Array.isArray(races) || races.length > MAX_SEASON_RACES) return null;
	if (!Array.isArray(assumptions)) return null;
	const parsed: SeasonRace[] = [];
	for (const r of races) {
		const race = parseRace(r);
		if (!race) return null;
		parsed.push(race);
	}
	for (const a of assumptions) {
		if (typeof a !== 'string' || !KNOWN_ASSUMPTIONS.has(a)) return null;
	}
	return { races: parsed, assumptions: assumptions as string[] };
}

export async function sendSeasonRequest(
	request: string,
	todayIso: string,
	deps: SeasonRequestDeps,
): Promise<SeasonRequestResult> {
	const body = JSON.stringify({ request, today: todayIso });
	// CloudFront's Lambda OAC can't hash the body itself — the client
	// supplies the sigv4 payload hash or the Function URL 403s (#590).
	const bodyHash = await payloadSha256Hex(body);
	const post = (token: string) =>
		deps.fetch(SEASON_REQUEST_PATH, {
			method: 'POST',
			headers: {
				'content-type': 'application/json',
				'X-Supabase-Authorization': `Bearer ${token}`,
				'x-amz-content-sha256': bodyHash,
			},
			body,
		});

	let token: string | null | undefined;
	try {
		token = await deps.currentToken();
	} catch (_) {
		token = null;
	}
	if (!token) throw new PlanRequestError('not_authenticated');

	let res: Response;
	try {
		res = await post(token);
		if (res.status === 401) {
			try {
				const refreshed = await deps.refreshToken();
				if (refreshed) res = await post(refreshed);
			} catch (_) {
				/* fall through to the status check below */
			}
		}
	} catch (_) {
		throw new PlanRequestError('unavailable');
	}

	if (!res.ok) {
		const errBody = (await res.json().catch(() => null)) as { code?: string } | null;
		throw new PlanRequestError(planRequestErrorKind(res.status, errBody?.code));
	}

	const result = parseSeasonRequestResult(await res.json().catch(() => null));
	if (!result) throw new PlanRequestError('unavailable');
	return result;
}

// Network glue for the season planner's "Describe your season" box: posts the
// runner's description to /api/coach/season-request and resolves to the races
// found in it, for the runner to confirm before anything is generated. The AI
// is the interface, never the planner (decisions.md §12).
//
// Every failure throws a typed `PlanRequestError` (the plan assistant's kinds),
// so the caller can fall back to entering the races by hand. Each assumption
// key renders through `seasonAssumptionMessageKey` (season_request_labels).

import { supabase } from '../core/supabase';
import { sendSeasonRequest } from './season_request_transport';
import type { SeasonRequestResult } from './season_types';

export { PlanRequestError, type PlanRequestErrorKind } from './plan_request_error';
export { seasonAssumptionMessageKey } from './season_request_labels';

/**
 * Extract the races from a plain-English season description. `todayIso` is
 * the runner's calendar day, so relative and year-less dates resolve against
 * it; the server only trusts it within a day of its own.
 */
export async function requestSeasonRaces(
	request: string,
	todayIso: string,
): Promise<SeasonRequestResult> {
	return sendSeasonRequest(request, todayIso, {
		fetch: (url, init) => fetch(url, init),
		currentToken: async () => (await supabase.auth.getSession()).data.session?.access_token,
		refreshToken: async () => (await supabase.auth.refreshSession()).data.session?.access_token,
	});
}

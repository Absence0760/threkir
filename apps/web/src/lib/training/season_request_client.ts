// Network glue for the season planner's "Describe your season" box: posts the
// runner's description and resolves to the races found in it, for the runner
// to confirm before anything is generated.

import { PlanRequestError } from './plan_request_client';
import type { SeasonRequestResult } from './season_types';

export async function requestSeasonRaces(
	request: string,
	todayIso: string,
): Promise<SeasonRequestResult> {
	void request;
	void todayIso;
	throw new PlanRequestError('unavailable');
}

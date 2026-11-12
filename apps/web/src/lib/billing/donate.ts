import { PUBLIC_DONATE_URL } from '$app/env/public';

import { donateUrlProblem } from './donate_link';

/// The donation link this build may show, or null. Fail-closed: an unset link
/// and a malformed one both hide every donate affordance, so no build can send
/// a donor to a placeholder page again.
export function donateUrl(): string | null {
	const url = (PUBLIC_DONATE_URL ?? '').trim();
	return donateUrlProblem(url) === null ? url : null;
}

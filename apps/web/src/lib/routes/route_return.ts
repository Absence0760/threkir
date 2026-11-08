import { safeReturnTo } from '../core/safe_redirect';

/// The route builder's `?return=` round trip: a form that wants a route it
/// doesn't have yet (the run editor's empty route picker) links to
/// `/routes/new?return=<its own path>`, and the builder sends the saved
/// route back there as `?route=<id>` instead of opening the route's page.
/// `?return=` is read off an attacker-controllable URL, so it goes through
/// `safeReturnTo` and an off-origin target is dropped, not followed.

export const RETURN_PARAM = 'return';
export const SAVED_ROUTE_PARAM = 'route';

export function newRouteHref(returnTo: string): string {
	return `/routes/new?${new URLSearchParams({ [RETURN_PARAM]: returnTo })}`;
}

export function savedRouteDestination(
	rawReturn: string | null | undefined,
	routeId: string,
): string | null {
	const safe = safeReturnTo(rawReturn, '');
	if (!safe) return null;
	const url = new URL(safe, 'https://internal.invalid');
	url.searchParams.set(SAVED_ROUTE_PARAM, routeId);
	return `${url.pathname}${url.search}${url.hash}`;
}

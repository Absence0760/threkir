import type { MessageKey } from '../i18n/messages';

/// One row of `route_delete_impact` (migration 20271106000001): what deleting
/// a route takes with it or detaches. "Others" counts leave out the caller's
/// own rows, since the owner is not owed a warning about their own bookmark.
export interface RouteDeleteImpact {
	saved_by_others: number;
	reviews_by_others: number;
	conditions_by_others: number;
	segments_by_others: number;
	segment_efforts_by_others: number;
	shares: number;
	race_listings: number;
	events: number;
	linked_runs: number;
	photos: number;
	markers: number;
}

export interface RouteDeleteImpactLine {
	key: MessageKey;
	count: number;
}

/// The sentences the delete confirm adds below its body, in the order the
/// owner should read them: other people's things that depend on the route
/// first, then what of the owner's own goes with it. Zero counts say nothing.
export function routeDeleteImpactLines(
	impact: RouteDeleteImpact,
	isPublic: boolean,
): RouteDeleteImpactLine[] {
	const lines: RouteDeleteImpactLine[] = [];
	const add = (key: MessageKey, count: number) => {
		if (count > 0) lines.push({ key, count });
	};
	if (isPublic) lines.push({ key: 'routeDetail.deleteImpact.public', count: 1 });
	add('routeDetail.deleteImpact.raceListings', impact.race_listings);
	add('routeDetail.deleteImpact.events', impact.events);
	add('routeDetail.deleteImpact.saved', impact.saved_by_others);
	add('routeDetail.deleteImpact.shares', impact.shares);
	add('routeDetail.deleteImpact.segments', impact.segments_by_others);
	add('routeDetail.deleteImpact.efforts', impact.segment_efforts_by_others);
	add('routeDetail.deleteImpact.reviews', impact.reviews_by_others);
	add('routeDetail.deleteImpact.conditions', impact.conditions_by_others);
	add('routeDetail.deleteImpact.runs', impact.linked_runs);
	add('routeDetail.deleteImpact.photos', impact.photos);
	add('routeDetail.deleteImpact.markers', impact.markers);
	return lines;
}

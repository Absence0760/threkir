/// What Races & courses shows (`/races?show=`): both sections, the race
/// calendar alone, or the park courses alone. No parameter, or one this list
/// does not hold, is both, so an old or mistyped link still opens the page.
export const RACES_SHOWS = ['all', 'races', 'courses'] as const;
export type RacesShow = (typeof RACES_SHOWS)[number];

export function parseRacesShow(raw: unknown): RacesShow {
	return typeof raw === 'string' && (RACES_SHOWS as readonly string[]).includes(raw)
		? (raw as RacesShow)
		: 'all';
}

/// `search` with `show` set, every other parameter kept. All is the page with
/// no parameter, so it removes `show` rather than writing `show=all`.
export function racesShowSearch(search: string, show: RacesShow): string {
	const params = new URLSearchParams(search);
	if (show === 'all') params.delete('show');
	else params.set('show', show);
	const rest = params.toString();
	return rest ? `?${rest}` : '';
}

/// How many park courses the courses section lists: a short list under the
/// race calendar, every course when the courses are all the page shows.
export const ANY_TIME_LIMIT = 8;

export function anyTimeCourseLimit(show: RacesShow): number | null {
	return show === 'courses' ? null : ANY_TIME_LIMIT;
}

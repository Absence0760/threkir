/**
 * Where a page's back link goes and what it says, from the in-app address the
 * reader left to reach it. Pure, so it is tested without a browser;
 * `referrer_back.svelte.ts` feeds it the departure `nav_departure.ts` records.
 *
 * The departure is the address bar as it read when the reader left, search
 * included, so a page that keeps its state in a shallow `?show=` (Races &
 * courses) comes back with it. A departure that is the page itself, or one
 * of its own children (a park's course pages), is no referrer: the reader is
 * coming back down, and the page keeps the fallback.
 */

/** What the back link names. Each one is a catalogue key the page renders. */
export type BackPlace = 'races' | 'parks' | 'previous';

export interface BackTarget {
	href: string;
	place: BackPlace;
}

/** The labels, by place: what the reader sees after the arrow. */
export const BACK_PLACE_KEY = {
	races: 'races.pageTitle',
	parks: 'parks.backToParks',
	previous: 'common.back',
} as const satisfies Record<BackPlace, string>;

function placeOf(pathname: string): BackPlace {
	if (pathname === '/races') return 'races';
	if (pathname === '/parks') return 'parks';
	return 'previous';
}

/** An in-app path, or null for anything that could leave the site. */
function inAppPath(href: string | null | undefined): URL | null {
	if (!href || !href.startsWith('/') || href.startsWith('//') || href.startsWith('/\\')) return null;
	try {
		return new URL(href, 'https://app.invalid');
	} catch {
		return null;
	}
}

/**
 * The back target for the page at `herePath`, given the address the reader
 * left (`departure`, path plus search) and the page's own `fallback` for a
 * reader with no in-app history: a shared link, a fresh tab, a reload.
 */
export function backTargetFrom(
	departure: string | null | undefined,
	herePath: string,
	fallback: BackTarget,
): BackTarget {
	const from = inAppPath(departure);
	if (!from) return fallback;
	const here = herePath.replace(/\/+$/, '') || '/';
	const path = from.pathname.replace(/\/+$/, '') || '/';
	if (path === here || path.startsWith(`${here}/`)) return fallback;
	return { href: `${path}${from.search}`, place: placeOf(path) };
}

/** Whether a value read back out of history state is a back target. */
export function isBackTarget(v: unknown): v is BackTarget {
	if (v === null || typeof v !== 'object') return false;
	const t = v as Record<string, unknown>;
	return (
		typeof t.href === 'string' &&
		inAppPath(t.href) !== null &&
		typeof t.place === 'string' &&
		Object.hasOwn(BACK_PLACE_KEY, t.place)
	);
}

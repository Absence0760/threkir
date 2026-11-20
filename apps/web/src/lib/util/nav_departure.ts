import { beforeNavigate } from '$app/navigation';

/**
 * The address the reader last left inside the app, as the address bar read
 * it: path plus search, so a shallow `?show=` or `?course=` the page wrote
 * without a navigation is part of it. SvelteKit's own `from.url` is the last
 * real navigation's address and misses those (decisions § 2588).
 *
 * The root layout calls `trackDepartures` once; `referrer_back.svelte.ts`
 * reads `lastDeparture` when the next page arrives.
 */
let last: string | null = null;

export function trackDepartures(): void {
	beforeNavigate(() => {
		last = `${location.pathname}${location.search}`;
	});
}

export function lastDeparture(): string | null {
	return last;
}

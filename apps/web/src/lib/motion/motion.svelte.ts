import { browser } from '$app/env';

// Whether the public pages may move right now: the OS reduced-motion setting,
// read live. There is no in-page pause. Every animation on those pages settles
// within five seconds of starting, which WCAG 2.2.2 does not ask to be
// pausable (decisions § 1907).

let reduced = $state(false);

if (browser) {
	const query = window.matchMedia?.('(prefers-reduced-motion: reduce)');
	if (query) {
		reduced = query.matches;
		query.addEventListener?.('change', (event) => {
			reduced = event.matches;
		});
	}
}

export const motion = {
	get reduced(): boolean {
		return reduced;
	},
};

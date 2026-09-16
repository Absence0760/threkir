import { browser } from '$app/environment';

// Whether the public pages may move right now. Two inputs: the OS setting,
// which is authoritative and live, and the in-page pause, which WCAG 2.2.2
// requires for any motion that starts on its own and runs past five seconds.
//
// The pause is not persisted. It is a per-visit control, not a preference: the
// durable "never animate" choice is the OS reduced-motion setting, which this
// already honours, and a stored flag would be one more registry entry
// (docs/backend/settings.md) standing in for it.
//
// Paused state is mirrored onto <html data-motion="paused"> so the stylesheet
// can stop CSS animations inside `.motion-scope` without every component
// subscribing to this store.

let paused = $state(false);
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
	get paused(): boolean {
		return paused;
	},
	get reduced(): boolean {
		return reduced;
	},
	/// True when nothing should start moving: the visitor paused, or asked
	/// the OS for reduced motion.
	get still(): boolean {
		return paused || reduced;
	},
	setPaused(next: boolean) {
		paused = next;
		if (!browser) return;
		if (next) document.documentElement.dataset.motion = 'paused';
		else delete document.documentElement.dataset.motion;
	},
};

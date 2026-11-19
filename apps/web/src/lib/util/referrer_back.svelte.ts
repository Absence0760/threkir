import { afterNavigate, goto } from '$app/navigation';
import { page } from '$app/state';
import { lastDeparture } from './nav_departure.ts';
import { backTargetFrom, isBackTarget, type BackTarget } from './back_target.ts';

/**
 * A back link that returns to the page the reader came from in the app, and
 * names it: Races & courses with its `?show=` kept, the parks index, or plain
 * Back. With no in-app history (a shared link, a fresh tab) it is the page's
 * `fallback` parent. The link stays a real `<a href>`, so it opens in a new
 * tab and works before the script runs; `handle` pops history instead when
 * the target is the entry behind this one, which brings that page back with
 * its scroll and filters.
 *
 * The target is saved in this history entry's state, so coming back down
 * from a child page (a course, then back to its park) keeps it, and a reload
 * does too (`persistState`). Pages that write their own shallow state pass
 * `page.state` along so the saved target survives.
 *
 * Call once during component init, like `smartBack`.
 */
export function referrerBack(fallback: BackTarget): {
	readonly href: string;
	readonly place: BackTarget['place'];
	handle: (e: MouseEvent) => void;
} {
	let target = $state<BackTarget>(fallback);
	let pop = false;

	afterNavigate((nav) => {
		if (nav.shallow) return;
		const saved = page.state.back;
		if ((nav.type === 'popstate' || nav.type === 'enter') && saved && isBackTarget(saved.target)) {
			target = saved.target;
			pop = nav.type === 'popstate' && saved.pop === true;
			return;
		}
		const computed =
			nav.type === 'enter' ? fallback : backTargetFrom(lastDeparture(), page.url.pathname, fallback);
		target = computed;
		pop = computed !== fallback;
		const shown = page.shallow?.url ?? page.url;
		void goto(`${shown.pathname}${shown.search}${shown.hash}`, {
			shallow: true,
			replace: true,
			persistState: true,
			state: { ...page.state, back: { target: computed, pop } },
		});
	});

	return {
		get href() {
			return target.href;
		},
		get place() {
			return target.place;
		},
		handle(e: MouseEvent) {
			if (!pop || e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
			e.preventDefault();
			history.back();
		},
	};
}

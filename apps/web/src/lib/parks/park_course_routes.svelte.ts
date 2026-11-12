import { SvelteMap } from 'svelte/reactivity';
import { fetchParkCourseRouteIds } from '#lib/core/data.ts';

/**
 * Which official routes are a park course's route, for the Official badge:
 * on a park course it must read "Official Threkir course", never just
 * "Official", or it reads as the park's own. `known` is false until the
 * route was checked, so a surface shows no badge rather than the short one
 * while it waits. A failed read marks the routes checked and not park
 * courses, so a lost lookup never hides the badge on every official route.
 */
export class ParkCourseRouteLookup {
	#parkCourse = new SvelteMap<string, boolean>();
	#inFlight = new Set<string>();

	known(routeId: string): boolean {
		return this.#parkCourse.has(routeId);
	}

	isParkCourse(routeId: string): boolean {
		return this.#parkCourse.get(routeId) === true;
	}

	async check(routeIds: readonly string[]): Promise<void> {
		const ids = [...new Set(routeIds)].filter((id) => !this.#parkCourse.has(id) && !this.#inFlight.has(id));
		if (ids.length === 0) return;
		for (const id of ids) this.#inFlight.add(id);
		let found: Set<string>;
		try {
			found = await fetchParkCourseRouteIds(ids);
		} catch (e) {
			console.warn('park course route lookup failed', e);
			found = new Set();
		} finally {
			for (const id of ids) this.#inFlight.delete(id);
		}
		for (const id of ids) this.#parkCourse.set(id, found.has(id));
	}
}

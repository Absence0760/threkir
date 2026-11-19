/**
 * The place half of the one search on the Courses view of Races & courses
 * (`/races?show=courses`). The search matches parks and courses by name from
 * the list already on the page; places are looked up beside it and OFFERED as
 * "Courses near …" rows, never applied on their own, because a short word
 * such as "belle" is far more often a park the runner is typing than a town
 * (decisions § 2591).
 */

import { haversineMetres } from '../runs/run_stats.ts';
import type { PlaceBias } from '../routes/geocoding_math.ts';

type LatLng = { lat: number; lng: number };

/** Characters typed before places are looked up at all. */
export const PLACE_LOOKUP_MIN_CHARS = 3;

/** How many place rows the search offers. */
export const PLACE_SUGGESTION_LIMIT = 3;

/**
 * How far a place may be from the nearest course and still be offered. A
 * place with no course within reach cannot be what the runner meant, and
 * sorting every park by distance from it helps nobody: it is how "Belle"
 * once ordered the Virginia parks from a namesake 6,100 km away.
 */
export const PLACE_REACH_M = 1_000_000;

/**
 * The countries the lookup is held to: every country the catalogue has a
 * park in (the part of `US-VA` before the dash), plus the reader's own
 * region from their locale, so a visitor can still find their home town.
 */
export function placeSearchCountries(regionCodes: Iterable<string>, locale?: string | null): string[] {
	const out = new Set<string>();
	for (const code of regionCodes) {
		const country = code.split('-')[0]?.trim().toLowerCase();
		if (country && /^[a-z]{2}$/.test(country)) out.add(country);
	}
	const region = localeRegion(locale);
	if (region) out.add(region);
	return [...out].sort();
}

function localeRegion(locale?: string | null): string | null {
	if (!locale) return null;
	try {
		const region = new Intl.Locale(locale).maximize().region?.toLowerCase();
		return region && /^[a-z]{2}$/.test(region) ? region : null;
	} catch {
		return null;
	}
}

/** The mean of the course points, the place lookup's proximity hint. */
export function catalogueCentre(points: readonly LatLng[]): LatLng | null {
	if (points.length === 0) return null;
	let lat = 0;
	let lng = 0;
	for (const p of points) {
		lat += p.lat;
		lng += p.lng;
	}
	return { lat: lat / points.length, lng: lng / points.length };
}

/** The bias the Courses view looks places up with. */
export function coursePlaceBias(
	regionCodes: Iterable<string>,
	points: readonly LatLng[],
	locale?: string | null,
): PlaceBias {
	const countries = placeSearchCountries(regionCodes, locale);
	const proximity = catalogueCentre(points);
	return {
		...(countries.length > 0 ? { countries } : {}),
		...(proximity ? { proximity } : {}),
	};
}

/**
 * The places worth offering, in the provider's order: within `reachM` of at
 * least one course point, one per name, at most `limit`. With no points to
 * measure from, nothing is offered — there is nothing to sort.
 */
export function placesNearCourses<P extends LatLng & { name: string }>(
	places: readonly P[],
	points: readonly LatLng[],
	reachM = PLACE_REACH_M,
	limit = PLACE_SUGGESTION_LIMIT,
): P[] {
	const out: P[] = [];
	const names = new Set<string>();
	for (const place of places) {
		if (out.length >= limit) break;
		const key = place.name.trim().toLowerCase();
		if (names.has(key)) continue;
		const near = points.some((p) => haversineMetres(place.lat, place.lng, p.lat, p.lng) <= reachM);
		if (!near) continue;
		names.add(key);
		out.push(place);
	}
	return out;
}

/**
 * A place's name short enough for a row and a chip: its first two parts, so
 * "Belle Isle, Lancaster County, Virginia, United States" reads "Belle Isle,
 * Lancaster County". A name with no commas is kept whole, one with no words
 * is empty.
 */
export function placeLabel(name: string): string {
	const parts = name
		.split(',')
		.map((p) => p.trim())
		.filter((p) => p.length > 0);
	return parts.slice(0, 2).join(', ');
}

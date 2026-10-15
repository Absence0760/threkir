/**
 * The fuelling plan's URL inputs, validated. Both fuelling surfaces read them
 * from the address bar — the roadbook's `?carbs=` / `?fluid=` overrides and
 * `/nutrition/fuel`'s `?duration=` / `?carbs=` / `?fluid=` / `?heat=` — and the
 * Coach's fuelling handoff writes them (decisions § 1975), so a value here is
 * model output or a pasted link and is never trusted.
 *
 * A value outside its range is DROPPED, not clamped to the edge: a 9000 ml/h
 * link is not a request for the 3000 ml/h ceiling, and the page then falls back
 * to the runner's own saved rate. The rate ceilings are the ones Settings →
 * Training already enforces on the saved prefs, so a link can never ask for a
 * rate the runner could not have saved.
 */

export const FUEL_MAX_CARBS_PER_HOUR_G = 200;
export const FUEL_MAX_FLUID_PER_HOUR_ML = 3000;
/** Ten minutes: a shorter outing has nothing to fuel. */
export const FUEL_MIN_DURATION_S = 600;
/** Seven days: past the longest multi-day race the roadbook plans for. */
export const FUEL_MAX_DURATION_S = 604_800;

const DECIMAL = /^\d{1,6}(\.\d{1,3})?$/;
const WHOLE = /^\d{1,7}$/;

/**
 * A per-hour rate from the URL, or null. Only a plain non-negative decimal is
 * read (no sign, exponent, hex or whitespace tricks), rounded to a whole unit,
 * and refused above `max`.
 */
export function parseFuelRate(raw: string | null | undefined, max: number): number | null {
	if (raw == null || !DECIMAL.test(raw)) return null;
	const n = Math.round(Number(raw));
	return Number.isFinite(n) && n <= max ? n : null;
}

/** A duration in whole seconds from the URL, or null when outside the range. */
export function parseFuelDurationS(raw: string | null | undefined): number | null {
	if (raw == null || !WHOLE.test(raw)) return null;
	const n = Number(raw);
	return n >= FUEL_MIN_DURATION_S && n <= FUEL_MAX_DURATION_S ? n : null;
}

/**
 * A typed `H:MM` or `H:MM:SS` duration in seconds, or null. The fuelling page's
 * duration field reads this and writes the seconds back into the URL, where
 * `parseFuelDurationS` checks the range.
 */
export function parseClockDurationS(raw: string): number | null {
	const parts = raw.trim().split(':');
	if (parts.length < 2 || parts.length > 3 || parts.some((p) => !/^\d{1,3}$/.test(p))) return null;
	const [h, mm, ss = 0] = parts.map(Number);
	if (mm > 59 || ss > 59) return null;
	return h * 3600 + mm * 60 + ss;
}

export interface FuelHandoff {
	durationS: number | null;
	carbsPerHourG: number | null;
	fluidPerHourMl: number | null;
	heat: boolean;
}

/** Every fuelling input a link can carry, each validated on its own. */
export function parseFuelHandoff(params: URLSearchParams): FuelHandoff {
	return {
		durationS: parseFuelDurationS(params.get('duration')),
		carbsPerHourG: parseFuelRate(params.get('carbs'), FUEL_MAX_CARBS_PER_HOUR_G),
		fluidPerHourMl: parseFuelRate(params.get('fluid'), FUEL_MAX_FLUID_PER_HOUR_ML),
		heat: params.get('heat') === '1',
	};
}

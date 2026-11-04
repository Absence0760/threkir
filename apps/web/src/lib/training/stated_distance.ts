// A race distance an AI extractor heard in a runner's text, put back on the
// race it names. Server-side, shared by the plan request (`plan_request/`)
// and the season request (`season_request/`). Web-only: both endpoints run
// here and nowhere else, so there is no Dart twin.
//
// A miles runner's AI plan box says "Distance: 31.1 mi." (decisions § 2292),
// and the model's kilometres for it, 50.05, name no race anyone runs: a
// distance written to a tenth of a mile is up to half a tenth off the race,
// and the 50K the listing meant would otherwise land in the wizard as a
// custom 50.05 km ultra beside its own 50K preset.
//
// The tolerance follows the unit the runner wrote the distance in, because
// that is what decides how much precision the figure lost. A kilometre
// figure written to one decimal is at most 50 m off, so a stated 50.06 km is
// kept as 50,060 m where the mile tolerance would have rewritten it to 50 km.

export type StatedDistanceUnit = 'km' | 'mi';

const METRES_PER_MILE = 1609.344;

/// The most a distance written to one decimal of a mile can be off the race.
export const MILE_TENTH_ROUNDING_M = METRES_PER_MILE / 20;
/// The most a distance written to one decimal of a kilometre can be off it.
export const KM_TENTH_ROUNDING_M = 50;

/// The stated-unit field an extractor returned, or `km` when it returned
/// none or something else: the tighter tolerance rewrites less.
export function parseStatedDistanceUnit(raw: unknown): StatedDistanceUnit {
	return raw === 'mi' ? 'mi' : 'km';
}

/// `metres`, or the whole kilometre or whole mile it is within half a tenth
/// of `unit` of (the nearer one when both are). Races are named in whole
/// kilometres or whole miles, so anything else is kept as stated; both are
/// candidates in either unit, because a 50K written in miles is "31.1 mi"
/// and a 100-miler written in kilometres is "160.9 km". Non-finite or
/// non-positive input comes back unchanged.
export function snapStatedDistanceM(metres: number, unit: StatedDistanceUnit): number {
	if (!Number.isFinite(metres) || metres <= 0) return metres;
	const tolerance = unit === 'mi' ? MILE_TENTH_ROUNDING_M : KM_TENTH_ROUNDING_M;
	let best = metres;
	let gap = Infinity;
	for (const round of [
		Math.round(metres / 1000) * 1000,
		Math.round(metres / METRES_PER_MILE) * METRES_PER_MILE,
	]) {
		const d = Math.abs(metres - round);
		if (round > 0 && d <= tolerance && d < gap) {
			best = round;
			gap = d;
		}
	}
	return best;
}

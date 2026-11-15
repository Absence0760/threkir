// Pure race auto-match scoring. Mirror of mobile race_match.dart — keep in
// lockstep (algorithm, gates, weights, thresholds, test counts). No I/O.
//
// The auto-match-on-record seam (race_calendar.md) offers, after a run is
// saved, to import the official race result when the recorded run looks like a
// listed race. This is an INFORM-tier suggestion — nothing writes without the
// user confirming. Candidates come from the `race_match_candidates` RPC.
//
// Three gates exclude a listing outright (issue #1389): a run that did not
// start on the race's calendar day in any time zone, a start more than
// RACE_MATCH_MAX_AWAY_M from the race, and a distance more than
// RACE_MATCH_DISTANCE_TOLERANCE off the race's. The date is necessary but
// never enough: a listing is offered only when its location, its distance or
// its course also agrees with the run. A listing that passes is scored, and a
// run that crosses its course's start line and then its finish line ranks
// above every listing it did not cross.

import { crossingsOf, gateUsable, type Gate, type GateFix } from '../geo/gate_crossing';
import { haversineMetres } from '../runs/run_stats';
import { lineLat, lineLng, trackLine, type LinePointSource } from '../runs/track_line';

/// Confidence at or above which a candidate is worth offering.
export const RACE_MATCH_THRESHOLD = 0.5;

/// Start within this radius of the listing's location scores on proximity,
/// falling off linearly to nothing at the edge.
export const RACE_MATCH_RADIUS_M = 5000;

/// A start further than this from the listing's location is not that race.
/// The RPC filters at the same distance.
export const RACE_MATCH_MAX_AWAY_M = 50000;

/// The largest relative difference between the run's distance and the race's
/// that still counts: GPS overshoot plus a recording started or stopped a
/// little away from the lines, well short of a half against a full.
export const RACE_MATCH_DISTANCE_TOLERANCE = 0.15;

/// The race's calendar day, in the earliest and latest time zones there are
/// (UTC+14 and UTC-12): `race_date` carries no zone, so this is the widest day
/// a run on it can have started in.
export const RACE_MATCH_EARLIEST_UTC_OFFSET_H = 14;
export const RACE_MATCH_LATEST_UTC_OFFSET_H = 12;

const HOUR_MS = 3_600_000;
const DAY_MS = 24 * HOUR_MS;

/** One timed fix of the run, epoch ms. */
export interface RaceMatchFix {
	lat: number;
	lng: number;
	tMs: number;
}

export interface RunMatchInput {
	/// Run start as an ISO timestamp.
	startedAt: string;
	distanceM: number | null;
	/// The run's timed fixes, in order; null or empty when it has no track.
	track?: readonly RaceMatchFix[] | null;
}

export interface RaceCourseLines {
	start: Gate | null;
	finish: Gate | null;
}

export interface ListingMatchInput {
	race_date: string; // ISO date (YYYY-MM-DD)
	distance_m: number | null;
	/// The linked course's distance, read when the listing has none.
	course_distance_m?: number | null;
	location?: { lat: number; lng: number } | null;
	/// The linked course's timing lines, when it has a public course.
	lines?: RaceCourseLines | null;
}

export interface RaceMatch {
	score: number;
	/// Whether the run crossed the course's lines in order; null when the
	/// listing has no usable line or the run has no track.
	crossesCourse: boolean | null;
}

/// A stored track as timed line fixes: off-track fixes dropped, each at its
/// line position, untimed or unparseable fixes skipped.
export function raceMatchFixes(
	track: readonly (LinePointSource & { ts?: string | null })[] | null | undefined
): RaceMatchFix[] {
	if (!track) return [];
	const out: RaceMatchFix[] = [];
	for (const p of trackLine(track)) {
		if (!p || typeof p.ts !== 'string') continue;
		const tMs = Date.parse(p.ts);
		const lat = lineLat(p);
		const lng = lineLng(p);
		if (!Number.isFinite(tMs) || !Number.isFinite(lat) || !Number.isFinite(lng)) continue;
		out.push({ lat, lng, tMs });
	}
	return out;
}

/// Whether the run's start instant falls on the race's calendar day in some
/// time zone.
export function startedOnRaceDay(startedAt: string, raceDate: string): boolean {
	const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(raceDate.trim());
	if (!m) return false;
	const startMs = Date.parse(startedAt);
	if (!Number.isFinite(startMs)) return false;
	const dayMs = Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
	return (
		startMs >= dayMs - RACE_MATCH_EARLIEST_UTC_OFFSET_H * HOUR_MS &&
		startMs < dayMs + DAY_MS + RACE_MATCH_LATEST_UTC_OFFSET_H * HOUR_MS
	);
}

function usable(gate: Gate | null | undefined): gate is Gate {
	return gate != null && gateUsable(gate) && gate.halfWidthM > 0;
}

/// Whether the run crossed the course's start line forward and later its
/// finish line forward (either alone when the course has only that one), by
/// `gate_crossing v1`. Null when there is no usable line or no track.
export function runCrossesCourse(
	track: readonly RaceMatchFix[] | null | undefined,
	lines: RaceCourseLines | null | undefined
): boolean | null {
	const start = usable(lines?.start) ? lines!.start! : null;
	const finish = usable(lines?.finish) ? lines!.finish! : null;
	if ((start == null && finish == null) || !track || track.length < 2) return null;
	// Only the crossing instants are read, so covered distance is not tracked.
	const fixes: GateFix[] = track.map((f) => ({ lat: f.lat, lng: f.lng, tMs: f.tMs, coveredM: 0 }));
	const forward = (gate: Gate) =>
		crossingsOf(fixes, gate)
			.filter((c) => c.direction === 'forward')
			.map((c) => c.tMs);
	const starts = start ? forward(start) : null;
	const finishes = finish ? forward(finish) : null;
	if (starts && finishes) {
		if (starts.length === 0 || finishes.length === 0) return false;
		return finishes[finishes.length - 1] > starts[0];
	}
	return (starts ?? finishes)!.length > 0;
}

/// The match of `run` against `listing`, or null when a gate excludes it.
export function raceMatch(run: RunMatchInput, listing: ListingMatchInput): RaceMatch | null {
	if (!startedOnRaceDay(run.startedAt, listing.race_date)) return null;

	const first = run.track && run.track.length > 0 ? run.track[0] : null;
	const loc = listing.location;
	const away =
		first && loc && Number.isFinite(loc.lat) && Number.isFinite(loc.lng)
			? haversineMetres(first.lat, first.lng, loc.lat, loc.lng)
			: null;
	if (away != null && away > RACE_MATCH_MAX_AWAY_M) return null;

	const raceM = listing.distance_m ?? listing.course_distance_m ?? null;
	const runM = run.distanceM;
	const off =
		raceM != null && raceM > 0 && runM != null && Number.isFinite(runM) && runM > 0
			? Math.abs(runM / raceM - 1)
			: null;
	if (off != null && off > RACE_MATCH_DISTANCE_TOLERANCE) return null;

	const crossesCourse = runCrossesCourse(run.track, listing.lines);

	const near = away != null && away <= RACE_MATCH_RADIUS_M;
	if (!near && off == null && crossesCourse !== true) return null;

	// Proximity and distance weigh in whenever the run can be measured on
	// them, so a listing that leaves one unknown earns nothing for it rather
	// than being normalised up to the listings that agree. The course weighs
	// in only when both sides have it: a listing without lines is not evidence
	// against the run.
	let score = 0.5;
	let weight = 0.5;
	if (first) {
		weight += 0.3;
		if (near) score += 0.3 * (1 - away! / RACE_MATCH_RADIUS_M);
	}
	if (runM != null && Number.isFinite(runM) && runM > 0) {
		weight += 0.2;
		if (off != null) score += 0.2 * (1 - off / RACE_MATCH_DISTANCE_TOLERANCE);
	}
	if (crossesCourse != null) {
		weight += 0.5;
		if (crossesCourse) score += 0.5;
	}
	return { score: score / weight, crossesCourse };
}

/// 0..1 confidence that `run` is the race in `listing`; 0 when excluded.
export function raceMatchScore(run: RunMatchInput, listing: ListingMatchInput): number {
	return raceMatch(run, listing)?.score ?? 0;
}

/// Whether a listing is a confident-enough candidate to offer.
export function isRaceMatchCandidate(run: RunMatchInput, listing: ListingMatchInput): boolean {
	return raceMatchScore(run, listing) >= RACE_MATCH_THRESHOLD;
}

/// The listing to offer: a candidate whose course the run crossed first, then
/// the highest score; on a tie the earlier listing (the RPC's nearest first).
export function bestRaceMatch<T>(
	run: RunMatchInput,
	listings: readonly T[],
	input: (listing: T) => ListingMatchInput
): T | null {
	let best: T | null = null;
	let bestMatch: RaceMatch | null = null;
	for (const l of listings) {
		const m = raceMatch(run, input(l));
		if (m == null || m.score < RACE_MATCH_THRESHOLD) continue;
		if (bestMatch == null || ranksAbove(m, bestMatch)) {
			best = l;
			bestMatch = m;
		}
	}
	return best;
}

function ranksAbove(a: RaceMatch, b: RaceMatch): boolean {
	const ac = a.crossesCourse === true;
	const bc = b.crossesCourse === true;
	if (ac !== bc) return ac;
	return a.score > b.score;
}

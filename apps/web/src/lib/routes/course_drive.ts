/**
 * Drive this course (docs/features/course_drive.md, decisions § 2380): the
 * pure core behind handing a course to a Maps app and speaking course notes
 * while someone drives it.
 *
 * Four pieces, all distances along the line the caller was SERVED (the
 * privacy-clipped line for a non-owner, never the raw one):
 *
 * - `buildDriveNotes` — course markers placed on that line, ordered, with
 *   the details a note speaks (aid services, cut-off, climb length + grade).
 * - `driveLeadM` / `DriveCueAnnouncer` — when to speak each note. The lead
 *   scales with speed (about 15 s ahead), and a note passed between two fixes
 *   with nothing said is still reported once.
 * - `planDriveLegs` + the `*Url` builders — the course cut into legs a Maps
 *   app will take, sized by how many stops that app accepts.
 * - `undrivableStretches` — where a road router's line leaves the course, so
 *   the hand-off can say which stretches the driver will not follow.
 *
 * Twin of `apps/mobile_android/lib/course_drive.dart` — keep the constants,
 * algorithms, edge cases and test count in lockstep.
 */
import { lonDeltaDeg, wrapLonDeg } from './geo';
import { haversineMetres } from '../runs/run_stats';
import { parseAidServices, parseCutoff, type CutoffParts } from './route_markers';

export interface DrivePoint {
	lat: number;
	lng: number;
	ele?: number | null;
}

/** A marker farther than this from the served line gets no note. */
export const DRIVE_NOTE_MAX_OFFSET_M = 150;
/** How far ahead a note is spoken, in seconds at the current speed. */
export const DRIVE_LEAD_S = 15;
export const DRIVE_LEAD_MIN_M = 150;
export const DRIVE_LEAD_MAX_M = 1000;
/** The "you're at it" window: at least this far, or `DRIVE_AT_S` seconds. */
export const DRIVE_AT_MIN_M = 30;
export const DRIVE_AT_S = 3;
/** A note passed by less than this with nothing said is still reported. */
export const DRIVE_MISSED_REPORT_M = 400;
/** Target spacing between the stops a Maps leg is pinned to. */
export const DRIVE_STOP_SPACING_M = 1500;
/** A single-destination app gets one leg per this many metres. */
export const DRIVE_SINGLE_STOP_SPACING_M = 3000;
/** A gap between two served points wider than this is never driven across. */
export const DRIVE_MAX_JOIN_M = 2000;
/** A course point farther than this from the router's line is undrivable. */
export const DRIVE_UNDRIVABLE_TOLERANCE_M = 75;
/** Shorter undrivable runs than this are router noise, not a stretch. */
export const DRIVE_UNDRIVABLE_MIN_M = 200;
/** How densely the course is sampled for the undrivable check. */
export const DRIVE_UNDRIVABLE_SAMPLE_M = 25;
/** A climb is reported once it gains this much over this distance at least. */
export const DRIVE_CLIMB_MIN_GAIN_M = 10;
export const DRIVE_CLIMB_MIN_LENGTH_M = 100;
/** A drop this far below the high point ends the climb a marker opens. */
export const DRIVE_CLIMB_END_DROP_M = 10;
export const DRIVE_CLIMB_MAX_LENGTH_M = 5000;

/**
 * Stops each Maps app accepts in one link, counting every waypoint before the
 * destination. Google documents nine, and three in a mobile browser
 * (developers.google.com/maps/documentation/urls/get-started). Apple Maps has
 * no documented multi-stop parameter and Waze takes one destination, so both
 * are driven leg by leg.
 */
export const MAPS_WAYPOINT_CAP = {
	google: 9,
	googleMobileWeb: 3,
	apple: 0,
	waze: 0
} as const;

export type MapsApp = 'google' | 'apple' | 'waze';

const R = 6_371_000;
const toRad = (d: number) => (d * Math.PI) / 180;

/** Cumulative distance to each point of `line`, metres. */
export function cumulativeM(line: readonly DrivePoint[]): number[] {
	const out: number[] = [];
	let acc = 0;
	for (let i = 0; i < line.length; i++) {
		if (i > 0) acc += haversineMetres(line[i - 1].lat, line[i - 1].lng, line[i].lat, line[i].lng);
		out.push(acc);
	}
	return out;
}

export interface LineSnap {
	lat: number;
	lng: number;
	alongM: number;
	offsetM: number;
}

interface Projection extends LineSnap {
	segmentIndex: number;
}

/** Project `p` onto segment i, with t held to [tMin, tMax]. */
function project(
	p: { lat: number; lng: number },
	line: readonly DrivePoint[],
	cum: readonly number[],
	i: number,
	tMin: number,
	tMax: number
): Projection {
	const a = line[i];
	const b = line[i + 1];
	const cosLat = Math.cos(toRad(a.lat));
	const bx = toRad(lonDeltaDeg(a.lng, b.lng)) * R * cosLat;
	const by = toRad(b.lat - a.lat) * R;
	const px = toRad(lonDeltaDeg(a.lng, p.lng)) * R * cosLat;
	const py = toRad(p.lat - a.lat) * R;
	const lenSq = bx * bx + by * by;
	const raw = lenSq > 0 ? (px * bx + py * by) / lenSq : 0;
	const t = Math.max(tMin, Math.min(tMax, raw));
	const lng = wrapLonDeg(a.lng + lonDeltaDeg(a.lng, b.lng) * t);
	const lat = a.lat + (b.lat - a.lat) * t;
	return {
		lat,
		lng,
		alongM: cum[i] + (cum[i + 1] - cum[i]) * t,
		offsetM: haversineMetres(p.lat, p.lng, lat, lng),
		segmentIndex: i
	};
}

/**
 * The nearest point to `p` on the part of `line` between `minAlongM` and
 * `maxAlongM`. This is how a course that crosses or doubles back on itself is
 * followed: the caller asks only about the stretch around where the driver
 * already is, so the other pass of an out-and-back is never a candidate. Null
 * when the line has fewer than two points or the window misses it.
 */
export function snapWithinAlong(
	p: { lat: number; lng: number },
	line: readonly DrivePoint[],
	cum: readonly number[],
	minAlongM: number,
	maxAlongM: number
): LineSnap | null {
	if (line.length < 2 || !Number.isFinite(p.lat) || !Number.isFinite(p.lng)) return null;
	if (!(maxAlongM >= minAlongM)) return null;
	let best: LineSnap | null = null;
	for (let i = 0; i < line.length - 1; i++) {
		const s = cum[i];
		const e = cum[i + 1];
		if (e < minAlongM || s > maxAlongM) continue;
		const len = e - s;
		const tMin = len > 0 ? Math.max(0, (minAlongM - s) / len) : 0;
		const tMax = len > 0 ? Math.min(1, (maxAlongM - s) / len) : 0;
		const c = project(p, line, cum, i, tMin, tMax);
		if (best === null || c.offsetM < best.offsetM) {
			best = { lat: c.lat, lng: c.lng, alongM: c.alongM, offsetM: c.offsetM };
		}
	}
	return best;
}

/**
 * Where a marker sits on the served line. Every segment within
 * `DRIVE_NOTE_MAX_OFFSET_M` is a candidate; with a `hintAlongM` (the marker's
 * server-derived `position_m`) the candidate nearest that distance wins, so a
 * marker on an out-and-back lands on the pass it was placed on. A non-owner's
 * line starts after a clipped privacy zone, so its distances run short of
 * `position_m` by the clipped length; the other pass is still kilometres
 * further off than that. Without a hint the nearest candidate wins.
 */
export function placeOnLine(
	p: { lat: number; lng: number },
	line: readonly DrivePoint[],
	cum: readonly number[],
	hintAlongM: number | null
): LineSnap | null {
	if (line.length < 2 || !Number.isFinite(p.lat) || !Number.isFinite(p.lng)) return null;
	let best: Projection | null = null;
	for (let i = 0; i < line.length - 1; i++) {
		const c = project(p, line, cum, i, 0, 1);
		if (c.offsetM > DRIVE_NOTE_MAX_OFFSET_M) continue;
		if (best === null) {
			best = c;
			continue;
		}
		if (hintAlongM === null || !Number.isFinite(hintAlongM)) {
			if (c.offsetM < best.offsetM) best = c;
			continue;
		}
		const dc = Math.abs(c.alongM - hintAlongM);
		const db = Math.abs(best.alongM - hintAlongM);
		if (dc < db || (dc === db && c.offsetM < best.offsetM)) best = c;
	}
	return best === null
		? null
		: { lat: best.lat, lng: best.lng, alongM: best.alongM, offsetM: best.offsetM };
}

/** Linear-interpolate the point at `alongM` on the line. */
export function pointAtAlong(
	line: readonly DrivePoint[],
	cum: readonly number[],
	alongM: number
): { lat: number; lng: number } | null {
	if (line.length === 0) return null;
	if (line.length === 1 || alongM <= 0) return { lat: line[0].lat, lng: line[0].lng };
	const last = line.length - 1;
	if (alongM >= cum[last]) return { lat: line[last].lat, lng: line[last].lng };
	for (let i = 1; i <= last; i++) {
		if (alongM <= cum[i]) {
			const span = cum[i] - cum[i - 1];
			const t = span > 0 ? (alongM - cum[i - 1]) / span : 0;
			const a = line[i - 1];
			const b = line[i];
			return {
				lat: a.lat + (b.lat - a.lat) * t,
				lng: wrapLonDeg(a.lng + lonDeltaDeg(a.lng, b.lng) * t)
			};
		}
	}
	return { lat: line[last].lat, lng: line[last].lng };
}

export interface DriveMarkerInput {
	kind: string;
	label: string;
	lat: number;
	lng: number;
	position_m: number | null;
	meta: unknown;
}

export interface DriveClimb {
	lengthM: number;
	gradePct: number;
}

export interface DriveNote {
	alongM: number;
	kind: string;
	label: string;
	services: string[];
	cutoff: CutoffParts | null;
	climb: DriveClimb | null;
}

const NOTE_KINDS = new Set(['aid_station', 'cutoff', 'crew_access', 'hazard', 'note', 'climb', 'custom']);

function eleAt(line: readonly DrivePoint[], cum: readonly number[], alongM: number): number | null {
	for (let i = 1; i < line.length; i++) {
		if (alongM <= cum[i]) {
			const a = line[i - 1].ele;
			const b = line[i].ele;
			if (a == null || b == null) return null;
			const span = cum[i] - cum[i - 1];
			const t = span > 0 ? (alongM - cum[i - 1]) / span : 0;
			return a + (b - a) * t;
		}
	}
	const lastEle = line[line.length - 1]?.ele;
	return lastEle == null ? null : lastEle;
}

/**
 * The climb a `climb` marker opens: from the marker to the highest point
 * before the line drops `DRIVE_CLIMB_END_DROP_M` below it, read off the served
 * line's own heights. Null when the line has no usable heights or the rise is
 * too small to call a climb.
 */
export function climbFrom(
	line: readonly DrivePoint[],
	cum: readonly number[],
	alongM: number
): DriveClimb | null {
	const distinct = new Set<number>();
	for (const p of line) if (p.ele != null && Number.isFinite(p.ele)) distinct.add(p.ele);
	if (distinct.size < 2) return null;
	const foot = eleAt(line, cum, alongM);
	if (foot == null) return null;
	let topEle = foot;
	let topAlong = alongM;
	for (let i = 0; i < line.length; i++) {
		if (cum[i] <= alongM) continue;
		if (cum[i] - alongM > DRIVE_CLIMB_MAX_LENGTH_M) break;
		const e = line[i].ele;
		if (e == null || !Number.isFinite(e)) break;
		if (e > topEle) {
			topEle = e;
			topAlong = cum[i];
		} else if (e < topEle - DRIVE_CLIMB_END_DROP_M) {
			break;
		}
	}
	const gain = topEle - foot;
	const lengthM = topAlong - alongM;
	if (gain < DRIVE_CLIMB_MIN_GAIN_M || lengthM < DRIVE_CLIMB_MIN_LENGTH_M) return null;
	return { lengthM, gradePct: Math.round((gain / lengthM) * 1000) / 10 };
}

/**
 * The course notes for a drive, ordered by distance along the served line.
 * Markers that land nowhere near the line (a redacted end, a stray pin) are
 * left out rather than spoken at a guessed position. Turns are not notes: the
 * Maps app already gives turn-by-turn directions.
 */
export function buildDriveNotes(
	markers: readonly DriveMarkerInput[],
	line: readonly DrivePoint[]
): DriveNote[] {
	const cum = cumulativeM(line);
	const placed: { note: DriveNote; order: number }[] = [];
	markers.forEach((m, order) => {
		const snap = placeOnLine({ lat: m.lat, lng: m.lng }, line, cum, m.position_m);
		if (snap === null) return;
		const kind = NOTE_KINDS.has(m.kind) ? m.kind : 'custom';
		const meta = m.meta != null && typeof m.meta === 'object' ? (m.meta as Record<string, unknown>) : {};
		placed.push({
			order,
			note: {
				alongM: snap.alongM,
				kind,
				label: m.label.trim(),
				services: kind === 'aid_station' ? parseAidServices(meta.services) : [],
				cutoff: kind === 'cutoff' ? parseCutoff(meta) : null,
				climb: kind === 'climb' ? climbFrom(line, cum, snap.alongM) : null
			}
		});
	});
	placed.sort((a, b) => a.note.alongM - b.note.alongM || a.order - b.order);
	return placed.map((p) => p.note);
}

/** How far ahead of a note to speak it at `speedMps`. */
export function driveLeadM(speedMps: number): number {
	const v = Number.isFinite(speedMps) && speedMps > 0 ? speedMps : 0;
	return Math.min(DRIVE_LEAD_MAX_M, Math.max(DRIVE_LEAD_MIN_M, v * DRIVE_LEAD_S));
}

/** How close to a note counts as "at it" at `speedMps`. */
export function driveAtM(speedMps: number): number {
	const v = Number.isFinite(speedMps) && speedMps > 0 ? speedMps : 0;
	return Math.max(DRIVE_AT_MIN_M, v * DRIVE_AT_S);
}

export type DriveCueBand = 'ahead' | 'at' | 'passed';

export interface DriveCue {
	index: number;
	note: DriveNote;
	band: DriveCueBand;
	/** Real distance to the note when the cue fired; negative once passed. */
	aheadM: number;
}

/**
 * Decides which note to speak on each position update. Each note speaks at
 * most twice — once `driveLeadM` ahead and once at it — and only the nearest
 * unfinished note is considered, so two close notes do not talk over each
 * other. When a fix lands inside both bands at once, only "at" speaks. A note
 * the driver passed between two fixes with nothing said is reported once as
 * "passed" when it is less than `DRIVE_MISSED_REPORT_M` behind; further back
 * (a long GPS gap, a late join) it is retired silently.
 *
 * `startAlongM` is where the drive joined the course: notes behind it are
 * retired without a word, so joining at mile 8 does not read out miles 0-8.
 */
export class DriveCueAnnouncer {
	private readonly notes: readonly DriveNote[];
	private readonly ahead: boolean[];
	private readonly at: boolean[];
	private readonly done: boolean[];

	constructor(notes: readonly DriveNote[], startAlongM = 0) {
		this.notes = notes;
		this.ahead = notes.map(() => false);
		this.at = notes.map(() => false);
		this.done = notes.map((n) => n.alongM < startAlongM);
	}

	get remaining(): number {
		return this.done.filter((d) => !d).length;
	}

	next(alongM: number, speedMps: number): DriveCue | null {
		const lead = driveLeadM(speedMps);
		const atM = driveAtM(speedMps);
		for (let i = 0; i < this.notes.length; i++) {
			if (this.done[i]) continue;
			const note = this.notes[i];
			const aheadM = note.alongM - alongM;
			if (aheadM < -atM) {
				this.done[i] = true;
				if (!this.ahead[i] && !this.at[i] && -aheadM <= DRIVE_MISSED_REPORT_M) {
					return { index: i, note, band: 'passed', aheadM };
				}
				continue;
			}
			if (this.at[i]) continue;
			if (aheadM <= atM) {
				this.at[i] = true;
				this.ahead[i] = true;
				return { index: i, note, band: 'at', aheadM };
			}
			if (aheadM <= lead && !this.ahead[i]) {
				this.ahead[i] = true;
				return { index: i, note, band: 'ahead', aheadM };
			}
			return null;
		}
		return null;
	}
}

export interface DriveStop {
	lat: number;
	lng: number;
	alongM: number;
}

export interface DriveLeg {
	index: number;
	start: DriveStop;
	/** Stops between start and end, in order. */
	via: DriveStop[];
	end: DriveStop;
}

/**
 * Cut the served line into legs a Maps app will take. `maxWaypoints` is the
 * app's cap on stops before the destination (`MAPS_WAYPOINT_CAP`); the leg's
 * start is the first of them, so the app routes from wherever the driver is
 * to the start of the leg and then along it. A leg is pinned every
 * `spacingM` so the router has little room to pick a different road, and
 * legs never span a gap wider than `DRIVE_MAX_JOIN_M` between two served
 * points: whatever is missing there is not the driver's to fill in.
 */
export function planDriveLegs(
	line: readonly DrivePoint[],
	maxWaypoints: number,
	spacingM: number = maxWaypoints > 0 ? DRIVE_STOP_SPACING_M : DRIVE_SINGLE_STOP_SPACING_M
): DriveLeg[] {
	const cum = cumulativeM(line);
	const pieces: [number, number][] = [];
	let pieceStart = 0;
	for (let i = 1; i < line.length; i++) {
		if (cum[i] - cum[i - 1] > DRIVE_MAX_JOIN_M) {
			pieces.push([pieceStart, i - 1]);
			pieceStart = i;
		}
	}
	if (line.length > 0) pieces.push([pieceStart, line.length - 1]);

	const via = Math.max(0, Math.floor(maxWaypoints) - 1);
	const legLenTarget = Math.max(1, spacingM) * (via + 1);
	const legs: DriveLeg[] = [];
	const stopAt = (alongM: number): DriveStop => {
		const p = pointAtAlong(line, cum, alongM)!;
		return { lat: p.lat, lng: p.lng, alongM };
	};
	for (const [a, b] of pieces) {
		const from = cum[a];
		const to = cum[b];
		const length = to - from;
		if (b <= a || length < 50) continue;
		const n = Math.ceil(length / legLenTarget);
		const legLen = length / n;
		for (let k = 0; k < n; k++) {
			const s = from + k * legLen;
			const e = k === n - 1 ? to : from + (k + 1) * legLen;
			const vias: DriveStop[] = [];
			for (let j = 1; j <= via; j++) vias.push(stopAt(s + ((e - s) * j) / (via + 1)));
			legs.push({ index: legs.length, start: stopAt(s), via: vias, end: stopAt(e) });
		}
	}
	return legs;
}

function coord(p: { lat: number; lng: number }): string {
	return `${p.lat.toFixed(5)},${p.lng.toFixed(5)}`;
}

/** Google Maps driving directions through a leg, from the device's location. */
export function googleMapsLegUrl(leg: DriveLeg): string {
	const waypoints = [leg.start, ...leg.via].map(coord).join('|');
	return (
		'https://www.google.com/maps/dir/?api=1' +
		`&destination=${encodeURIComponent(coord(leg.end))}` +
		`&waypoints=${encodeURIComponent(waypoints)}` +
		'&travelmode=driving'
	);
}

/** Apple Maps driving directions to one point, from the device's location. */
export function appleMapsUrl(dest: { lat: number; lng: number }): string {
	return `https://maps.apple.com/?daddr=${encodeURIComponent(coord(dest))}&dirflg=d`;
}

/** Waze navigation to one point. */
export function wazeUrl(dest: { lat: number; lng: number }): string {
	return `https://waze.com/ul?ll=${encodeURIComponent(coord(dest))}&navigate=yes`;
}

/** The link that opens `leg` in `app`. Single-destination apps go to its end. */
export function mapsLegUrl(app: MapsApp, leg: DriveLeg): string {
	if (app === 'google') return googleMapsLegUrl(leg);
	return app === 'apple' ? appleMapsUrl(leg.end) : wazeUrl(leg.end);
}

/** The link that drives to the start of the course in `app`. */
export function mapsStartUrl(app: MapsApp, start: { lat: number; lng: number }): string {
	if (app === 'google') {
		return (
			'https://www.google.com/maps/dir/?api=1' +
			`&destination=${encodeURIComponent(coord(start))}&travelmode=driving`
		);
	}
	return app === 'apple' ? appleMapsUrl(start) : wazeUrl(start);
}

export interface CourseStretch {
	startM: number;
	endM: number;
}

/**
 * The stretches of the course a road router's line does not follow: every
 * run of course samples (one each `DRIVE_UNDRIVABLE_SAMPLE_M`) farther than
 * `DRIVE_UNDRIVABLE_TOLERANCE_M` from `routed`, kept when it is at least
 * `DRIVE_UNDRIVABLE_MIN_M` long. A closed road, a path or a bridge the
 * router went round shows up here; an empty routed line reports the whole
 * course, since nothing was shown to follow it.
 */
export function undrivableStretches(
	line: readonly DrivePoint[],
	routed: readonly DrivePoint[]
): CourseStretch[] {
	const cum = cumulativeM(line);
	if (line.length < 2) return [];
	const total = cum[cum.length - 1];
	if (total <= 0) return [];
	if (routed.length < 2) return [{ startM: 0, endM: total }];

	const rcum = cumulativeM(routed);
	const padLat = DRIVE_UNDRIVABLE_TOLERANCE_M / 111_320;
	const boxes: { minLat: number; maxLat: number; minLng: number; maxLng: number; refLng: number }[] = [];
	for (let i = 0; i < routed.length - 1; i++) {
		const a = routed[i];
		const b = routed[i + 1];
		const cos = Math.max(0.01, Math.cos(toRad((a.lat + b.lat) / 2)));
		const padLng = padLat / cos;
		const bLng = a.lng + lonDeltaDeg(a.lng, b.lng);
		boxes.push({
			minLat: Math.min(a.lat, b.lat) - padLat,
			maxLat: Math.max(a.lat, b.lat) + padLat,
			minLng: Math.min(a.lng, bLng) - padLng,
			maxLng: Math.max(a.lng, bLng) + padLng,
			refLng: a.lng
		});
	}
	const offCourse = (p: { lat: number; lng: number }): boolean => {
		for (let i = 0; i < boxes.length; i++) {
			const box = boxes[i];
			const lng = box.refLng + lonDeltaDeg(box.refLng, p.lng);
			if (p.lat < box.minLat || p.lat > box.maxLat || lng < box.minLng || lng > box.maxLng) continue;
			if (project(p, routed, rcum, i, 0, 1).offsetM <= DRIVE_UNDRIVABLE_TOLERANCE_M) return false;
		}
		return true;
	};

	const stretches: CourseStretch[] = [];
	let openAt: number | null = null;
	let lastOff = 0;
	const samples = Math.ceil(total / DRIVE_UNDRIVABLE_SAMPLE_M);
	for (let k = 0; k <= samples; k++) {
		const along = Math.min(total, k * DRIVE_UNDRIVABLE_SAMPLE_M);
		const p = pointAtAlong(line, cum, along)!;
		if (offCourse(p)) {
			if (openAt === null) openAt = along;
			lastOff = along;
		} else if (openAt !== null) {
			if (lastOff - openAt >= DRIVE_UNDRIVABLE_MIN_M) stretches.push({ startM: openAt, endM: lastOff });
			openAt = null;
		}
	}
	if (openAt !== null && lastOff - openAt >= DRIVE_UNDRIVABLE_MIN_M) {
		stretches.push({ startM: openAt, endM: lastOff });
	}
	return stretches;
}

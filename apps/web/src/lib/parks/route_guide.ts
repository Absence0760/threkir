/**
 * A park course's route guide (issue #1344, decisions § 2448): the reader of
 * `park_courses.route_guide` and the renderer from its structured steps to
 * the lines a person follows. Steps are data, so every locale reads the
 * guide through its own templates; trail names stay as OpenStreetMap has
 * them, and `getting_there` is free text in the guide's own `lang`.
 *
 * Parity pair with `apps/mobile_android/lib/route_guide.dart`
 * (docs/architecture/parity_pairs.md). Both read the case table in
 * `fixtures/route_guide_cases.json`, so which template a step takes, and with
 * which values, changes there or nowhere. The vocabularies mirror the CHECK
 * `private.park_course_route_guide_ok` (migration 20271212001344) and the
 * generator `scripts/parks/lib/route_guide.mjs`.
 */

export const GUIDE_TURNS = ['left', 'right', 'straight'] as const;
export const GUIDE_WAYS = ['fire_road', 'road', 'path'] as const;
export const GUIDE_ROTATIONS = ['clockwise', 'counterclockwise'] as const;
export const GUIDE_SIDES = ['left', 'right'] as const;
export const GUIDE_SURFACES = ['paved', 'gravel', 'dirt', 'unpaved', 'boardwalk'] as const;
export const GUIDE_CROSSINGS = ['bridge', 'ford'] as const;

type Turn = (typeof GUIDE_TURNS)[number];
type Way = (typeof GUIDE_WAYS)[number];

/** Where a start or a junction leads: a named trail, or the kind of unnamed way. */
export type GuideTarget = { name: string } | { way: Way };

export type RouteGuideStep =
	| ({ kind: 'start'; at_m: number } & GuideTarget)
	| {
			kind: 'direction';
			at_m: number;
			rotation: (typeof GUIDE_ROTATIONS)[number];
			keep_on?: (typeof GUIDE_SIDES)[number];
			landmark?: string;
	  }
	| { kind: 'lap'; at_m: number; lap: number; of: number }
	| ({ kind: 'junction'; at_m: number; turn: Turn } & GuideTarget)
	| { kind: 'crossing'; at_m: number; crossing: (typeof GUIDE_CROSSINGS)[number] }
	| { kind: 'surface'; at_m: number; surface: (typeof GUIDE_SURFACES)[number] }
	| { kind: 'climb'; at_m: number; gain_m: number; length_m: number }
	| { kind: 'checkpoint'; at_m: number; order: number; of: number }
	| { kind: 'finish'; at_m: number };

export interface RouteGuide {
	lang: string;
	gettingThere: string | null;
	steps: RouteGuideStep[];
}

const MAX_STEPS = 200;
const MAX_LABEL = 120;
const MAX_GETTING_THERE = 500;

const isWhole = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v);
const isLabel = (v: unknown): v is string =>
	typeof v === 'string' && v.trim().length >= 1 && v.trim().length <= MAX_LABEL;
const oneOf = <T extends string>(list: readonly T[], v: unknown): v is T =>
	typeof v === 'string' && (list as readonly string[]).includes(v);

function readTarget(s: Record<string, unknown>): GuideTarget | null {
	const hasName = 'name' in s;
	const hasWay = 'way' in s;
	if (hasName === hasWay) return null;
	if (hasName) return isLabel(s.name) ? { name: s.name.trim() } : null;
	return oneOf(GUIDE_WAYS, s.way) ? { way: s.way } : null;
}

function readStep(raw: unknown): RouteGuideStep | null {
	if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) return null;
	const s = raw as Record<string, unknown>;
	if (!isWhole(s.at_m) || s.at_m < 0) return null;
	const at_m = s.at_m;
	switch (s.kind) {
		case 'start': {
			const target = readTarget(s);
			return target && at_m === 0 ? { kind: 'start', at_m, ...target } : null;
		}
		case 'direction': {
			if (!oneOf(GUIDE_ROTATIONS, s.rotation)) return null;
			if ('keep_on' in s !== 'landmark' in s) return null;
			if (!('keep_on' in s)) return { kind: 'direction', at_m, rotation: s.rotation };
			if (!oneOf(GUIDE_SIDES, s.keep_on) || !isLabel(s.landmark)) return null;
			return { kind: 'direction', at_m, rotation: s.rotation, keep_on: s.keep_on, landmark: s.landmark.trim() };
		}
		case 'lap':
			return isWhole(s.lap) && isWhole(s.of) && s.lap >= 2 && s.lap <= s.of
				? { kind: 'lap', at_m, lap: s.lap, of: s.of }
				: null;
		case 'junction': {
			const target = readTarget(s);
			return target && oneOf(GUIDE_TURNS, s.turn) ? { kind: 'junction', at_m, turn: s.turn, ...target } : null;
		}
		case 'crossing':
			return oneOf(GUIDE_CROSSINGS, s.crossing) ? { kind: 'crossing', at_m, crossing: s.crossing } : null;
		case 'surface':
			return oneOf(GUIDE_SURFACES, s.surface) ? { kind: 'surface', at_m, surface: s.surface } : null;
		case 'climb':
			return isWhole(s.gain_m) && isWhole(s.length_m) && s.gain_m >= 1 && s.length_m >= 1
				? { kind: 'climb', at_m, gain_m: s.gain_m, length_m: s.length_m }
				: null;
		case 'checkpoint':
			return isWhole(s.order) && isWhole(s.of) && s.order >= 1 && s.order <= s.of
				? { kind: 'checkpoint', at_m, order: s.order, of: s.of }
				: null;
		case 'finish':
			return { kind: 'finish', at_m };
		default:
			return null;
	}
}

/**
 * Reads `park_courses.route_guide`. Null — never a guide with a step left
 * out — when anything in it cannot be read: a guide missing one turn sends a
 * runner the wrong way, so the section is hidden instead.
 */
export function parseRouteGuide(raw: unknown): RouteGuide | null {
	if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) return null;
	const g = raw as Record<string, unknown>;
	if (g.version !== 1 || typeof g.lang !== 'string' || !Array.isArray(g.steps)) return null;
	if (g.steps.length < 2 || g.steps.length > MAX_STEPS) return null;
	let gettingThere: string | null = null;
	if (g.getting_there !== undefined && g.getting_there !== null) {
		if (typeof g.getting_there !== 'string') return null;
		const text = g.getting_there.trim();
		if (text.length < 1 || text.length > MAX_GETTING_THERE) return null;
		gettingThere = text;
	}
	const steps: RouteGuideStep[] = [];
	let prev = 0;
	for (const raw of g.steps) {
		const step = readStep(raw);
		if (!step || step.at_m < prev) return null;
		prev = step.at_m;
		steps.push(step);
	}
	if (steps[0].kind !== 'start' || steps[steps.length - 1].kind !== 'finish') return null;
	return { lang: g.lang, gettingThere, steps };
}

/** Every template a guide line takes. Each is a full sentence per locale, so word order and gender stay right. */
export const GUIDE_LINE_KEYS = [
	'startNamed',
	'startFireRoad',
	'startRoad',
	'startPath',
	'clockwise',
	'counterclockwise',
	'keepLeft',
	'keepRight',
	'passCheckpoints',
	'leftNamed',
	'rightNamed',
	'straightNamed',
	'leftFireRoad',
	'rightFireRoad',
	'straightFireRoad',
	'leftRoad',
	'rightRoad',
	'straightRoad',
	'leftPath',
	'rightPath',
	'straightPath',
	'bridge',
	'ford',
	'surfacePaved',
	'surfaceGravel',
	'surfaceDirt',
	'surfaceUnpaved',
	'surfaceBoardwalk',
	'climb',
	'checkpoint',
	'lap',
	'finish',
] as const;
export type GuideLineKey = (typeof GUIDE_LINE_KEYS)[number];

/**
 * One line before formatting: its template and raw values. Distances are
 * metres (`at`, `length`, `gain`); the caller formats them in the reader's
 * unit and locale.
 */
export interface GuideLine {
	key: GuideLineKey;
	at?: number;
	name?: string;
	landmark?: string;
	gain?: number;
	length?: number;
	n?: number;
	total?: number;
}

const WAY_SUFFIX: Record<Way, 'FireRoad' | 'Road' | 'Path'> = { fire_road: 'FireRoad', road: 'Road', path: 'Path' };
const SURFACE_KEY: Record<(typeof GUIDE_SURFACES)[number], GuideLineKey> = {
	paved: 'surfacePaved',
	gravel: 'surfaceGravel',
	dirt: 'surfaceDirt',
	unpaved: 'surfaceUnpaved',
	boardwalk: 'surfaceBoardwalk',
};

/**
 * The lines a guide reads as, in order. The start, the direction and (when
 * the course has checkpoints) the stay-on-course note come first; every
 * other step follows at its distance.
 */
export function routeGuideLines(guide: RouteGuide): GuideLine[] {
	const lines: GuideLine[] = [];
	const rest: GuideLine[] = [];
	let hasCheckpoint = false;
	for (const s of guide.steps) {
		switch (s.kind) {
			case 'start':
				lines.push('name' in s ? { key: 'startNamed', name: s.name } : { key: `start${WAY_SUFFIX[s.way]}` });
				break;
			case 'direction':
				lines.push({ key: s.rotation });
				if (s.keep_on && s.landmark) {
					lines.push({ key: s.keep_on === 'left' ? 'keepLeft' : 'keepRight', landmark: s.landmark });
				}
				break;
			case 'junction':
				rest.push(
					'name' in s
						? { key: `${s.turn}Named`, at: s.at_m, name: s.name }
						: { key: `${s.turn}${WAY_SUFFIX[s.way]}`, at: s.at_m },
				);
				break;
			case 'crossing':
				rest.push({ key: s.crossing, at: s.at_m });
				break;
			case 'surface':
				rest.push({ key: SURFACE_KEY[s.surface], at: s.at_m });
				break;
			case 'climb':
				rest.push({ key: 'climb', at: s.at_m, gain: s.gain_m, length: s.length_m });
				break;
			case 'checkpoint':
				hasCheckpoint = true;
				rest.push({ key: 'checkpoint', at: s.at_m, n: s.order, total: s.of });
				break;
			case 'lap':
				rest.push({ key: 'lap', at: s.at_m, n: s.lap, total: s.of });
				break;
			case 'finish':
				rest.push({ key: 'finish', at: s.at_m });
				break;
		}
	}
	if (hasCheckpoint) lines.push({ key: 'passCheckpoints' });
	return [...lines, ...rest];
}

export interface GuideFormat {
	/** The template for a key, with `{at}`, `{name}`, `{landmark}`, `{gain}`, `{length}`, `{n}`, `{total}` filled. */
	message: (key: GuideLineKey, params: Record<string, string | number>) => string;
	/** A distance along the course, e.g. `1.8 km`. */
	distance: (metres: number) => string;
	/** A short length or a height, e.g. `19 m` / `62 ft`. */
	short: (metres: number) => string;
}

/** A line as text. */
export function formatGuideLine(line: GuideLine, fmt: GuideFormat): string {
	const params: Record<string, string | number> = {};
	if (line.at !== undefined) params.at = fmt.distance(line.at);
	if (line.name !== undefined) params.name = line.name;
	if (line.landmark !== undefined) params.landmark = line.landmark;
	if (line.gain !== undefined) params.gain = fmt.short(line.gain);
	if (line.length !== undefined) params.length = fmt.short(line.length);
	if (line.n !== undefined) params.n = line.n;
	if (line.total !== undefined) params.total = line.total;
	return fmt.message(line.key, params);
}

/** The guide as plain text, one line each, for a GPX `<desc>` or a search description. */
export function routeGuideText(guide: RouteGuide, fmt: GuideFormat): string[] {
	return routeGuideLines(guide).map((l) => formatGuideLine(l, fmt));
}

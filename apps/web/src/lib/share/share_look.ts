// The look a runner chose for their photo and sticker share images, kept in
// this browser so the next run shares the same way without choosing again.
// Twin of `RunShareLook` in apps/mobile_android/lib/share_look.dart: the same
// layouts, inks, aspects, stat cap, mark switch, toggle rule and field-by-field
// restore, and the same per-aspect placement of the photo style's stats; and
// the same occasion kinds, offered by the same rule, with the same splits
// budget.

import type { RunShareStatKind } from './run_share_stats';
import { RUN_SHARE_STAT_KINDS } from './run_share_stats';
import {
	DEFAULT_SHARE_PLACEMENT,
	sharePlacementEquals,
	sharePlacementFromJson,
	sharePlacementToJson,
	type SharePlacement,
} from './share_placement';

/// How a stats sticker is laid out: each stat on its own line with the route
/// under them (`stack`), the route large with the stats in a line beneath it
/// (`route`), every stat in one line for the edge of a story (`strip`), or the
/// first stat huge with the rest small beneath it (`hero`).
export const RUN_STICKER_LAYOUTS = ['stack', 'route', 'strip', 'hero'] as const;
export type RunStickerLayout = (typeof RUN_STICKER_LAYOUTS)[number];

/// What a sticker is about: the run's numbers (`stats`, in one of the four
/// layouts), or the occasion the run marks: its `splits`, a personal record
/// (`pr`), a day of a `streak`, a `race` finish, a park `course` time, a
/// `badge` it earned, or the `route` outline alone.
export const RUN_STICKER_KINDS = ['stats', 'splits', 'pr', 'streak', 'race', 'course', 'badge', 'route'] as const;
export type RunStickerKind = (typeof RUN_STICKER_KINDS)[number];

/// What a run holds for each occasion: the splits it has, the records it set,
/// the streak day it was (as of its own day, not today), whether it is linked
/// to a race, completed a park course and earned a badge, and whether it has a
/// line to draw.
export interface RunStickerOccasions {
	splits: number;
	records: number;
	streakDays: number;
	race: boolean;
	course: boolean;
	badge: boolean;
	route: boolean;
}

/// One split is a single number, not a breakdown.
export const MIN_SPLITS_STICKER_ROWS = 2;

/// A first run is not a streak.
export const MIN_STREAK_STICKER_DAYS = 2;

/// The kinds a run can print, in display order. `stats` always; an occasion
/// only when the run has its data, the same rule the stat chips follow, so no
/// sticker prints a dash.
export function offeredStickerKinds(o: RunStickerOccasions): RunStickerKind[] {
	return RUN_STICKER_KINDS.filter((k) => {
		switch (k) {
			case 'stats':
				return true;
			case 'splits':
				return o.splits >= MIN_SPLITS_STICKER_ROWS;
			case 'pr':
				return o.records > 0;
			case 'streak':
				return o.streakDays >= MIN_STREAK_STICKER_DAYS;
			case 'race':
				return o.race;
			case 'course':
				return o.course;
			case 'badge':
				return o.badge;
			case 'route':
				return o.route;
		}
	});
}

/// The remembered kind when this run can print it, `stats` otherwise. The
/// stored look keeps the remembered kind for the next run that has it.
export function stickerKindFor(kind: RunStickerKind, offered: readonly RunStickerKind[]): RunStickerKind {
	return offered.includes(kind) ? kind : 'stats';
}

/// The room a splits sticker may take. It is sized for a 9:16 story 640
/// logical units tall, with the top and bottom eighths kept clear (the profile
/// header and the reply bar), of which it may cover half so the photo still
/// shows; and it may not be shrunk below `legibleDigitsPx` for the pace
/// digits.
export const SPLITS_STICKER_BUDGET = { usableHeight: 480, maxCover: 0.5, legibleDigitsPx: 12 } as const;

/// The tallest a splits sticker may be at its natural size, for rows set at
/// `rowTextPx`: shrunk to the legibility floor, it must still fit the cover.
export function splitsStickerMaxHeight(rowTextPx: number): number {
	const b = SPLITS_STICKER_BUDGET;
	return (b.usableHeight * b.maxCover * rowTextPx) / b.legibleDigitsPx;
}

/// How many rows one table column holds inside the budget, given the row
/// pitch and the height of everything that is not a row.
export function splitsColumnCapacity(rowTextPx: number, rowHeight: number, chrome: number): number {
	return Math.max(0, Math.floor((splitsStickerMaxHeight(rowTextPx) - chrome) / rowHeight));
}

/// A table of one column, of two, or one bar per split once even two columns
/// would overflow the budget.
export type SplitsStickerForm = 'single' | 'paired' | 'bars';

export function splitsStickerForm(rows: number, capacity: number): SplitsStickerForm {
	if (rows <= capacity) return 'single';
	if (rows <= capacity * 2) return 'paired';
	return 'bars';
}

/// One split as the sticker reads it: its pace, its length and whether it is
/// the short tail the run ended on.
export interface SplitsStickerRow {
	paceSecPerKm: number;
	metres: number;
	partial: boolean;
}

/// The fastest whole split, or -1 when there is none. A partial tail is never
/// the fastest, as on run detail: a few hundred metres is not a split.
export function fastestStickerSplit(rows: readonly SplitsStickerRow[]): number {
	let best = -1;
	rows.forEach((r, i) => {
		if (r.partial || !(r.paceSecPerKm > 0)) return;
		if (best < 0 || r.paceSecPerKm < rows[best].paceSecPerKm) best = i;
	});
	return best;
}

/// The pace over every split, weighted by length: the time the splits add up
/// to over the distance they cover.
export function averageStickerPace(rows: readonly SplitsStickerRow[]): number | null {
	let seconds = 0;
	let metres = 0;
	for (const r of rows) {
		if (!(r.paceSecPerKm > 0) || !(r.metres > 0)) continue;
		seconds += (r.paceSecPerKm * r.metres) / 1000;
		metres += r.metres;
	}
	return metres > 0 ? (seconds / metres) * 1000 : null;
}

/// The colour the type and route are drawn in: `light` for a dark photo,
/// `dark` for a bright one, `brand` for the Threkir coral.
export const RUN_SHARE_INKS = ['light', 'dark', 'brand'] as const;
export type RunShareInk = (typeof RUN_SHARE_INKS)[number];

/// The canvas the photo style is cut to: a 4:5 feed `post` or a 9:16 `story`.
export const RUN_PHOTO_ASPECTS = ['post', 'story'] as const;
export type RunPhotoAspect = (typeof RUN_PHOTO_ASPECTS)[number];

export interface RunShareLook {
	kind: RunStickerKind;
	layout: RunStickerLayout;
	ink: RunShareInk;
	aspect: RunPhotoAspect;
	stats: RunShareStatKind[];
	/// Whether the image carries the Threkir mark. On unless the runner turns
	/// it off; free on every tier.
	mark: boolean;
	/// Where the photo style's title and stats sit, kept apart for each
	/// aspect: a block placed on a tall story does not belong on a post.
	placements: Record<RunPhotoAspect, SharePlacement>;
}

function defaultPlacements(): Record<RunPhotoAspect, SharePlacement> {
	return { post: { ...DEFAULT_SHARE_PLACEMENT }, story: { ...DEFAULT_SHARE_PLACEMENT } };
}

export const DEFAULT_SHARE_STATS: readonly RunShareStatKind[] = ['distance', 'pace', 'time'];

/// The most stats one sticker prints: past four, the strip layout no longer
/// reads at story scale.
export const MAX_SHARE_STATS = 4;

export const DEFAULT_SHARE_LOOK: Readonly<RunShareLook> = Object.freeze({
	kind: 'stats',
	layout: 'stack',
	ink: 'light',
	aspect: 'story',
	stats: [...DEFAULT_SHARE_STATS],
	mark: true,
	placements: Object.freeze(defaultPlacements()),
});

/// `look` with the current aspect's placement set to `placement`.
export function withSharePlacement(look: RunShareLook, placement: SharePlacement): RunShareLook {
	return { ...look, placements: { ...look.placements, [look.aspect]: { ...placement } } };
}

export function shareLookEquals(a: RunShareLook, b: RunShareLook): boolean {
	return (
		a.kind === b.kind &&
		a.layout === b.layout &&
		a.ink === b.ink &&
		a.aspect === b.aspect &&
		a.mark === b.mark &&
		RUN_PHOTO_ASPECTS.every((k) => sharePlacementEquals(a.placements[k], b.placements[k])) &&
		a.stats.length === b.stats.length &&
		a.stats.every((k, i) => b.stats[i] === k)
	);
}

/// `look` with `kind` added or removed, in display order. Never empties the
/// set, and never grows it past MAX_SHARE_STATS.
export function toggleShareStat(look: RunShareLook, kind: RunShareStatKind): RunShareLook {
	if (look.stats.includes(kind)) {
		if (look.stats.length === 1) return look;
		return { ...look, stats: look.stats.filter((k) => k !== kind) };
	}
	if (look.stats.length >= MAX_SHARE_STATS) return look;
	return {
		...look,
		stats: RUN_SHARE_STAT_KINDS.filter((k) => k === kind || look.stats.includes(k)),
	};
}

export function shareLookToJson(look: RunShareLook): Record<string, unknown> {
	return {
		kind: look.kind,
		layout: look.layout,
		ink: look.ink,
		aspect: look.aspect,
		stats: [...look.stats],
		mark: look.mark,
		placements: {
			post: sharePlacementToJson(look.placements.post),
			story: sharePlacementToJson(look.placements.story),
		},
	};
}

function pick<T extends string>(values: readonly T[], name: unknown, fallback: T): T {
	return values.find((v) => v === name) ?? fallback;
}

/// Reads a stored look field by field: an unknown or missing value takes its
/// default rather than discarding the rest, so a look saved by a newer build
/// still restores what this build understands.
export function shareLookFromJson(json: unknown): RunShareLook {
	const d = DEFAULT_SHARE_LOOK;
	if (json === null || typeof json !== 'object' || Array.isArray(json)) {
		return { ...d, stats: [...d.stats], placements: defaultPlacements() };
	}
	const o = json as Record<string, unknown>;
	const raw = Array.isArray(o.stats) ? o.stats : [];
	const stats = RUN_SHARE_STAT_KINDS.filter((k) => raw.includes(k));
	const placements =
		o.placements !== null && typeof o.placements === 'object' && !Array.isArray(o.placements)
			? (o.placements as Record<string, unknown>)
			: {};
	return {
		kind: pick(RUN_STICKER_KINDS, o.kind, d.kind),
		layout: pick(RUN_STICKER_LAYOUTS, o.layout, d.layout),
		ink: pick(RUN_SHARE_INKS, o.ink, d.ink),
		aspect: pick(RUN_PHOTO_ASPECTS, o.aspect, d.aspect),
		stats: stats.length === 0 ? [...DEFAULT_SHARE_STATS] : stats.slice(0, MAX_SHARE_STATS),
		mark: typeof o.mark === 'boolean' ? o.mark : d.mark,
		placements: {
			post: sharePlacementFromJson(placements.post),
			story: sharePlacementFromJson(placements.story),
		},
	};
}

/// Device-local, not a synced setting: see docs/backend/settings.md §
/// Device-local pairing prefs. The same key mobile keeps it under.
export const SHARE_LOOK_STORAGE_KEY = 'share_look';

type LookStorage = Pick<Storage, 'getItem' | 'setItem'>;

function browserStorage(): LookStorage | null {
	return typeof localStorage === 'undefined' ? null : localStorage;
}

/// The look saved in this browser, or the default when none is saved or the
/// read fails. A failed read (a private window, blocked site data) is logged,
/// never thrown: the share dialog must open whatever the store does.
export function loadShareLook(storage: LookStorage | null = browserStorage()): RunShareLook {
	try {
		const raw = storage?.getItem(SHARE_LOOK_STORAGE_KEY) ?? null;
		if (raw === null) return shareLookFromJson(null);
		return shareLookFromJson(JSON.parse(raw));
	} catch (e) {
		console.warn('loadShareLook: falling back to the default look', e);
		return shareLookFromJson(null);
	}
}

/// Saves `look` for the next share. A failed write is logged: losing the
/// remembered look costs a runner one re-pick, which is no reason to fail the
/// share in front of them.
export function saveShareLook(look: RunShareLook, storage: LookStorage | null = browserStorage()): void {
	try {
		storage?.setItem(SHARE_LOOK_STORAGE_KEY, JSON.stringify(shareLookToJson(look)));
	} catch (e) {
		console.warn('saveShareLook: look not saved', e);
	}
}

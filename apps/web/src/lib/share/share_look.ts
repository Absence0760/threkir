// The look a runner chose for their photo and sticker share images, kept in
// this browser so the next run shares the same way without choosing again.
// Twin of `RunShareLook` in apps/mobile_android/lib/share_look.dart: the same
// layouts, inks, aspects, stat cap, mark switch, toggle rule and field-by-field
// restore, and the same per-aspect placement of the photo style's stats.

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

/// The colour the type and route are drawn in: `light` for a dark photo,
/// `dark` for a bright one, `brand` for the Threkir coral.
export const RUN_SHARE_INKS = ['light', 'dark', 'brand'] as const;
export type RunShareInk = (typeof RUN_SHARE_INKS)[number];

/// The canvas the photo style is cut to: a 4:5 feed `post` or a 9:16 `story`.
export const RUN_PHOTO_ASPECTS = ['post', 'story'] as const;
export type RunPhotoAspect = (typeof RUN_PHOTO_ASPECTS)[number];

export interface RunShareLook {
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

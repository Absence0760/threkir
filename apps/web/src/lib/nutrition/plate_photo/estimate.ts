// The trust boundary for the plate-photo logger (decisions § 1972). Nothing
// the vision model emitted reaches the client without passing through
// `validatePlateEstimate`: every item is whitelisted field by field, every
// number is clamped into a range a single plated serving can sit in, and
// anything else is dropped. The runner reviews and edits the result before a
// single food_log row is written, so a wrong estimate costs an edit, never a
// silent entry — but a nonsense one (a negative, a NaN, a 40,000 kcal salad)
// never reaches the review list either.

export const MAX_PLATE_ITEMS = 8;
export const MAX_ITEM_NAME_CHARS = 120;

export type PlateMealSlot = 'breakfast' | 'lunch' | 'dinner' | 'snack';
const MEAL_SLOTS: readonly PlateMealSlot[] = ['breakfast', 'lunch', 'dinner', 'snack'];

export type PlateConfidence = 'low' | 'medium' | 'high';
const CONFIDENCES: readonly PlateConfidence[] = ['low', 'medium', 'high'];

/// Per-item ceilings: generous for one plated serving, far below anything a
/// real plate reaches, so a hallucinated digit is caught rather than logged.
/// Grams round to one decimal, kcal and mg to whole numbers.
export const PLATE_ITEM_LIMITS = {
	calories: { max: 3000, decimals: 0 },
	protein_g: { max: 250, decimals: 1 },
	carbs_g: { max: 400, decimals: 1 },
	fat_g: { max: 250, decimals: 1 },
	fiber_g: { max: 100, decimals: 1 },
	sugar_g: { max: 300, decimals: 1 },
	saturated_fat_g: { max: 150, decimals: 1 },
	sodium_mg: { max: 10000, decimals: 0 },
	cholesterol_mg: { max: 3000, decimals: 0 },
} as const;

export type PlateNutrient = keyof typeof PLATE_ITEM_LIMITS;
export const PLATE_NUTRIENTS = Object.keys(PLATE_ITEM_LIMITS) as PlateNutrient[];

export type PlateItem = { item_name: string; confidence: PlateConfidence | null } & {
	[K in PlateNutrient]: number | null;
};

export interface PlateEstimate {
	items: PlateItem[];
	meal_slot: PlateMealSlot | null;
}

/// A finite non-negative number clamped to `max` and rounded, or null. A
/// negative or non-numeric value is a model error, not a small portion, so it
/// is dropped rather than floored to zero.
export function clampNutrient(raw: unknown, max: number, decimals: number): number | null {
	if (typeof raw !== 'number' || !Number.isFinite(raw) || raw < 0) return null;
	const f = 10 ** decimals;
	return Math.round(Math.min(raw, max) * f) / f;
}

/// Printable, single-line, trimmed, capped. Control characters (including
/// newlines and bidi overrides) are removed: the name is shown in lists and
/// stored as a food_log item_name.
export function cleanItemName(raw: unknown): string | null {
	if (typeof raw !== 'string') return null;
	const cleaned = raw
		.replace(/[\u0000-\u001f\u007f-\u009f​-‏‪-‮⁦-⁩]/g, ' ')
		.replace(/\s+/g, ' ')
		.trim()
		.slice(0, MAX_ITEM_NAME_CHARS)
		.trim();
	return cleaned.length > 0 ? cleaned : null;
}

export function validatePlateEstimate(raw: unknown): PlateEstimate {
	const o = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
	const slot = MEAL_SLOTS.includes(o.meal_slot as PlateMealSlot) ? (o.meal_slot as PlateMealSlot) : null;
	const list = Array.isArray(o.items) ? o.items : [];
	const items: PlateItem[] = [];
	for (const entry of list) {
		if (items.length === MAX_PLATE_ITEMS) break;
		if (!entry || typeof entry !== 'object') continue;
		const e = entry as Record<string, unknown>;
		const name = cleanItemName(e.item_name);
		if (!name) continue;
		const item = {
			item_name: name,
			confidence: CONFIDENCES.includes(e.confidence as PlateConfidence)
				? (e.confidence as PlateConfidence)
				: null,
		} as PlateItem;
		for (const k of PLATE_NUTRIENTS) {
			item[k] = clampNutrient(e[k], PLATE_ITEM_LIMITS[k].max, PLATE_ITEM_LIMITS[k].decimals);
		}
		items.push(item);
	}
	return { items, meal_slot: slot };
}

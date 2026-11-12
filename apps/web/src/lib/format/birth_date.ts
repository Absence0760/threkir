// Pure helpers behind DateOfBirthInput. A birth date is picked as three
// selects (month / day / year) rather than `<input type="date">`, whose
// browser popup opens on the current month and makes a runner page back
// through decades to reach their birth year.
//
// Plain .ts with an explicit `locale` / `today` so they unit-test under
// `tsx --test`.

export type DatePart = 'year' | 'month' | 'day';

export interface DateParts {
	year: number | null;
	/** 1-based: 1 = January. */
	month: number | null;
	day: number | null;
}

/** The oldest birth year offered, counted back from today. */
export const MAX_AGE_YEARS = 120;

const ISO_DATE = /^(\d{4})-(\d{2})-(\d{2})$/;

/// Days in a month, 1-based. With no year yet, February offers 29 so a
/// runner born on a leap day can pick the day before the year.
export function daysInMonth(year: number | null, month: number): number {
	if (month === 2 && year == null) return 29;
	return new Date(Date.UTC(year ?? 2000, month, 0)).getUTCDate();
}

export function splitIsoDate(iso: string | null | undefined): DateParts {
	const match = iso ? ISO_DATE.exec(iso) : null;
	if (!match) return { year: null, month: null, day: null };
	const [year, month, day] = [Number(match[1]), Number(match[2]), Number(match[3])];
	if (month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month)) {
		return { year: null, month: null, day: null };
	}
	return { year, month, day };
}

/// `YYYY-MM-DD`, or null while any part is missing or the parts name a day
/// that doesn't exist (31 April, 29 February in a common year).
export function composeIsoDate({ year, month, day }: DateParts): string | null {
	if (year == null || month == null || day == null) return null;
	if (day > daysInMonth(year, month)) return null;
	return `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}

/// True when some parts are picked and some aren't — the state the input
/// reports instead of silently clearing the stored date.
export function isPartial({ year, month, day }: DateParts): boolean {
	const set = [year, month, day].filter((v) => v != null).length;
	return set > 0 && set < 3;
}

/// Birth years newest first, from `today`'s year back MAX_AGE_YEARS.
export function birthYearOptions(today: Date): number[] {
	const newest = today.getFullYear();
	return Array.from({ length: MAX_AGE_YEARS + 1 }, (_, i) => newest - i);
}

/// True when the date the parts would make is after `today` (local
/// calendar), which no birth date can be.
export function isFuture(parts: DateParts, today: Date): boolean {
	const iso = composeIsoDate(parts);
	if (!iso) return false;
	const t = today;
	const todayIso = `${t.getFullYear()}-${String(t.getMonth() + 1).padStart(2, '0')}-${String(t.getDate()).padStart(2, '0')}`;
	return iso > todayIso;
}

const orderCache = new Map<string, DatePart[]>();

/// The order a locale writes a full date in: month-day-year for en-US,
/// day-month-year for most of Europe, year-month-day for ja.
export function datePartOrder(locale?: string): DatePart[] {
	const key = locale ?? '';
	let order = orderCache.get(key);
	if (!order) {
		const parts = new Intl.DateTimeFormat(locale, {
			year: 'numeric',
			month: 'long',
			day: 'numeric',
			timeZone: 'UTC',
		}).formatToParts(new Date(Date.UTC(2021, 0, 15)));
		order = parts
			.map((p) => p.type)
			.filter((t): t is DatePart => t === 'year' || t === 'month' || t === 'day');
		if (order.length !== 3) order = ['month', 'day', 'year'];
		orderCache.set(key, order);
	}
	return order;
}

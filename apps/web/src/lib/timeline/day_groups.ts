/// Consecutive rows that fall on the same local calendar day, in the order
/// the caller already sorted them. Shared by the /history timeline and the
/// /runs list view so the two group a day the same way (decisions § 2117).
///
/// Rows are grouped by run, not bucketed: a day that recurs further down (a
/// list sorted by something other than time) starts a second group rather
/// than pulling rows out of the caller's order. Its key is suffixed so a
/// keyed `{#each}` never sees the same key twice.
export interface DayGroup<T> {
	key: string;
	relative: 'today' | 'yesterday' | null;
	/// The first row's timestamp, for the caller to format as the heading.
	startedAt: string;
	rows: T[];
}

function localDayKey(d: Date): string {
	const mm = String(d.getMonth() + 1).padStart(2, '0');
	const dd = String(d.getDate()).padStart(2, '0');
	return `${d.getFullYear()}-${mm}-${dd}`;
}

export function groupByLocalDay<T>(
	rows: readonly T[],
	startedAt: (row: T) => string,
	now: Date = new Date(),
): DayGroup<T>[] {
	const today = localDayKey(now);
	const y = new Date(now);
	y.setDate(y.getDate() - 1);
	const yesterday = localDayKey(y);

	const groups: DayGroup<T>[] = [];
	const seen = new Map<string, number>();
	let cur: DayGroup<T> | null = null;
	let curDay = '';
	for (const row of rows) {
		const iso = startedAt(row);
		const day = localDayKey(new Date(iso));
		if (!cur || day !== curDay) {
			const n = seen.get(day) ?? 0;
			seen.set(day, n + 1);
			cur = {
				key: n === 0 ? day : `${day}#${n}`,
				relative: day === today ? 'today' : day === yesterday ? 'yesterday' : null,
				startedAt: iso,
				rows: [],
			};
			curDay = day;
			groups.push(cur);
		}
		cur.rows.push(row);
	}
	return groups;
}

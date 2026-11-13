/// What a screen reader hears for FilterBar's Filters button: the plain
/// label while nothing is on, else the label with the count, because the
/// visible badge is `aria-hidden` and would otherwise say nothing.
export function filtersButtonLabel(
	activeCount: number,
	label: string,
	withCount: (count: number) => string,
): string {
	return activeCount > 0 ? withCount(activeCount) : label;
}

/// Whether FilterBar draws its chips as one toggle icon button in the top
/// row rather than a chip line: a lone quick chip never takes a line of its
/// own (issue #1374). Only a chip with an icon can be drawn that way, and
/// only when the top row exists; the mobile twin also joins a lone chip to a
/// view row, which web's views (links above the bar) do not need.
export function loneChipInTopRow(chipCount: number, chipHasIcon: boolean, hasTopRow: boolean): boolean {
	return chipCount === 1 && chipHasIcon && hasTopRow;
}

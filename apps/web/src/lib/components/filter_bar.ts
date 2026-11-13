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

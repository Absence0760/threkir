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

/// Which edges of FilterBar's chip line fade, the twin of ui_kit's
/// `EdgeFadeScroll`: the end while there is more to scroll to, the start
/// once the line has left its start, neither when it all fits. A chip cut
/// by the edge then reads as "more", never a hard cut (issue #1374).
/// `scrolled` is the distance from the start edge, positive in either
/// direction (an RTL `scrollLeft` is negative).
export function lineFades(
	scrolled: number,
	clientWidth: number,
	scrollWidth: number,
): { start: boolean; end: boolean } {
	const from = Math.abs(scrolled);
	return { start: from > 1, end: from + clientWidth < scrollWidth - 1 };
}

/// The CSS mask for the fades, in paint order (left to right), so an RTL
/// line fades its start on the right.
export function lineMask(fades: { start: boolean; end: boolean }, rtl: boolean, extent = '2rem'): string {
	if (!fades.start && !fades.end) return 'none';
	const left = rtl ? fades.end : fades.start;
	const right = rtl ? fades.start : fades.end;
	return `linear-gradient(to right, ${left ? 'transparent' : '#000'}, #000 ${extent}, #000 calc(100% - ${extent}), ${right ? 'transparent' : '#000'})`;
}

/// Whether FilterBar puts its `trailing` actions at the end of the chip
/// line rather than in a top row of their own: when nothing else would
/// share that row (no search, no Filters button, no toggle) and there is a
/// line to stand on. The twin of ui_kit's `FilterBar.trailingOnLine`.
export function trailingOnLine(opts: {
	hasSearch: boolean;
	hasFilters: boolean;
	hasToggle: boolean;
	hasTrailing: boolean;
	hasLine: boolean;
}): boolean {
	return !opts.hasSearch && !opts.hasFilters && !opts.hasToggle && opts.hasTrailing && opts.hasLine;
}

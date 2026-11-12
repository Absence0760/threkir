/// The /runs layout: map-card grid or compact day-grouped list
/// (decisions § 2117). The URL names it so a link can open either; with no
/// `?view=` the viewer's last choice applies, then the grid.
export const RUNS_VIEWS = ['grid', 'list'] as const;
export type RunsView = (typeof RUNS_VIEWS)[number];
export const DEFAULT_RUNS_VIEW: RunsView = 'grid';

export function parseRunsView(raw: unknown): RunsView | null {
	return typeof raw === 'string' && (RUNS_VIEWS as readonly string[]).includes(raw)
		? (raw as RunsView)
		: null;
}

export function resolveRunsView(fromUrl: unknown, stored: unknown): RunsView {
	return parseRunsView(fromUrl) ?? parseRunsView(stored) ?? DEFAULT_RUNS_VIEW;
}

/// The date ranges a link may name with `?range=`. Custom is left out: it
/// means nothing without its bounds. A link that names one replaces the
/// remembered range for that visit, which is how `/history` hands a run-only
/// runner their whole record rather than today's (decisions § 2117).
export const RUNS_LINK_RANGES = ['today', 'week', 'month', 'year', 'all'] as const;
export type RunsLinkRange = (typeof RUNS_LINK_RANGES)[number];

export function parseRunsRange(raw: unknown): RunsLinkRange | null {
	return typeof raw === 'string' && (RUNS_LINK_RANGES as readonly string[]).includes(raw)
		? (raw as RunsLinkRange)
		: null;
}

/// `search` without `range`, every other parameter kept: the range is applied
/// once and then lives in the filters like any other choice, so a refresh
/// after the runner changes it does not snap it back.
export function runsSearchWithoutRange(search: string): string {
	const params = new URLSearchParams(search);
	params.delete('range');
	const rest = params.toString();
	return rest ? `?${rest}` : '';
}

/// `search` with `view` set, every other parameter kept.
export function runsViewSearch(search: string, view: RunsView): string {
	const params = new URLSearchParams(search);
	params.set('view', view);
	return `?${params.toString()}`;
}

/// Day headings only mean something when the list is in time order; under a
/// distance or pace sort they would split the list into one-row fragments.
export function runsListGroupsByDay(sortKey: string): boolean {
	return sortKey === 'newest' || sortKey === 'oldest';
}

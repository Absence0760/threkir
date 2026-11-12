// Which list snapshots a write has outdated.
//
// /runs, /history, /plans and /routes export a SvelteKit `snapshot` that
// keeps the loaded list and the scroll position across a back-navigation
// and skips the refetch. A write made after the snapshot was captured — a
// run created from the list's own modal and opened on its detail page, an
// edit or delete on that detail page — then came back as the pre-write list,
// because nothing told the restore that the data had moved on (decisions
// § 1822).
//
// Every write in the data layer bumps the token of each list that shows the
// written entity. A page notes the token when it STARTS loading its list —
// not when the snapshot is captured, because the create flow writes on the
// list page itself and only then navigates, so a capture-time token would
// already include the write the captured list lacks. The snapshot carries
// that load-time token, and restore keeps the captured list only when it is
// still current. A page that folds its own write into the list in memory (a
// bulk delete on /runs, an optimistic star on /routes) re-notes the token
// once the write settles, so that write does not cost the next back-
// navigation its scroll. A token rather than a read-and-clear flag, because
// a flag set while the user loaded the list fresh in between would outlive
// the load that already saw the write.
//
// The epoch half covers a full reload: SvelteKit keeps snapshots in
// sessionStorage, so one can outlive this module's state. A reload mints a
// new epoch, and every snapshot captured before it reads as stale.

export const SNAPSHOT_LISTS = ['runs', 'history', 'plans', 'routes'] as const;
export type SnapshotList = (typeof SNAPSHOT_LISTS)[number];

/// The snapshotted lists each written table appears on. `runs` rows show on
/// /runs and on the /history timeline (the `activities` view unions runs,
/// gym workouts and food entries), and every run write can move the
/// trigger-maintained `routes.run_count` the /routes list prints — an insert,
/// a delete, a `route_id` change, or a visibility flip
/// (docs/backend/derived_state.md § routes.run_count).
export const LISTS_BY_TABLE = {
	runs: ['runs', 'history', 'routes'],
	gym_workouts: ['history'],
	food_log: ['history'],
	routes: ['routes'],
	training_plans: ['plans'],
} as const satisfies Record<string, readonly SnapshotList[]>;

const epoch = Math.random().toString(36).slice(2, 10);
const versions: Record<SnapshotList, number> = { runs: 0, history: 0, plans: 0, routes: 0 };

/// Server-side this is a no-op: the module is evaluated once per server
/// process, so a counter there would be shared by every request. The writes
/// that call it run in the browser, where module state is one tab's — the
/// same scope a snapshot has.
export function markListsStale(...lists: SnapshotList[]): void {
	if (typeof window === 'undefined') return;
	for (const list of lists) versions[list] += 1;
}

export function listToken(list: SnapshotList): string {
	return `${epoch}:${versions[list]}`;
}

/// `captured` is typed `unknown` because a snapshot written before the token
/// existed restores without one, and that list is as unprovable as a stale one.
export function isListStale(list: SnapshotList, captured: unknown): boolean {
	return captured !== listToken(list);
}

// The order of the NPS alert review queue at /admin/park-alerts.
//
// The queue is read whole by a keyset walk on `id`, the one unique column the
// RPC returns, so the rows arrive in id order and are put back into the order
// the RPC itself sorts by: current flags before ones NPS stopped listing, then
// oldest first, then id.

export interface NpsAlertQueueRow {
	id: number;
	first_seen_at: string;
	gone_at: string | null;
}

export function compareNpsAlertQueue(a: NpsAlertQueueRow, b: NpsAlertQueueRow): number {
	const gone = Number(a.gone_at !== null) - Number(b.gone_at !== null);
	if (gone !== 0) return gone;
	// Parsed, not compared as text: the fraction's length and the offset both
	// vary with how the timestamp was written, and text order follows neither.
	const seen = Date.parse(a.first_seen_at) - Date.parse(b.first_seen_at);
	if (seen !== 0) return seen;
	return a.id - b.id;
}

export function orderNpsAlertQueue<T extends NpsAlertQueueRow>(rows: readonly T[]): T[] {
	return [...rows].sort(compareNpsAlertQueue);
}

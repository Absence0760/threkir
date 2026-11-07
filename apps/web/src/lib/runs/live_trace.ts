/// The spectator's view of a live run's pings, kept in time order whatever
/// order they arrive in (issue #1300 BUG-003).
///
/// Pings reach `/live/[id]` from up to three places at once: the backlog
/// query, the realtime stream (opened first so nothing lands between the
/// two), and the poll fallback when realtime fails. The Go hub also replays
/// its ring on every reconnect. Appending each arrival drew a ping that
/// arrived late as a spike back to an old position, and a replayed ring
/// drew the run twice. Every arrival goes through [insertPing] instead.
///
/// Pure and framework-free so it is unit-testable; the page owns the array.
/// Mirrored by `live_trace.dart` for the mobile spectator screen
/// (`docs/architecture/parity_pairs.md`).

export interface TracePing {
	lat: number;
	lng: number;
	distanceM: number | null;
	elapsedS: number | null;
	bpm: number | null;
	/// The ping's own clock in ms (`at` on the table, `sent_at_ms` on the
	/// hub), or null when it carries none — a hub ping bridged from the
	/// table has `sent_at_ms` 0.
	atMs: number | null;
	/// The privacy-zone last-seen (migration 20270121_001).
	coarse: boolean;
	/// A fix the recorder kept for distance but not for its line (migration
	/// 20271112000030). Drawn as an approximate position, never joined.
	weakGps: boolean;
}

interface OrderedPing extends TracePing {
	orderMs: number;
}

export type InsertResult = 'newest' | 'older' | 'duplicate';

/// An ISO-8601 instant with a time and an explicit offset — what Postgres
/// emits for a `timestamptz`. Anything else (a bare date, a zoneless time, a
/// locale string) is refused rather than resolved in the device's own zone,
/// which `Date.parse` and Dart's `DateTime.tryParse` do differently.
const ISO_INSTANT = /^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])[T ]([01]\d|2[0-3]):[0-5]\d(:[0-5]\d(\.\d+)?)?(Z|[+-]\d{2}(:?\d{2})?)$/;

/// A finite, positive timestamp, or null. Zero and negatives are the hub's
/// "no clock" and a malformed `at`, neither of which is an instant.
export function pingTimeMs(atIso: string | null | undefined, sentAtMs?: number | null): number | null {
	if (typeof sentAtMs === 'number' && Number.isFinite(sentAtMs) && sentAtMs > 0) return sentAtMs;
	if (atIso == null || !ISO_INSTANT.test(atIso)) return null;
	const t = Date.parse(atIso);
	return Number.isFinite(t) && t > 0 ? t : null;
}

function samePing(a: TracePing, b: TracePing): boolean {
	return (
		a.lat === b.lat &&
		a.lng === b.lng &&
		a.distanceM === b.distanceM &&
		a.elapsedS === b.elapsedS
	);
}

/// Insert [incoming] into [pings] (kept sorted by time, mutated in place).
///
/// - A ping with a clock goes where its clock puts it; equal clocks keep
///   arrival order.
/// - A ping without one goes last, at the newest clock seen so far: arrival
///   order is the only order it has.
/// - A ping already present is dropped: same clock and same reading, or, for
///   one without a clock, the same reading anywhere in the list.
///
/// Returns whether it became the newest ping (the one the marker and the
/// stat strip show), landed behind it, or was a duplicate.
export function insertPing(pings: TracePing[], incoming: TracePing): InsertResult {
	const list = pings as OrderedPing[];
	const lastOrder = list.length > 0 ? list[list.length - 1].orderMs : 0;
	if (incoming.atMs == null) {
		if (list.some((p) => p.atMs == null && samePing(p, incoming))) return 'duplicate';
		list.push({ ...incoming, orderMs: lastOrder });
		return 'newest';
	}
	const order = incoming.atMs;
	let lo = 0;
	let hi = list.length;
	while (lo < hi) {
		const mid = (lo + hi) >>> 1;
		if (list[mid].orderMs <= order) lo = mid + 1;
		else hi = mid;
	}
	for (let i = lo - 1; i >= 0 && list[i].orderMs === order; i--) {
		if (list[i].atMs === order && samePing(list[i], incoming)) return 'duplicate';
	}
	list.splice(lo, 0, { ...incoming, orderMs: order });
	return lo === list.length - 1 ? 'newest' : 'older';
}

/// The trace line's coordinates, `[lng, lat]`, in time order. Only precise
/// fixes join it: a coarse or weak ping is drawn as an approximate marker
/// instead, the way the saved run keeps those fixes off its line.
export function traceLineCoords(pings: readonly TracePing[]): [number, number][] {
	const out: [number, number][] = [];
	for (const p of pings) {
		if (!p.coarse && !p.weakGps) out.push([p.lng, p.lat]);
	}
	return out;
}

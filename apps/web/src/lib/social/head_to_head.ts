/// The head-to-head share card's pure half: the rows the `head_to_head` RPC
/// returns, who won and by how much, and how the card prints a time and a name.
/// Decisions § 2267.
///
/// TS↔Dart parity pair with `apps/mobile_android/lib/head_to_head.dart` — keep
/// the two in lockstep: algorithm, edge cases, outputs, test counts.

export const HEAD_TO_HEAD_KINDS = ['route', 'segment', 'global_segment'] as const;
export type HeadToHeadKind = (typeof HEAD_TO_HEAD_KINDS)[number];

export interface HeadToHeadRow {
	friendId: string;
	friendDisplayName: string | null;
	friendHandle: string | null;
	friendAvatarUrl: string | null;
	targetName: string;
	myRunId: string;
	mySeconds: number;
	friendRunId: string;
	friendSeconds: number;
}

export type HeadToHeadWinner = 'me' | 'friend' | 'tie';

export interface HeadToHeadOutcome {
	winner: HeadToHeadWinner;
	/// Whole seconds between the two times; 0 for a tie.
	marginSeconds: number;
}

function text(v: unknown): string | null {
	return typeof v === 'string' && v.trim() !== '' ? v : null;
}

function seconds(v: unknown): number | null {
	return typeof v === 'number' && Number.isFinite(v) && v > 0 ? v : null;
}

/// The RPC's rows, keeping only those that carry both sides. A malformed row is
/// dropped rather than drawn with a missing time.
export function parseHeadToHeadRows(raw: unknown): HeadToHeadRow[] {
	if (!Array.isArray(raw)) return [];
	const rows: HeadToHeadRow[] = [];
	for (const r of raw) {
		if (r === null || typeof r !== 'object') continue;
		const o = r as Record<string, unknown>;
		const friendId = text(o.friend_id);
		const targetName = text(o.target_name);
		const myRunId = text(o.my_run_id);
		const friendRunId = text(o.friend_run_id);
		const mySeconds = seconds(o.my_seconds);
		const friendSeconds = seconds(o.friend_seconds);
		if (!friendId || !targetName || !myRunId || !friendRunId || mySeconds === null || friendSeconds === null) {
			continue;
		}
		rows.push({
			friendId,
			friendDisplayName: text(o.friend_display_name),
			friendHandle: text(o.friend_handle),
			friendAvatarUrl: text(o.friend_avatar_url),
			targetName,
			myRunId,
			mySeconds,
			friendRunId,
			friendSeconds,
		});
	}
	return rows;
}

/// Lower time wins. Both are rounded to whole seconds first, so the card never
/// names a winner by a margin it prints as 0:00.
export function headToHeadOutcome(mySeconds: number, friendSeconds: number): HeadToHeadOutcome {
	const mine = Math.round(mySeconds);
	const theirs = Math.round(friendSeconds);
	if (mine === theirs) return { winner: 'tie', marginSeconds: 0 };
	return { winner: mine < theirs ? 'me' : 'friend', marginSeconds: Math.abs(mine - theirs) };
}

/// `m:ss` under an hour, `h:mm:ss` from one. Rounded; never negative.
export function formatHeadToHeadTime(totalSeconds: number): string {
	const t = Number.isFinite(totalSeconds) ? Math.max(0, Math.round(totalSeconds)) : 0;
	const h = Math.floor(t / 3600);
	const m = Math.floor((t % 3600) / 60);
	const s = t % 60;
	const ss = String(s).padStart(2, '0');
	return h > 0 ? `${h}:${String(m).padStart(2, '0')}:${ss}` : `${m}:${ss}`;
}

/// `@handle` when the runner has one, else their display name, else null so
/// the caller supplies its own fallback.
export function headToHeadName(handle: string | null | undefined, displayName: string | null | undefined): string | null {
	const h = handle?.trim();
	if (h) return `@${h}`;
	const d = displayName?.trim();
	return d ? d : null;
}

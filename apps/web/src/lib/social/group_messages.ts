/**
 * Group conversations on web (issue #1365 slice 2, decisions § 2463): the pure
 * rules the inbox, the create and invite pickers and the group thread share.
 *
 * The server is authoritative on every one of them (migrations
 * 20271216000007 and 20271217000006); these decide only what to offer, so a
 * control the server would refuse is not drawn. The mobile twin arrives with
 * slice 3, which registers the pair in docs/architecture/parity_pairs.md.
 */

import { compareFoldedNames } from '../segments/catalogue_browse';
import { compareDmOrder, type DmOrderKey } from './dm_thread';

/** `c_group_max_members` in private.group_check_cap: members and live invites. */
export const GROUP_MAX_MEMBERS = 32;

/** A group's title is 1 to 60 characters after trimming (conversations_title_check). */
export const GROUP_TITLE_MAX = 60;

/** create_group_conversation needs at least two other people. */
export const GROUP_MIN_INVITEES = 2;

export type GroupRole = 'owner' | 'admin' | 'member';

/** A group_members() row: `role` is null for an invite. */
export interface GroupMemberState {
	userId: string;
	role: GroupRole | null;
	state: 'active' | 'invited';
}

/** A role read at the boundary; anything else is no role. */
export function parseGroupRole(raw: unknown): GroupRole | null {
	return raw === 'owner' || raw === 'admin' || raw === 'member' ? raw : null;
}

/**
 * The title as the server stores it, or null when it would refuse it. Counted
 * in code points, as Postgres `char_length` counts characters, so an emoji is
 * one of the 60 and not two.
 */
export function normalizeGroupTitle(raw: string): string | null {
	const t = raw.trim();
	const n = Array.from(t).length;
	return n >= 1 && n <= GROUP_TITLE_MAX ? t : null;
}

/**
 * Seats a group has left for new invites: 32 less its members and live
 * invites. The creator takes a seat, so a new group can invite 31.
 */
export function groupSeatsLeft(activeCount: number, pendingCount: number): number {
	return Math.max(0, GROUP_MAX_MEMBERS - Math.max(0, activeCount) - Math.max(0, pendingCount));
}

const RANK: Record<GroupRole, number> = { owner: 3, admin: 2, member: 1 };

/** private.group_rank: an invite has no role and ranks 0. */
function rank(role: GroupRole | null): number {
	return role ? RANK[role] : 0;
}

/** Owner and admins invite and rename (invite_to_group, rename_group). */
export function canManageGroup(myRole: GroupRole | null): boolean {
	return myRole === 'owner' || myRole === 'admin';
}

/** Only the owner changes roles and hands ownership on. */
export function canChangeGroupRoles(myRole: GroupRole | null): boolean {
	return myRole === 'owner';
}

/**
 * remove_group_member's rule: an admin or the owner removes someone ranked
 * below them (an invite ranks below everyone, so cancelling one is a removal),
 * never themselves, and nobody removes the owner.
 */
export function canRemoveGroupMember(
	myRole: GroupRole | null,
	me: string | null,
	target: GroupMemberState,
): boolean {
	if (!me || target.userId === me || rank(myRole) < 2) return false;
	return rank(myRole) > rank(target.state === 'active' ? target.role : null);
}

/**
 * Owner first, then admins, then members, each by folded name with unnamed
 * last; invites after. Folded rather than collated so the Dart twin can order
 * it the same way (decisions § 1956).
 */
export function sortGroupMembers<T extends GroupMemberState & { name: string | null }>(
	members: readonly T[],
): T[] {
	return [...members].sort((a, b) => {
		if (a.state !== b.state) return a.state === 'active' ? -1 : 1;
		const r = rank(b.role) - rank(a.role);
		if (r !== 0) return r;
		if (a.name === null || b.name === null) {
			if (a.name !== b.name) return a.name === null ? 1 : -1;
			return a.userId < b.userId ? -1 : a.userId > b.userId ? 1 : 0;
		}
		return compareFoldedNames(a.name, a.userId, b.name, b.userId);
	});
}

/** One line of a group thread: a message, or the place of one the viewer blocked. */
export type GroupThreadItem<T extends DmOrderKey> =
	| { kind: 'message'; message: T }
	| { kind: 'blocked'; id: string; created_at: string };

/**
 * Messages and "message from someone you blocked" placeholders in thread
 * order. A placeholder whose id is also a message on screen is dropped: the
 * viewer unblocked and the message itself came back.
 */
export function mergeGroupThread<T extends DmOrderKey>(
	messages: readonly T[],
	placeholders: readonly DmOrderKey[],
): GroupThreadItem<T>[] {
	const shown = new Set(messages.map((m) => m.id));
	const items: GroupThreadItem<T>[] = [
		...messages.map((message) => ({ kind: 'message' as const, message })),
		...placeholders
			.filter((p) => !shown.has(p.id))
			.map((p) => ({ kind: 'blocked' as const, id: p.id, created_at: p.created_at })),
	];
	const orderKey = (i: GroupThreadItem<T>): DmOrderKey => (i.kind === 'message' ? i.message : i);
	return items.sort((a, b) => compareDmOrder(orderKey(a), orderKey(b)));
}

/**
 * The lower bound for a placeholder read: the oldest message on screen while
 * older ones exist, so placeholders stay inside the loaded window; null once
 * the whole readable history is loaded.
 */
export function placeholdersSince(messages: readonly DmOrderKey[], hasMore: boolean): string | null {
	return hasMore && messages.length > 0 ? messages[0].created_at : null;
}

/**
 * The group a `/messages/group/<id>` path names, or null for any other
 * conversation path.
 */
export function groupIdFromRouteId(routeId: string | null): string | null {
	return routeId?.startsWith('group/') ? routeId.slice('group/'.length) || null : null;
}

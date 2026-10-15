/**
 * Keyset paging for one direct-message conversation, on `(created_at, id)`.
 *
 * The thread is read from its newest end: the first page is the latest
 * `DM_THREAD_PAGE_SIZE` messages, and "load earlier" asks for the page before
 * the oldest message on screen. Mobile's `fetchDmThread` (api_client) pages
 * the same way with the same size and tie-break.
 */

import { keysetAfter, keysetCursor, type KeysetKey } from '../core/keyset_page';

export const DM_THREAD_PAGE_SIZE = 50;

export interface DmOrderKey {
	id: string;
	created_at: string;
}

export interface DmPage<T> {
	/** Oldest first, the order the conversation renders in. */
	messages: T[];
	/** Messages older than the first one here exist. */
	hasMore: boolean;
}

/**
 * `[milliseconds, microseconds within the millisecond]`. `Date.parse` stops at
 * milliseconds and Postgres stamps microseconds, so two messages in the same
 * millisecond would otherwise tie on time and fall through to the id.
 */
function instant(iso: string): [number, number] {
	const ms = Date.parse(iso);
	const frac = /T\d{2}:\d{2}:\d{2}\.(\d+)/.exec(iso)?.[1] ?? '';
	return [Number.isNaN(ms) ? 0 : ms, Number((frac + '000000').slice(3, 6))];
}

/** The thread's order: `created_at`, then `id`. */
export function compareDmOrder(a: DmOrderKey, b: DmOrderKey): number {
	const [ma, ua] = instant(a.created_at);
	const [mb, ub] = instant(b.created_at);
	if (ma !== mb) return ma - mb;
	if (ua !== ub) return ua - ub;
	return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
}

/**
 * The thread's keyset, newest first. Both columns are NOT NULL, so null
 * placement never applies; `nullsFirst: true` is the postgrest-js default for a
 * descending key and keeps `keysetAfter` from adding an `is.null` arm.
 */
export const DM_THREAD_ORDER: readonly KeysetKey[] = [
	{ column: 'created_at', ascending: false, nullsFirst: true },
	{ column: 'id', ascending: false, nullsFirst: true }
];

/**
 * The PostgREST `or` body for the page strictly before `before` (older, since
 * the read runs newest first). The timestamp goes back exactly as the server
 * wrote it, so no microseconds are lost on the way round.
 */
export function dmPageBeforeFilter(before: DmOrderKey): string {
	const filter = keysetAfter(DM_THREAD_ORDER, keysetCursor(DM_THREAD_ORDER, before));
	if (filter === null) throw new Error('dm thread: no message can precede the cursor');
	return filter;
}

/**
 * Turns the newest-first rows of a `limit + 1` read into a page. The extra
 * row is only the "older messages exist" probe and is dropped.
 */
export function dmPageFromRows<T>(newestFirst: readonly T[], limit: number): DmPage<T> {
	const hasMore = newestFirst.length > limit;
	const kept = hasMore ? newestFirst.slice(0, limit) : newestFirst.slice();
	return { messages: kept.reverse(), hasMore };
}

/** Union by id, in thread order. A later copy of an id replaces an earlier. */
export function mergeDmMessages<T extends DmOrderKey>(a: readonly T[], b: readonly T[]): T[] {
	const byId = new Map<string, T>();
	for (const m of a) byId.set(m.id, m);
	for (const m of b) byId.set(m.id, m);
	return [...byId.values()].sort(compareDmOrder);
}

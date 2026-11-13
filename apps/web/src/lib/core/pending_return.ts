/// Carries a sign-in hop's `return_to` across a sign-up that leaves the page.
///
/// An email confirmation link and an OAuth round trip both land on
/// /auth/callback with no query of its own, so the invite a visitor signed up
/// from (a club or challenge join link) was dropped for /dashboard. /login
/// stashes the target here before it leaves; the callback takes it once.
/// localStorage, not sessionStorage: the confirmation link opens in a new tab.
/// A different device finds nothing and lands on the default, as before.

import { DEFAULT_RETURN_TO, safeReturnTo } from './safe_redirect';
import { localStore } from './browser_storage';

export const PENDING_RETURN_KEY = 'threkir.pending_return_to';
export const PENDING_RETURN_TTL_MS = 24 * 60 * 60 * 1000;

export type ReturnStore = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>;

export function stashPendingReturn(
	store: ReturnStore | null,
	target: string,
	now: number = Date.now(),
): void {
	if (!store) return;
	const to = safeReturnTo(target);
	try {
		if (to === DEFAULT_RETURN_TO) store.removeItem(PENDING_RETURN_KEY);
		else store.setItem(PENDING_RETURN_KEY, JSON.stringify({ to, at: now }));
	} catch {
		/* Storage refused (private mode, quota): the hop falls back to the default. */
	}
}

/// The stashed target, removed as it is read. Null when there is none, it is
/// older than a day, or it no longer passes the same-origin check.
export function takePendingReturn(
	store: ReturnStore | null,
	now: number = Date.now(),
): string | null {
	if (!store) return null;
	let raw: string | null;
	try {
		raw = store.getItem(PENDING_RETURN_KEY);
		store.removeItem(PENDING_RETURN_KEY);
	} catch {
		return null;
	}
	if (!raw) return null;
	try {
		const parsed = JSON.parse(raw) as { to?: unknown; at?: unknown };
		if (typeof parsed.to !== 'string' || typeof parsed.at !== 'number') return null;
		if (now - parsed.at > PENDING_RETURN_TTL_MS || parsed.at > now) return null;
		const to = safeReturnTo(parsed.to);
		return to === DEFAULT_RETURN_TO ? null : to;
	} catch {
		return null;
	}
}

/// localStorage, or null where reading it throws (sandboxed frames, blocked
/// site data).
export function browserReturnStore(): ReturnStore | null {
	return localStore();
}

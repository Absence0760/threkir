/// Share-link attribution, the pure half (decisions § 2268).
///
/// A creator's own share links carry `?ref=<code>`, an opaque ten-character
/// code minted by `my_share_ref`. A visit reads it back from the URL, a sign-up
/// made from the share page carries it into the GoTrue metadata as
/// `signup_share`, and a plan copy or a challenge join made through it is
/// attributed to the link. Every reader validates it with `parseShareRef`, so
/// anything else in the parameter is dropped rather than forwarded.

import { isEntityId } from '../core/entity_id';

export const SHARE_REF_PARAM = 'ref';

const SHARE_REF_RE = /^[a-z0-9]{10}$/;

/// The share kinds the creator view counts. Clubs, events and race listings are
/// left out: they belong to a club or to nobody, and the view is one person's.
export const TRACKED_SHARE_KINDS = ['plan', 'challenge', 'profile', 'session', 'workout'] as const;
export type TrackedShareKind = (typeof TRACKED_SHARE_KINDS)[number];

export function isTrackedShareKind(value: unknown): value is TrackedShareKind {
	return typeof value === 'string' && (TRACKED_SHARE_KINDS as readonly string[]).includes(value);
}

/// A well-formed ref code, or null.
export function parseShareRef(value: unknown): string | null {
	return typeof value === 'string' && SHARE_REF_RE.test(value) ? value : null;
}

/// The ref in a URL's query string, or null when it is absent or malformed.
export function shareRefFromSearch(search: string | null | undefined): string | null {
	if (!search) return null;
	try {
		return parseShareRef(new URLSearchParams(search).get(SHARE_REF_PARAM));
	} catch {
		return null;
	}
}

/// `url` with `ref` set, for an absolute URL or a root-relative path. Returns
/// `url` unchanged when `ref` is not a well-formed code, so a caller can pass
/// whatever it has.
export function withShareRef(url: string, ref: string | null | undefined): string {
	const code = parseShareRef(ref);
	if (!code) return url;
	const hashAt = url.indexOf('#');
	const hash = hashAt >= 0 ? url.slice(hashAt) : '';
	const head = hashAt >= 0 ? url.slice(0, hashAt) : url;
	const queryAt = head.indexOf('?');
	const path = queryAt >= 0 ? head.slice(0, queryAt) : head;
	const params = new URLSearchParams(queryAt >= 0 ? head.slice(queryAt + 1) : '');
	params.set(SHARE_REF_PARAM, code);
	return `${path}?${params.toString()}${hash}`;
}

export interface SignupShare {
	kind: TrackedShareKind;
	id: string;
	ref: string;
}

/// The share a sign-up came from, read off the in-app target the visitor was
/// returning to: a `/share/<kind>/<id>` page, or the plan library preview the
/// plan page sends a new runner to. Null without a valid ref, so a sign-up is
/// attributed only through a link its owner handed out.
export function signupShareFromTarget(target: string | null | undefined): SignupShare | null {
	if (!target || target[0] !== '/') return null;
	let url: URL;
	try {
		url = new URL(target, 'https://internal.invalid');
	} catch {
		return null;
	}
	const ref = parseShareRef(url.searchParams.get(SHARE_REF_PARAM));
	if (!ref) return null;
	const parts = url.pathname.split('/').filter(Boolean);
	let kind: string | null = null;
	let id: string | null = null;
	if (parts.length === 3 && parts[0] === 'share') {
		kind = parts[1];
		id = parts[2];
	} else if (parts.length === 3 && parts[0] === 'plans' && parts[1] === 'library') {
		kind = 'plan';
		id = parts[2];
	}
	if (!isTrackedShareKind(kind) || !isEntityId(id)) return null;
	return { kind, id: id!.toLowerCase(), ref };
}

const BOT_UA_RE =
	/bot\b|crawl|spider|slurp|facebookexternalhit|embedly|headless|lighthouse|bingpreview/i;

/// A crawler that runs the page's script and says so. Counted apart from
/// visits; an unfurler that does not run script never reaches the counter.
export function isLikelyBot(userAgent: string | null | undefined, webdriver = false): boolean {
	if (webdriver) return true;
	return !!userAgent && BOT_UA_RE.test(userAgent);
}

/// The sign-up link on a share page. With a valid ref it returns the new
/// account to the same page with the ref intact, which is what lets the
/// sign-up be attributed to the link; without one it is the plain sign-up.
export function shareSignupHref(sharePath: string, ref: string | null | undefined): string {
	const code = parseShareRef(ref);
	if (!code) return '/login?signup=1';
	return `/login?signup=1&return_to=${encodeURIComponent(withShareRef(sharePath, code))}`;
}

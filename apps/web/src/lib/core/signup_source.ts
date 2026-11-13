/// First-touch sign-up source, the pure half (decisions § 2350). Where this
/// browser tab first arrived from, kept in sessionStorage until a sign-up sends
/// it as `signup_source` GoTrue metadata. The I/O half is
/// `signup_source_attribution.ts`.
///
/// UTM parameters win when present (bio links carry them); otherwise the
/// referrer's host is mapped to a platform name. Post captions say a bare
/// "threkir.com", so for those the referrer is the only signal, and in-app
/// browsers that send none arrive as `direct`.

import { sessionStore } from './browser_storage';

export const SIGNUP_SOURCE_KEY = 'threkir.signup_source';

export type SignupSourceStore = Pick<Storage, 'getItem' | 'setItem'>;

export interface SignupSource {
	source: string;
	medium: string | null;
	campaign: string | null;
	referrer_host: string | null;
}

const TOKEN = /^[a-z0-9][a-z0-9._-]{0,63}$/;
const HOST = /^[a-z0-9.-]{1,253}$/;

const PLATFORM_HOSTS: Record<string, string> = {
	'instagram.com': 'instagram',
	'facebook.com': 'facebook',
	'fb.com': 'facebook',
	'fb.me': 'facebook',
	'tiktok.com': 'tiktok',
	'youtube.com': 'youtube',
	'youtu.be': 'youtube',
	'threads.net': 'threads',
	'threads.com': 'threads',
	't.co': 'x',
	'x.com': 'x',
	'twitter.com': 'x',
	'bsky.app': 'bluesky',
	'linkedin.com': 'linkedin',
	'lnkd.in': 'linkedin',
};

const UTM_ALIASES: Record<string, string> = {
	ig: 'instagram',
	insta: 'instagram',
	fb: 'facebook',
	tt: 'tiktok',
	yt: 'youtube',
	twitter: 'x',
	bsky: 'bluesky',
	li: 'linkedin',
};

/// A UTM value as the database accepts it: lowercase, spaces to hyphens,
/// anything outside [a-z0-9._-] dropped, at most 64 characters. Null when
/// nothing is left.
export function sourceToken(raw: string | null | undefined): string | null {
	if (typeof raw !== 'string') return null;
	const t = raw
		.trim()
		.toLowerCase()
		.replace(/\s+/g, '-')
		.replace(/[^a-z0-9._-]/g, '')
		.replace(/^[._-]+/, '')
		.slice(0, 64);
	return TOKEN.test(t) ? t : null;
}

export function referrerHost(referrer: string | null | undefined): string | null {
	if (!referrer) return null;
	try {
		const host = new URL(referrer).hostname.toLowerCase();
		return HOST.test(host) ? host : null;
	} catch {
		return null;
	}
}

/// The platform a referrer host belongs to, matching the domain itself or any
/// subdomain of it (l.instagram.com, m.facebook.com, www.threads.net).
export function platformForHost(host: string | null | undefined): string | null {
	if (!host) return null;
	for (const [domain, platform] of Object.entries(PLATFORM_HOSTS)) {
		if (host === domain || host.endsWith(`.${domain}`)) return platform;
	}
	return null;
}

function sameSite(a: string, b: string): boolean {
	const bare = (h: string) => h.toLowerCase().replace(/^www\./, '');
	return bare(a) === bare(b);
}

/// The first touch this landing represents, or null when it is not a landing
/// worth recording: the auth hops (an OAuth provider or a mail client would be
/// read as the source) and a navigation from this site with no UTM.
export function firstTouchFrom(
	pathname: string,
	search: string,
	referrer: string | null | undefined,
	ownHost: string,
): SignupSource | null {
	if (pathname.startsWith('/auth/')) return null;
	const params = new URLSearchParams(search);
	const utmSource = sourceToken(params.get('utm_source'));
	let host = referrerHost(referrer);
	if (host && sameSite(host, ownHost)) {
		if (!utmSource) return null;
		host = null;
	}
	if (utmSource) {
		return {
			source: UTM_ALIASES[utmSource] ?? utmSource,
			medium: sourceToken(params.get('utm_medium')),
			campaign: sourceToken(params.get('utm_campaign')),
			referrer_host: host,
		};
	}
	return {
		source: host ? (platformForHost(host) ?? 'other') : 'direct',
		medium: null,
		campaign: null,
		referrer_host: host,
	};
}

/// Records the tab's first touch, never overwriting one already there.
export function captureFirstTouch(
	store: SignupSourceStore | null,
	pathname: string,
	search: string,
	referrer: string | null | undefined,
	ownHost: string,
): void {
	if (!store) return;
	try {
		if (store.getItem(SIGNUP_SOURCE_KEY) !== null) return;
		const touch = firstTouchFrom(pathname, search, referrer, ownHost);
		if (touch) store.setItem(SIGNUP_SOURCE_KEY, JSON.stringify(touch));
	} catch {
		/* Storage refused (private mode, blocked site data): the sign-up records no source. */
	}
}

function tokenOrNull(v: unknown): string | null {
	return typeof v === 'string' && TOKEN.test(v) ? v : null;
}

/// The stored first touch, revalidated, or null. Left in place: a sign-up
/// that fails and is retried sends it again.
export function readFirstTouch(store: SignupSourceStore | null): SignupSource | null {
	if (!store) return null;
	let raw: string | null;
	try {
		raw = store.getItem(SIGNUP_SOURCE_KEY);
	} catch {
		return null;
	}
	if (!raw) return null;
	try {
		const parsed = JSON.parse(raw) as Record<string, unknown>;
		const source = tokenOrNull(parsed.source);
		if (!source) return null;
		const host = parsed.referrer_host;
		return {
			source,
			medium: tokenOrNull(parsed.medium),
			campaign: tokenOrNull(parsed.campaign),
			referrer_host: typeof host === 'string' && HOST.test(host) ? host : null,
		};
	} catch {
		return null;
	}
}

/// sessionStorage, or null where reading it throws (sandboxed frames, blocked
/// site data).
export function browserSessionStore(): SignupSourceStore | null {
	return sessionStore();
}

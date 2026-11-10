/**
 * Links in a direct message (issue #1216). A link is drawn as its text plus
 * a chip naming its domain, worked out here from the text alone: nothing is
 * fetched, so there is no server-side request to aim at an internal address
 * and no request that tells a third party who opened the message. The
 * anchor carries rel="noopener noreferrer nofollow ugc".
 *
 * Only an http(s) URL with an ASCII host and no user-info becomes a link. A
 * host in another script stays text, because a look-alike domain is the
 * phishing case a domain chip exists to expose, and `user@` before a host is
 * the old way of making one domain read as another. Mobile twin: `dm_link.dart`.
 */

export const DM_LINK_REL = 'noopener noreferrer nofollow ugc';

export type DmTextSegment =
	| { kind: 'text'; text: string }
	| { kind: 'link'; text: string; href: string; domain: string };

const URL_RE = /https?:\/\/[^\s<>"'`\u0080-\uFFFF]+/gi;
const TRAILING = /[.,;:!?'"\]}>]+$/;
const ASCII_HOST = /^[a-z0-9.-]+$/;

function trimTrailing(candidate: string): string {
	let url = candidate.replace(TRAILING, '');
	while (url.endsWith(')') && (url.match(/\(/g)?.length ?? 0) < (url.match(/\)/g)?.length ?? 0)) {
		url = url.slice(0, -1).replace(TRAILING, '');
	}
	return url;
}

/**
 * The domain a chip shows for `url`, or null when it must stay text: not
 * http(s), user-info present, a host outside [a-z0-9.-], or no dot in it.
 * A leading `www.` is dropped.
 */
export function dmLinkDomain(url: string): string | null {
	const m = /^(https?):\/\/([^/?#]*)/i.exec(url);
	if (!m) return null;
	const authority = m[2];
	if (authority.includes('@')) return null;
	const host = authority.replace(/:\d*$/, '').toLowerCase();
	if (!ASCII_HOST.test(host) || !host.includes('.')) return null;
	if (host.startsWith('.') || host.endsWith('.') || host.includes('..')) return null;
	return host.startsWith('www.') ? host.slice(4) : host;
}

/** The message text cut into plain runs and links, in order. */
export function dmTextSegments(body: string): DmTextSegment[] {
	const out: DmTextSegment[] = [];
	let at = 0;
	for (const match of body.matchAll(URL_RE)) {
		const start = match.index ?? 0;
		const url = trimTrailing(match[0]);
		const domain = dmLinkDomain(url);
		if (!domain) continue;
		if (start > at) out.push({ kind: 'text', text: body.slice(at, start) });
		out.push({ kind: 'link', text: url, href: url, domain });
		at = start + url.length;
	}
	if (at < body.length) out.push({ kind: 'text', text: body.slice(at) });
	return out;
}

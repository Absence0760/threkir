/// Per-challenge `<head>` meta-tag + JSON-LD builders for the public
/// share-challenge page. Pure string helpers used by the SvelteKit
/// +page.svelte (dev-server SSR) and the production share-entity Lambda,
/// the same split as the sibling share_*_meta.ts modules.
///
/// Locale-neutral on purpose, like every unfurl: a crawler's preview must not
/// change with whoever triggered the scrape.

import { formatDateStable, formatKmStable, normaliseSiteUrl } from './share_meta';
import { escapeHtml } from '../util/html_escape';
import { serialiseJsonLd } from '../util/json_ld';
import { collapseAndClip } from '../util/clip_text';
import type { SharedChallenge } from './share_challenge_lookup';

const SITE_NAME = 'Threkir';

/// The goal in stable English: "50 km", "10 h", "20 activities", "30 days".
export function challengeGoalStable(c: Pick<SharedChallenge, 'metric' | 'goal_value'>): string {
	const v = c.goal_value;
	if (v == null || !Number.isFinite(v) || v <= 0) return '';
	switch (c.metric) {
		case 'distance':
			return formatKmStable(v);
		case 'duration': {
			const h = Math.round((v / 3600) * 10) / 10;
			return `${h} h`;
		}
		case 'vert':
			return `${Math.round(v)} m`;
		case 'activity_count':
			return `${Math.round(v)} activities`;
		case 'streak_days':
			return `${Math.round(v)} days`;
		case 'park_courses':
			return `${Math.round(v)} park courses`;
	}
}

export function challengeWindowStable(c: Pick<SharedChallenge, 'starts_at' | 'ends_at'>): string {
	const a = formatDateStable(c.starts_at);
	const b = formatDateStable(c.ends_at);
	return a && b ? `${a} – ${b}` : a || b;
}

export function buildChallengeShareTitle(c: SharedChallenge | null | undefined): string {
	const t = collapseAndClip(c?.title, 80);
	return t ? `${t} — ${SITE_NAME}` : `Challenge — ${SITE_NAME}`;
}

export function buildChallengeShareDescription(c: SharedChallenge | null | undefined): string {
	if (!c) return `A running challenge on ${SITE_NAME}.`;
	const desc = collapseAndClip(c.description, 160);
	if (desc) return desc;
	const goal = challengeGoalStable(c);
	const window = challengeWindowStable(c);
	const parts = [goal && `Goal ${goal}`, window].filter(Boolean).join(' · ');
	return parts
		? `A running challenge on ${SITE_NAME}: ${parts}.`
		: `A running challenge on ${SITE_NAME}.`;
}

export function buildChallengeShareCanonical(
	base: string | null | undefined,
	id: string,
): string {
	return `${normaliseSiteUrl(base)}/share/challenge/${id}`;
}

export function buildChallengeOgImageUrl(base: string | null | undefined, id: string): string {
	return `${normaliseSiteUrl(base)}/og/challenge/${id}.png`;
}

/// schema.org JSON-LD: an `Event` with its window. User-controlled text is
/// escaped for the script-element context by serialiseJsonLd.
export function buildChallengeJsonLd(
	c: SharedChallenge | null | undefined,
	opts: { id: string; base: string | null | undefined },
): string {
	const canonical = buildChallengeShareCanonical(opts.base, opts.id);
	const graph: Record<string, unknown> = {
		'@context': 'https://schema.org',
		'@type': 'Event',
		name: collapseAndClip(c?.title, 120) || 'Challenge',
		description: buildChallengeShareDescription(c),
		url: canonical,
		image: buildChallengeOgImageUrl(opts.base, opts.id),
		eventAttendanceMode: 'https://schema.org/OnlineEventAttendanceMode',
		location: { '@type': 'VirtualLocation', url: canonical },
		organizer: { '@type': 'Organization', name: SITE_NAME, url: normaliseSiteUrl(opts.base) },
	};
	if (c?.starts_at) graph.startDate = c.starts_at;
	if (c?.ends_at) graph.endDate = c.ends_at;
	return serialiseJsonLd(graph);
}

export interface ShareChallengeHead {
	title: string;
	description: string;
	canonical: string;
	ogImageUrl: string;
	jsonLd: string;
}

export function buildShareChallengeHead(input: {
	id: string;
	challenge: SharedChallenge | null;
	siteUrl: string;
}): ShareChallengeHead {
	const { id, challenge, siteUrl } = input;
	return {
		title: buildChallengeShareTitle(challenge),
		description: buildChallengeShareDescription(challenge),
		canonical: buildChallengeShareCanonical(siteUrl, id),
		ogImageUrl: buildChallengeOgImageUrl(siteUrl, id),
		jsonLd: buildChallengeJsonLd(challenge, { id, base: siteUrl }),
	};
}

export function renderShareChallengeHeadTags(head: ShareChallengeHead): string {
	const e = escapeHtml;
	return [
		`<title>${e(head.title)}</title>`,
		`<meta name="description" content="${e(head.description)}">`,
		`<link rel="canonical" href="${e(head.canonical)}">`,
		`<meta property="og:title" content="${e(head.title)}">`,
		`<meta property="og:description" content="${e(head.description)}">`,
		`<meta property="og:type" content="website">`,
		`<meta property="og:url" content="${e(head.canonical)}">`,
		`<meta property="og:image" content="${e(head.ogImageUrl)}">`,
		`<meta property="og:image:width" content="1200">`,
		`<meta property="og:image:height" content="630">`,
		`<meta property="og:site_name" content="Threkir">`,
		`<meta name="twitter:card" content="summary_large_image">`,
		`<meta name="twitter:title" content="${e(head.title)}">`,
		`<meta name="twitter:description" content="${e(head.description)}">`,
		`<meta name="twitter:image" content="${e(head.ogImageUrl)}">`,
		`<script type="application/ld+json">${head.jsonLd}</script>`,
	].join('\n\t');
}

/// Per-plan `<head>` meta-tag + JSON-LD builders for the public share-plan
/// page. Pure string helpers, used by the SvelteKit +page.svelte (dev-server
/// SSR) and the production entity-SSR Lambda.
///
/// Privacy boundary: every field read here comes from `public_plan_share`,
/// which already withholds physiology, paces, notes, dates and the user id
/// (decisions § 2262). The meta says what the plan trains for, how long it is
/// and who wrote it, and nothing a workout row says.
///
/// The strings are English and the distance is in kilometres, deliberately
/// ignoring the viewer's locale and unit: an unfurl must not change with who
/// triggered the scrape. See share_meta.ts's header for the argument.

import { normaliseSiteUrl } from './share_meta';
import { escapeHtml } from '../util/html_escape';
import { serialiseJsonLd } from '../util/json_ld';
import { collapseAndClip } from '../util/clip_text';
import type { SharedPlan, SharedPlanAuthor } from './share_plan_lookup';

const SITE_NAME = 'Threkir';

/// What the plan trains for, in the unfurl's fixed English.
export function planGoalEnglish(plan: Pick<SharedPlan, 'goal_event' | 'goal_distance_m'>): string {
	switch (plan.goal_event) {
		case 'distance_5k':
			return '5K';
		case 'distance_10k':
			return '10K';
		case 'distance_half':
			return 'half marathon';
		case 'distance_full':
			return 'marathon';
		default: {
			const km = plan.goal_distance_m / 1000;
			if (!(km > 0)) return 'custom goal';
			const rounded = Math.round(km * 10) / 10;
			return `${Number.isInteger(rounded) ? rounded.toFixed(0) : rounded.toFixed(1)} km`;
		}
	}
}

/// The name the author is credited by: their handle when they set one,
/// otherwise their display name, otherwise null (a private profile).
export function planAuthorCredit(author: SharedPlanAuthor | null | undefined): string | null {
	const handle = collapseAndClip(author?.handle, 40);
	if (handle) return `@${handle}`;
	return collapseAndClip(author?.name, 60) || null;
}

export function buildPlanShareTitle(plan: SharedPlan | null | undefined): string {
	if (!plan) return `Training plan — ${SITE_NAME}`;
	const name = collapseAndClip(plan.name, 80);
	return name ? `${name} — ${SITE_NAME}` : `Training plan — ${SITE_NAME}`;
}

export function buildPlanShareDescription(plan: SharedPlan | null | undefined): string {
	if (!plan) return `View a public training plan on ${SITE_NAME}.`;
	const weeks = plan.weeks.length;
	const bits: string[] = [`A ${planGoalEnglish(plan)} plan`];
	if (weeks > 0) bits.push(`${weeks} ${weeks === 1 ? 'week' : 'weeks'}`);
	if (plan.days_per_week > 0) bits.push(`${plan.days_per_week} days a week`);
	const by = planAuthorCredit(plan.author);
	if (by) bits.push(`by ${by}`);
	return `${bits.join(' · ')}. Start the same plan on ${SITE_NAME}.`;
}

/// Absolute canonical URL for a public plan share page. The library preview
/// builds its copyable share link from the same helper, so the two can never
/// drift apart.
export function buildPlanShareCanonical(base: string | null | undefined, id: string): string {
	return `${normaliseSiteUrl(base)}/share/plan/${id}`;
}

/// schema.org JSON-LD: a `WebPage` + a `BreadcrumbList` (Home → plan), the
/// same honest shape the session and workout share pages use. `ExercisePlan`
/// is refused for the reason given there: its supertype chain runs through
/// `MedicalEntity`. Name and author are user-controlled, so the output goes
/// through `serialiseJsonLd` before it reaches the DOM.
export function buildPlanJsonLd(
	plan: SharedPlan | null | undefined,
	opts: { id: string; base: string | null | undefined },
): string {
	const base = normaliseSiteUrl(opts.base);
	const canonical = buildPlanShareCanonical(base, opts.id);
	const full = buildPlanShareTitle(plan);
	const suffix = ` — ${SITE_NAME}`;
	const name = full.endsWith(suffix) ? full.slice(0, -suffix.length) : full;
	return serialiseJsonLd({
		'@context': 'https://schema.org',
		'@type': 'WebPage',
		name,
		description: buildPlanShareDescription(plan),
		url: canonical,
		breadcrumb: {
			'@type': 'BreadcrumbList',
			itemListElement: [
				{ '@type': 'ListItem', position: 1, name: SITE_NAME, item: `${base}/` },
				{ '@type': 'ListItem', position: 2, name },
			],
		},
	});
}

export interface SharePlanMetaInput {
	id: string;
	plan: SharedPlan | null;
	siteUrl: string;
}

export interface SharePlanHead {
	title: string;
	description: string;
	canonical: string;
	ogImageUrl: string;
	jsonLd: string;
}

export function buildSharePlanHead(input: SharePlanMetaInput): SharePlanHead {
	const { id, plan, siteUrl } = input;
	const base = normaliseSiteUrl(siteUrl);
	return {
		title: buildPlanShareTitle(plan),
		description: buildPlanShareDescription(plan),
		canonical: buildPlanShareCanonical(siteUrl, id),
		ogImageUrl: `${base}/og-default.png`,
		jsonLd: buildPlanJsonLd(plan, { id, base: siteUrl }),
	};
}

export function renderSharePlanHeadTags(head: SharePlanHead): string {
	const e = escapeHtml;
	return [
		`<title>${e(head.title)}</title>`,
		`<meta name="description" content="${e(head.description)}">`,
		`<link rel="canonical" href="${e(head.canonical)}">`,
		`<meta property="og:title" content="${e(head.title)}">`,
		`<meta property="og:description" content="${e(head.description)}">`,
		`<meta property="og:type" content="article">`,
		`<meta property="og:url" content="${e(head.canonical)}">`,
		`<meta property="og:image" content="${e(head.ogImageUrl)}">`,
		`<meta property="og:image:width" content="1200">`,
		`<meta property="og:image:height" content="630">`,
		`<meta property="og:site_name" content="${SITE_NAME}">`,
		`<meta name="twitter:card" content="summary_large_image">`,
		`<meta name="twitter:title" content="${e(head.title)}">`,
		`<meta name="twitter:description" content="${e(head.description)}">`,
		`<meta name="twitter:image" content="${e(head.ogImageUrl)}">`,
		`<script type="application/ld+json">${head.jsonLd}</script>`,
	].join('\n\t');
}

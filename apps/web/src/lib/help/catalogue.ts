// The pure index over the help guides: lookup, grouping, route matching and
// search. `index.ts` binds it to the guide files through Vite's glob; this
// module takes the guides as an argument so the unit suite (raw tsx, no Vite)
// can build the same index from the files on disk.

import { fold } from '../segments/catalogue_browse';
import { plainText } from './markup';
import type { Audience, Block, Guide, GuideCategory, GuideKind, Platform, Requirement } from './types';

/// Display order of the contents page, and the full set a guide may name.
export const GUIDE_CATEGORIES: readonly GuideCategory[] = [
	'running',
	'races',
	'clubs',
	'paid-classes',
	'instructors',
	'account',
];
export const GUIDE_KINDS: readonly GuideKind[] = ['start', 'how-to', 'explainer'];
export const AUDIENCES: readonly Audience[] = [
	'everyone',
	'runner',
	'organiser',
	'participant',
	'spectator',
	'instructor',
	'club-admin',
];
export const REQUIREMENTS: readonly Requirement[] = [
	'pro',
	'club-admin',
	'race-director',
	'stripe-connected',
	'paid-rail-live',
];
export const PLATFORMS: readonly Platform[] = ['web', 'android', 'ios', 'wear', 'apple-watch'];

export interface CategoryGroup {
	category: GuideCategory;
	guides: Guide[];
}

export interface HelpIndex {
	allGuides(): Guide[];
	guideFor(id: string): Guide | undefined;
	guidesByCategory(): CategoryGroup[];
	guidesForRoute(routeId: string): Guide[];
	searchGuides(query: string): Guide[];
}

function blockText(block: Block): string {
	switch (block.type) {
		case 'steps':
		case 'list':
			return block.items.map(plainText).join(' ');
		default:
			return plainText(block.text);
	}
}

function byKindThenTitle(a: Guide, b: Guide): number {
	return GUIDE_KINDS.indexOf(a.kind) - GUIDE_KINDS.indexOf(b.kind) || a.title.localeCompare(b.title, 'en');
}

export function createHelpIndex(guides: readonly Guide[]): HelpIndex {
	const ordered = [...guides].sort(
		(a, b) => GUIDE_CATEGORIES.indexOf(a.category) - GUIDE_CATEGORIES.indexOf(b.category) || byKindThenTitle(a, b),
	);
	const byId = new Map(ordered.map((g) => [g.id, g]));
	const haystacks = ordered.map((g) => ({
		guide: g,
		title: fold(g.title),
		summary: fold(g.summary),
		body: fold(g.sections.flatMap((s) => [s.heading, ...s.blocks.map(blockText)]).join(' ')),
	}));

	return {
		allGuides: () => [...ordered],
		guideFor: (id) => byId.get(id),
		guidesByCategory: () =>
			GUIDE_CATEGORIES.map((category) => ({
				category,
				guides: ordered.filter((g) => g.category === category),
			})).filter((group) => group.guides.length > 0),
		guidesForRoute: (routeId) => ordered.filter((g) => g.routes?.includes(routeId)),
		// Every word must match somewhere; a word in the title outranks one in
		// the summary, which outranks one in the body. Ties keep contents order.
		searchGuides: (query) => {
			const words = fold(query).split(/\s+/).filter(Boolean);
			if (words.length === 0) return [];
			const scored: { guide: Guide; score: number; order: number }[] = [];
			haystacks.forEach((h, order) => {
				let score = 0;
				for (const word of words) {
					if (h.title.includes(word)) score += 100;
					else if (h.summary.includes(word)) score += 10;
					else if (h.body.includes(word)) score += 1;
					else return;
				}
				scored.push({ guide: h.guide, score, order });
			});
			return scored.sort((a, b) => b.score - a.score || a.order - b.order).map((s) => s.guide);
		},
	};
}

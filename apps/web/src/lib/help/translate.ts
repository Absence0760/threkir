// A guide in the reader's language (docs/features/help.md § Translation). A
// translation carries only words; this lays them over the English guide. It
// imports nothing at run time, so scripts/gen_help_guides.mjs loads it under
// plain Node to write the same merge into every per-locale JSON file.

import type { Block, Guide, GuideSection, GuideTranslation, LocalizedGuide } from './types';

export const SOURCE_LANG = 'en';

/// Every string a translation translates, each with its path: `title`,
/// `summary`, `s<n>.heading`, `s<n>.b<m>` for a paragraph, a note or an
/// illustration's alt text, and
/// `s<n>.b<m>.i<k>` for a step or list item, all counted from 0. A
/// translation records a hash of the English at each path (`sources`), so an
/// English edit stales only the strings it touched. The same paths key the
/// translator batches, as `web:help.<guide id>.<path>`.
export function translatableStrings(guide: Pick<Guide, 'title' | 'summary' | 'sections'>): [path: string, text: string][] {
	const out: [string, string][] = [
		['title', guide.title],
		['summary', guide.summary],
	];
	guide.sections.forEach((section, si) => {
		out.push([`s${si}.heading`, section.heading]);
		section.blocks.forEach((block, bi) => {
			if (block.type === 'p' || block.type === 'note') out.push([`s${si}.b${bi}`, block.text]);
			else if (block.type === 'illustration') out.push([`s${si}.b${bi}`, block.alt]);
			else block.items.forEach((item, ii) => out.push([`s${si}.b${bi}.i${ii}`, item]));
		});
	});
	return out;
}

/// Where a path from `translatableStrings` sits, for a person: "section 2
/// block 1 item 3", or the path itself for the title and summary.
export function describePath(path: string): string {
	const m = /^s(\d+)\.(?:heading|b(\d+)(?:\.i(\d+))?)$/.exec(path);
	if (!m) return path;
	const [, s, b, i] = m;
	if (b === undefined) return `section ${Number(s) + 1} heading`;
	return `section ${Number(s) + 1} block ${Number(b) + 1}${i === undefined ? '' : ` item ${Number(i) + 1}`}`;
}

/// Where a translation's shape departs from its guide's: one message per
/// difference, empty when every section and block lines up.
export function structureProblems(guide: Guide, translation: GuideTranslation): string[] {
	const problems: string[] = [];
	if (translation.id !== guide.id) problems.push(`translates "${translation.id}", not "${guide.id}"`);
	if (translation.sections.length !== guide.sections.length) {
		problems.push(`${translation.sections.length} sections, the guide has ${guide.sections.length}`);
		return problems;
	}
	guide.sections.forEach((section, si) => {
		const other = translation.sections[si]!;
		if (other.blocks.length !== section.blocks.length) {
			problems.push(`section ${si + 1}: ${other.blocks.length} blocks, the guide has ${section.blocks.length}`);
			return;
		}
		section.blocks.forEach((block, bi) => {
			const theirs = other.blocks[bi]!;
			const where = `section ${si + 1} block ${bi + 1}`;
			if (theirs.type !== block.type) {
				problems.push(`${where}: a ${theirs.type}, the guide has a ${block.type}`);
			} else if (block.type === 'note' && theirs.type === 'note' && theirs.tone !== block.tone) {
				problems.push(`${where}: a ${theirs.tone} note, the guide has a ${block.tone} note`);
			} else if (block.type === 'illustration' && theirs.type === 'illustration' && theirs.id !== block.id) {
				problems.push(`${where}: illustration "${theirs.id}", the guide has "${block.id}"`);
			} else if ((block.type === 'steps' || block.type === 'list') && (theirs.type === 'steps' || theirs.type === 'list')) {
				if (theirs.items.length !== block.items.length) {
					problems.push(`${where}: ${theirs.items.length} items, the guide has ${block.items.length}`);
				}
			}
		});
	});
	return problems;
}

/// The guide in `lang` when `translation` lines up with it, else the English
/// guide marked as English. Block types and tones always come from the guide.
export function localizeGuide(guide: Guide, translation: GuideTranslation | undefined, lang: string): LocalizedGuide {
	if (!translation || lang === SOURCE_LANG || structureProblems(guide, translation).length > 0) {
		return { ...guide, lang: SOURCE_LANG };
	}
	const sections = guide.sections.map((section, si) => {
		const other = translation.sections[si]!;
		return {
			heading: other.heading,
			blocks: section.blocks.map((block, bi): Block => {
				const theirs = other.blocks[bi]!;
				switch (block.type) {
					case 'p':
						return { type: 'p', text: 'text' in theirs ? theirs.text : block.text };
					case 'note':
						return { type: 'note', tone: block.tone, text: 'text' in theirs ? theirs.text : block.text };
					case 'steps':
						return { type: 'steps', items: 'items' in theirs ? [...theirs.items] : block.items };
					case 'list':
						return { type: 'list', items: 'items' in theirs ? [...theirs.items] : block.items };
					case 'illustration':
						return { type: 'illustration', id: block.id, alt: 'alt' in theirs ? theirs.alt : block.alt };
				}
			}),
		};
	});
	return { ...guide, title: translation.title, summary: translation.summary, sections, lang };
}

function isSection(value: unknown): value is GuideSection {
	if (!value || typeof value !== 'object') return false;
	const s = value as { heading?: unknown; blocks?: unknown };
	return (
		typeof s.heading === 'string' &&
		Array.isArray(s.blocks) &&
		s.blocks.every((b: unknown) => {
			if (!b || typeof b !== 'object') return false;
			const block = b as { text?: unknown; items?: unknown; alt?: unknown };
			return (
				typeof block.text === 'string' ||
				typeof block.alt === 'string' ||
				(Array.isArray(block.items) && block.items.every((i) => typeof i === 'string'))
			);
		})
	);
}

/// The guides from a fetched `guides.<lang>.json` (scripts/gen_help_guides.mjs),
/// one per English guide: the fetched one where it is well formed, in `lang`
/// and lines up with the guide, else the English guide. Anything the file holds
/// beyond the words — kind, routes, related — is taken from the English guide,
/// never from the file.
export function mergeFetchedGuides(english: readonly Guide[], raw: unknown, lang: string): LocalizedGuide[] {
	const fetched = new Map<string, GuideTranslation>();
	if (Array.isArray(raw)) {
		for (const item of raw as unknown[]) {
			if (!item || typeof item !== 'object') continue;
			const g = item as Record<string, unknown>;
			if (
				g.lang === lang &&
				typeof g.id === 'string' &&
				typeof g.title === 'string' &&
				typeof g.summary === 'string' &&
				Array.isArray(g.sections) &&
				g.sections.every(isSection)
			) {
				fetched.set(g.id, { id: g.id, sources: {}, title: g.title, summary: g.summary, sections: g.sections });
			}
		}
	}
	return english.map((guide) => localizeGuide(guide, fetched.get(guide.id), lang));
}

// The inline markup every help-guide string may carry, parsed into tokens so
// nothing renders through {@html}. The whole grammar (docs/features/help.md):
//
//   **Save**                      an on-screen label, in bold
//   *only once*                   emphasis
//   [[guide:<id>|label]]          a link to another guide
//   [[route:<route id>|label]]    a link to an app screen, by SvelteKit route id
//
// The mobile renderer parses the same grammar from the generated JSON, so a
// new form here is a new form there.

import { fold } from '../segments/catalogue_browse';

export type HelpToken =
	| { kind: 'text'; text: string }
	| { kind: 'strong'; text: string }
	| { kind: 'em'; text: string }
	| { kind: 'guide'; id: string; text: string }
	| { kind: 'route'; routeId: string; text: string }
	/** A `[[...]]` that is neither form above. Rendered as its label; the guard fails it. */
	| { kind: 'invalid'; raw: string; text: string };

// A link's body may hold single brackets (route ids do: `/runs/[id]`), so it
// ends at the first `]]`. Emphasis only where the asterisks stand apart from a
// word, so `a*b` is text.
const INLINE = /\*\*(.+?)\*\*|\[\[((?:[^\]]|\](?!\]))*)\]\]|(?<![\w*])\*([^*\s](?:[^*]*[^*\s])?)\*(?![\w*])/g;
const LINK = /^(guide|route):([^|]+)\|(.+)$/;

export function parseMarkup(text: string): HelpToken[] {
	const out: HelpToken[] = [];
	let last = 0;
	for (const match of text.matchAll(INLINE)) {
		if (match.index > last) out.push({ kind: 'text', text: text.slice(last, match.index) });
		last = match.index + match[0].length;
		if (match[1] !== undefined) {
			out.push({ kind: 'strong', text: match[1] });
		} else if (match[3] !== undefined) {
			out.push({ kind: 'em', text: match[3] });
		} else {
			const link = LINK.exec(match[2] ?? '');
			const target = link?.[2]?.trim() ?? '';
			const label = link?.[3]?.trim() ?? '';
			if (!link || !target || !label) {
				const raw = match[2] ?? '';
				out.push({ kind: 'invalid', raw, text: raw.split('|').pop()?.trim() || raw });
			} else if (link[1] === 'guide') {
				out.push({ kind: 'guide', id: target, text: label });
			} else {
				out.push({ kind: 'route', routeId: target, text: label });
			}
		}
	}
	if (last < text.length) out.push({ kind: 'text', text: text.slice(last) });
	return out;
}

export function plainText(text: string): string {
	return parseMarkup(text)
		.map((t) => t.text)
		.join('');
}

/// What is wrong with a string's markup, one message per problem; empty when
/// it parses cleanly. Every token's text is checked, so markup nested inside
/// bold (which the grammar does not support) is reported too.
export function markupProblems(text: string): string[] {
	const problems: string[] = [];
	for (const token of parseMarkup(text)) {
		if (token.kind === 'invalid') {
			problems.push(`unknown link "[[${token.raw}]]" (use [[guide:<id>|label]] or [[route:<route id>|label]])`);
			continue;
		}
		if (token.text.includes('*')) problems.push(`stray "*" in "${token.text}"`);
		if (token.text.includes('[[') || token.text.includes(']]')) problems.push(`unclosed link in "${token.text}"`);
		if (token.text.includes('<')) problems.push(`raw "<" in "${token.text}" (no HTML in guides)`);
	}
	return problems;
}

/// The concrete href for a route id, or null when the route takes params and
/// so has no single address (the label then renders as plain text). Route
/// groups — `(name)` segments — are not part of the URL.
export function routeHref(routeId: string): string | null {
	if (routeId.includes('[')) return null;
	const path = routeId
		.split('/')
		.filter((segment) => !/^\(.+\)$/.test(segment))
		.join('/');
	return path === '' ? '/' : path;
}

/// The in-page anchor for a guide section, from its heading. Letters of any
/// script survive, so a Japanese heading has an anchor too; an English one
/// folds to the same ASCII it always did.
export function sectionId(heading: string): string {
	return fold(heading)
		.replace(/[^\p{L}\p{N}]+/gu, '-')
		.replace(/^-|-$/g, '');
}

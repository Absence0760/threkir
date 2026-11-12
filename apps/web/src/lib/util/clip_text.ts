/**
 * Length-clipping for user-authored text that is about to be interpolated into
 * a `<head>` meta tag, an SVG text node, or a JSON-LD value — a share title, a
 * club description, a route name on an og:image card.
 *
 * `max` is a budget in GRAPHEME CLUSTERS: what a reader counts as characters,
 * and what the author counted when they wrote the description. It used to be a
 * budget in UTF-16 code units, which is what every caller's cap happened to be
 * measured in and is a different number for the same text depending on the
 * script — a 160-emoji club description was cut to 79 emoji against the budget
 * that keeps a 160-character CJK one whole (decisions § 1528).
 */

let cachedCtor: unknown = null;
let cachedSegmenter: Intl.Segmenter | null = null;

/**
 * The shared grapheme segmenter, or `null` where the runtime has none.
 *
 * Pinned to one locale so the boundaries do not move with the host's: ICU does
 * not tailor grapheme clusters by locale, but the argument is observable and a
 * fixed one is one less thing that can differ between the Lambda and the tab.
 *
 * Memoised on the constructor rather than on first call, because constructing
 * one is the expensive half and reading the property is free.
 */
function graphemeSegmenter(): Intl.Segmenter | null {
	const ctor = (Intl as { Segmenter?: typeof Intl.Segmenter }).Segmenter;
	if (typeof ctor !== 'function') return null;
	if (cachedCtor !== ctor) {
		cachedSegmenter = new ctor('en', { granularity: 'grapheme' });
		cachedCtor = ctor;
	}
	return cachedSegmenter;
}

/**
 * At most `max` grapheme clusters, with the last one spent on an ellipsis when
 * anything was dropped.
 *
 * The cut lands only on a cluster boundary, so no cluster is split: a ZWJ
 * sequence, a regional-indicator flag pair, a skin-tone modifier and a base
 * letter with its combining mark each survive whole or are dropped whole. A
 * surrogate pair is inside a cluster, so the well-formedness the previous
 * code-unit cut had to step back to protect (§ 1478) now holds by
 * construction — a lone surrogate has no UTF-8 encoding, so one reaching the
 * response encoder became U+FFFD on the end of an og:description.
 *
 * `s.length` is the code-unit count, which is never below the cluster count,
 * so a string short enough by that measure is short enough by this one — and
 * that fast path is every call the clipper actually gets.
 *
 * Where the runtime has no `Intl.Segmenter` the budget degrades to code units
 * with the § 1478 step-back, which is well-formed but can split a cluster.
 * That is the previous behaviour exactly, so the fallback is never worse than
 * what shipped before.
 *
 * The floor now says who it is for, which is the question § 1529 had to leave
 * open: Firefox 121-124, and nothing else. Every other browser
 * `apps/web/package.json` supports has had the constructor since 2021, and
 * every share Lambda is Node 24 with full ICU. Those four releases cost a
 * title cut inside a cluster in the tab where the crawler was served the
 * cluster-boundary cut; deleting the fallback instead would cost a thrown
 * TypeError in a `<head>` that every share page rebuilds during hydration —
 * a blank page rather than a clipped title — and raising the floor past them
 * to make that safe costs 0.35% of globally tracked page views for a
 * cosmetic guarantee. So it stays until the floor reaches Firefox 125, which
 * `browser_baseline_guard.test.ts` fails on (conventions.md § Web browser
 * baseline, decisions § 1670).
 */
export function clipText(s: string, max: number): string {
	if (s.length <= max) return s;

	const seg = graphemeSegmenter();
	if (!seg) return clipCodeUnits(s, max);

	const keep = Math.max(0, max - 1);
	let end = 0;
	let seen = 0;
	for (const { index } of seg.segment(s)) {
		if (seen === keep) end = index;
		seen++;
		if (seen > max) break;
	}
	if (seen <= max) return s;
	return `${s.slice(0, end).trimEnd()}…`;
}

/**
 * A code-unit index can land between the two halves of a surrogate pair, and
 * slicing there emits a lone surrogate. So the cut steps back off a high
 * surrogate and drops the character whole.
 */
function clipCodeUnits(s: string, max: number): string {
	const at = Math.max(0, max - 1);
	const before = at > 0 ? s.charCodeAt(at - 1) : 0;
	const end = before >= 0xd800 && before <= 0xdbff ? at - 1 : at;
	return `${s.slice(0, end).trimEnd()}…`;
}

/**
 * Collapse runs of whitespace, trim, then clip. A non-string (a `null` column,
 * a number out of a jsonb bag) is nothing to say, so it yields `''` rather
 * than the word `null`.
 */
export function collapseAndClip(raw: unknown, max: number): string {
	const collapsed = (typeof raw === 'string' ? raw : '').replace(/\s+/g, ' ').trim();
	if (!collapsed) return '';
	return clipText(collapsed, max);
}

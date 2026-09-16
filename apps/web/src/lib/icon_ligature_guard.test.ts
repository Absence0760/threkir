// Source-scan guard for the one thing that silently turns an icon back into
// its own name.
//
// Every web icon is a LIGATURE: `<span class="material-symbols">terrain</span>`
// ships the eight letters `terrain` and the font shapes them into one glyph.
// Two inherited properties stop that shaping, and both are ordinary things to
// put on a label:
//
//   letter-spacing  a per-character advance cannot be applied to a glyph that
//                   spans several characters, so the shaper declines the
//                   substitution and lays out the letters
//   text-transform  `TERRAIN` is not a ligature the font carries, so there is
//                   nothing to substitute
//
// Neither is ever set ON the icon span. They are INHERITED — from the uppercase
// tracked micro-label the icon sits inside, which is the single most common
// place an icon goes. That is why the reset has to be unconditional rather than
// per-site, and why a reviewer reading the icon's own markup can never see the
// bug coming.
//
// The failure is also quiet rather than loud. `.material-symbols` is
// `overflow: hidden` at `width: 1.25em`, so the unshaped name does not reflow
// the page — it renders in the fallback serif and is clipped to its first two
// letters. A route's surface tile read `AD Road`, its elevation tiles read
// `TR GAIN` / `TE MAX` / `VE MIN`, a gym workout read `LO PRIVATE`, and the
// plans list read `PL ACTIVE`. Ten icons across four pages, shipped, and every
// one of them looks at a glance like a deliberate two-letter abbreviation.
//
// `font-display: block` in the same file is the OTHER half of this and is not
// interchangeable with it: block covers the window before the font arrives,
// this covers the case where the font arrived and shaped nothing.
//
// A source scan only proves the base rule declares the reset. It cannot see a
// descendant rule setting `letter-spacing` back on a `.material-symbols`
// selector, and it cannot see the resolved cascade at all — that half is
// `tests-e2e/cross-cutting/icon-ligature.spec.ts`, which measures whether the
// text overflows its box on the pages that carried the defect.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const APP_CSS = resolve(__dirname, '../app.css');

/** The `.material-symbols { ... }` block body, without its braces. */
function iconRuleBody(): string {
	const css = readFileSync(APP_CSS, 'utf-8');
	const match = css.match(/(?<![\w-.])\.material-symbols\s*\{([^}]*)\}/);
	assert.ok(
		match,
		'app.css no longer declares a bare `.material-symbols` rule — the icon reset has to live somewhere a span inherits through.',
	);
	return match[1];
}

test('.material-symbols resets the two properties that break a ligature', () => {
	const body = iconRuleBody();

	assert.match(
		body,
		/(?<![\w-])letter-spacing:\s*normal\s*;/,
		'`.material-symbols` must declare `letter-spacing: normal`. Without it an icon inside a tracked label (a `.key-stat-label`, an `.elev-label`, any uppercase micro-label) renders its own ligature name clipped to two letters.',
	);

	assert.match(
		body,
		/(?<![\w-])text-transform:\s*none\s*;/,
		'`.material-symbols` must declare `text-transform: none`. Without it an icon inside an uppercase or capitalized label shapes nothing, because the font carries no `TERRAIN` ligature.',
	);
});

test('the icon box still clips, so a broken ligature cannot reflow the page', () => {
	// The reset above is what keeps the name from rendering. This is the
	// containment that keeps a future one — a third shaping-breaker, a font
	// that failed to parse — from pushing the layout around instead.
	assert.match(
		iconRuleBody(),
		/(?<![\w-])overflow:\s*hidden\s*;/,
		'`.material-symbols` must stay `overflow: hidden` — it is what bounds an unshaped ligature name to the icon slot.',
	);
});

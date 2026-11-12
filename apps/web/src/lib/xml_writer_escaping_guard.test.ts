// Every module that writes an XML document — GPX, KML, SVG, a sitemap —
// escapes through `escapeXml`, never `escapeHtml`. The two agree on the five
// reserved characters, which is why the difference is invisible in review:
// only `escapeXml` also replaces the code points XML 1.0 cannot carry, and one
// of those in a route name, event title or imported finisher name made resvg,
// a browser or a GPX reader refuse the whole document (this round's fixes).
// The set is found by what a module EMITS, so a new writer is covered the day
// it is added.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const LIB = dirname(fileURLToPath(import.meta.url));

function sources(dir: string): string[] {
	const out: string[] = [];
	for (const entry of readdirSync(dir)) {
		const path = join(dir, entry);
		if (statSync(path).isDirectory()) out.push(...sources(path));
		else if (entry.endsWith('.ts') && !entry.endsWith('.test.ts') && !entry.endsWith('.d.ts')) out.push(path);
	}
	return out;
}

const EMITS_XML = /<\?xml|`<svg|'<svg|<kml\b|<gpx\b|<urlset\b/;

test('every XML writer escapes text with escapeXml, not escapeHtml', () => {
	const writers = sources(LIB).filter((f) => EMITS_XML.test(readFileSync(f, 'utf-8')));
	// The guard has to be looking at something: the GPX, SVG and sitemap writers.
	assert.ok(writers.length >= 8, `found only ${writers.length} XML writers`);
	for (const f of writers) {
		const src = readFileSync(f, 'utf-8');
		const rel = relative(LIB, f);
		assert.ok(!/\bescapeHtml\(/.test(src), `${rel} writes XML but escapes with escapeHtml`);
	}
});

// `InfoTip` renders a button whose accessible name names its subject ("About
// Strava"). Placed INSIDE a heading, that name is folded into the heading's
// own: `<h3>Strava <InfoTip …/></h3>` is announced as "Strava About Strava", so
// a screen-reader user moving by heading hears every provider twice, and a
// `getByRole('heading', { name: 'Strava', exact: true })` stops matching. The
// settings page shipped exactly that on all four of its InfoTip sites, and the
// surface smoke test was the only thing that noticed — in one e2e shard, on a
// run that had already cost a push. The tip belongs BESIDE its heading, in a
// row the two share.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, relative } from 'node:path';

const SRC = join(import.meta.dirname, '..');

function svelteFiles(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		const full = join(dir, entry.name);
		if (entry.isDirectory()) svelteFiles(full, out);
		else if (entry.name.endsWith('.svelte')) out.push(full);
	}
	return out;
}

/// One pass over the markup. Comments and script / style blocks are consumed
/// whole as tokens of their own, so a heading tag quoted inside either can
/// neither open nor close anything.
const TOKEN =
	/<!--[\s\S]*?(?:-->|$)|<script\b[\s\S]*?<\/script(?=[\s/>])[^>]*>|<style\b[\s\S]*?<\/style(?=[\s/>])[^>]*>|<(\/?)h([1-6])\b[^>]*>|<InfoTip\b/g;

/// The line of every `<InfoTip` that sits inside an open heading element.
function infoTipsInHeadings(source: string): { nested: number[]; total: number } {
	const nested: number[] = [];
	let total = 0;
	let depth = 0;
	for (const m of source.matchAll(TOKEN)) {
		if (m[2] !== undefined) {
			depth = Math.max(0, depth + (m[1] ? -1 : 1));
		} else if (m[0] === '<InfoTip') {
			total++;
			if (depth > 0) nested.push(source.slice(0, m.index).split('\n').length);
		}
	}
	return { nested, total };
}

test('infoTipsInHeadings finds a nested tip and passes a sibling or a commented one', () => {
	assert.deepEqual(infoTipsInHeadings('<h3>\n\tStrava\n\t<InfoTip label="x" />\n</h3>'), {
		nested: [3],
		total: 1
	});
	assert.deepEqual(
		infoTipsInHeadings('<div class="title-row">\n\t<h2>Strava</h2>\n\t<InfoTip label="x" />\n</div>'),
		{ nested: [], total: 1 }
	);
	assert.deepEqual(infoTipsInHeadings('<!-- <h2> is not open here -->\n<InfoTip label="x" />'), {
		nested: [],
		total: 1
	});
	assert.deepEqual(
		infoTipsInHeadings("<script>const tag = '<h2>';</script>\n<InfoTip label=\"x\" />"),
		{ nested: [], total: 1 }
	);
});

test('no InfoTip is rendered inside a heading', () => {
	const offenders: string[] = [];
	let total = 0;
	for (const file of svelteFiles(SRC)) {
		const found = infoTipsInHeadings(readFileSync(file, 'utf-8'));
		total += found.total;
		for (const line of found.nested) offenders.push(`${relative(SRC, file)}:${line}`);
	}
	// A scan that matched nothing would pass here for the wrong reason.
	assert.ok(total > 0, 'no <InfoTip usage found under src — the scan is not reading markup');
	assert.deepEqual(
		offenders,
		[],
		`An InfoTip inside a heading folds its "About …" label into the heading's ` +
			`accessible name. Put the heading and the tip side by side in a shared row:\n  ` +
			offenders.join('\n  ')
	);
});

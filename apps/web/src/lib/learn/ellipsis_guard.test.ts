import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

// The public Learn guides write the one-character ellipsis "…" (U+2026), never
// three full stops, which can wrap between the dots and read as three
// sentences to a screen reader (decisions § 2539, § 2556, § 2571). The guides
// are MDsvex prose read straight off disk, as guides.test.ts does, so this
// checks the reader's text only: the frontmatter values and the body, with
// fenced and inline code, link and image targets, autolinks, bare URLs and
// HTML comments removed first, since `...` there is syntax, not punctuation.

const GUIDES_DIR = join(import.meta.dirname, 'guides');

// Blanks a removed span but keeps its newlines, so an offender's line number
// still points into the file.
const keepLines = (span: string): string => span.replace(/[^\n]/g, '');

function proseOf(src: string): string {
	return src
		.replace(/^(```|~~~)[^\n]*\n[\s\S]*?^\1[^\n]*$/gm, keepLines)
		.replace(/`[^`\n]*`/g, '')
		.replace(/<!--[\s\S]*?-->/g, keepLines)
		.replace(/\]\([^)\s]*(?:\s+"[^"]*")?\)/g, ']')
		.replace(/<https?:[^>\s]*>/g, '')
		.replace(/https?:\/\/\S+/g, '');
}

function offenders(name: string, src: string): string[] {
	return proseOf(src)
		.split('\n')
		.flatMap((line, i) => (line.includes('...') ? [`${name}:${i + 1}: ${line.trim()}`] : []));
}

const files = readdirSync(GUIDES_DIR).filter((f) => f.endsWith('.md'));

test('Learn guides: an ellipsis is the single character, never three full stops', () => {
	assert.ok(files.length > 20, 'the guide reader found the guides');
	const found = files.flatMap((f) => offenders(f, readFileSync(join(GUIDES_DIR, f), 'utf8')));
	assert.deepEqual(found, []);
});

test('the Learn guard catches the slips it exists for', () => {
	assert.equal(offenders('x', 'Then, slowly... you run.').length, 1);
	assert.equal(offenders('x', 'title: "Wait..."').length, 1);
	assert.equal(offenders('x', 'まず歩いて...').length, 1);
	assert.equal(offenders('x', 'Then, slowly… you run.').length, 0);
	assert.equal(offenders('x', 'Spread with `[...a]` first.').length, 0);
	assert.equal(offenders('x', '```ts\nconst b = [...a];\n```').length, 0);
	assert.equal(offenders('x', 'See [the guide](https://example.com/a...b) now.').length, 0);
	assert.equal(offenders('x', 'Visit https://example.com/a...b today.').length, 0);
	assert.equal(offenders('x', '<!-- TODO... -->').length, 0);
});

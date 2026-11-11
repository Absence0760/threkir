// `<Modal bodyClass="x">` puts `x` on an element Modal renders, so a plain
// `.x` rule in the caller's <style> is scoped to the caller and never matches:
// Svelte drops it as unused and the dialog silently loses that layout. Every
// ConfirmDialog in the app shipped its actions flush under the message that
// way, and four other dialogs lost their body spacing the same way. A rule for
// a class handed to Modal has to be written `:global(.x)`.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, relative } from 'node:path';

const SRC = join(import.meta.dirname, '..', '..');

function svelteFiles(dir: string): string[] {
	return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
		const path = join(dir, entry.name);
		if (entry.isDirectory()) return svelteFiles(path);
		return entry.name.endsWith('.svelte') ? [path] : [];
	});
}

/// The plain (scoped) uses of `.name` in the file's <style> blocks.
function scopedUses(source: string, name: string): number {
	const styles = [...source.matchAll(/<style[^>]*>([\s\S]*?)<\/style(?=[\s/>])[^>]*>/g)].map((m) => m[1]);
	const escaped = name.replace(/[-]/g, '\\-');
	const any = new RegExp(`\\.${escaped}(?![\\w-])`, 'g');
	const global = new RegExp(`:global\\(\\s*\\.${escaped}(?![\\w-])`, 'g');
	return styles.reduce(
		(n, css) => n + (css.match(any)?.length ?? 0) - (css.match(global)?.length ?? 0),
		0,
	);
}

test('a class handed to Modal through bodyClass is styled with :global()', () => {
	const offenders: string[] = [];
	let checked = 0;
	for (const file of svelteFiles(SRC)) {
		const source = readFileSync(file, 'utf8');
		for (const [, name] of source.matchAll(/bodyClass="([\w-]+)"/g)) {
			checked++;
			const uses = scopedUses(source, name);
			if (uses > 0) offenders.push(`${relative(SRC, file)}: .${name} (${uses} scoped rule(s))`);
		}
	}
	assert.ok(checked > 0, 'no bodyClass call site found; the scan is not reading the tree');
	assert.deepEqual(offenders, [], `write these as :global(.name):\n${offenders.join('\n')}`);
});

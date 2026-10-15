// Source-level guard: no Anthropic call forces a tool and asks for extended
// thinking in the same request.
//
// The Messages API refuses `thinking` beside a `tool_choice` that forces a tool
// (`{ type: 'tool' }` or `{ type: 'any' }`), so such a call fails on every
// request and the feature is dead the moment its flag opens. The plan
// assistant dropped the pair in § 1930; the route assistant kept it until the
// #1168 round. Each handler injects its own client, so the shape is checked
// here, once, over every call site.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { stripComments } from './core/strip_comments';

const WEB = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const ROOTS = [resolve(WEB, 'src'), resolve(WEB, 'lambda')];

function walk(dir: string, out: string[] = []): string[] {
	for (const name of readdirSync(dir)) {
		if (name === 'node_modules' || name.startsWith('.')) continue;
		const path = join(dir, name);
		if (statSync(path).isDirectory()) walk(path, out);
		else if (path.endsWith('.ts') && !path.endsWith('.test.ts') && !path.endsWith('.d.ts')) out.push(path);
	}
	return out;
}

/// The argument list of the call whose `(` sits at `open`.
function callArgs(source: string, open: number): string {
	let depth = 0;
	for (let i = open; i < source.length; i++) {
		if (source[i] === '(') depth++;
		else if (source[i] === ')' && --depth === 0) return source.slice(open + 1, i);
	}
	return source.slice(open + 1);
}

function callSites(): Array<{ where: string; args: string }> {
	const sites: Array<{ where: string; args: string }> = [];
	for (const file of ROOTS.flatMap((r) => walk(r))) {
		const source = stripComments(readFileSync(file, 'utf8'));
		for (const m of source.matchAll(/\.messages\.(?:create|stream)\s*\(/g)) {
			const open = (m.index ?? 0) + m[0].length - 1;
			sites.push({ where: relative(WEB, file), args: callArgs(source, open) });
		}
	}
	return sites;
}

test('no Anthropic call sends extended thinking beside a forced tool_choice', () => {
	const sites = callSites();
	assert.ok(sites.length >= 5, `only ${sites.length} Anthropic call sites found — re-anchor the scan`);
	const forced = sites.filter((s) => /tool_choice\s*:\s*\{\s*type\s*:\s*'(?:tool|any)'/.test(s.args));
	assert.ok(forced.length >= 4, `only ${forced.length} forced-tool calls found — re-anchor the scan`);
	const offenders = forced.filter((s) => /\bthinking\s*:/.test(s.args)).map((s) => s.where);
	assert.deepEqual(offenders, [], 'these calls force a tool and ask for thinking; the API refuses the pair');
});

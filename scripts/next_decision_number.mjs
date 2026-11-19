#!/usr/bin/env node
// The next free decisions.md number across origin/main AND every open PR.
//
// The numbering guard (apps/web/src/lib/decisions_numbering_guard.test.ts)
// reads one tree, so two PRs cut from the same main both take the next number
// and pass; the second to merge then conflicts. On 2026-11-19 that happened
// three times in one session (2582/2583, 2583/2589, 2590/2591). Run this
// before writing a decisions entry, and when briefing parallel agents, give
// each one its own number from here.
//
// Run: node scripts/next_decision_number.mjs   (needs gh and network)

import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs';

/**
 * The entry numbers a decisions.md text declares.
 * @param {string} text
 * @returns {number[]}
 */
export function entryNumbers(text) {
	return [...text.matchAll(/^## (\d+)\. /gm)].map((m) => Number(m[1]));
}

/**
 * The next free number and, per ref, the numbers it holds above main's highest.
 * @param {Map<string, number[]>} byRef  ref name -> its entry numbers; must include 'origin/main'
 * @returns {{ next: number, claims: { ref: string, numbers: number[] }[] }}
 */
export function nextFree(byRef) {
	const main = byRef.get('origin/main') ?? [];
	const mainMax = main.length ? Math.max(...main) : 0;
	let max = mainMax;
	/** @type {{ ref: string, numbers: number[] }[]} */
	const claims = [];
	for (const [ref, numbers] of byRef) {
		if (ref === 'origin/main') continue;
		const above = numbers.filter((n) => n > mainMax).sort((a, b) => a - b);
		if (above.length) claims.push({ ref, numbers: above });
		for (const n of above) if (n > max) max = n;
	}
	return { next: max + 1, claims };
}

/** @param {string[]} args */
function git(args) {
	return execFileSync('git', args, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
	const prs = /** @type {{ number: number, headRefName: string }[]} */ (
		JSON.parse(execFileSync('gh', ['pr', 'list', '--state', 'open', '--limit', '200', '--json', 'number,headRefName'], { encoding: 'utf8' }))
	);
	git(['fetch', '--quiet', 'origin', 'main', ...prs.map((p) => p.headRefName)]);
	/** @type {Map<string, number[]>} */
	const byRef = new Map();
	byRef.set('origin/main', entryNumbers(git(['show', 'origin/main:docs/architecture/decisions.md'])));
	for (const p of prs) {
		try {
			byRef.set(`#${p.number} ${p.headRefName}`, entryNumbers(git(['show', `origin/${p.headRefName}:docs/architecture/decisions.md`])));
		} catch {
			// a PR from a fork, or one without the file: nothing to claim
		}
	}
	const { next, claims } = nextFree(byRef);
	for (const c of claims) console.log(`${c.ref}: ${c.numbers.join(', ')}`);
	console.log(`next free: ${next}`);
}

// The Svelte `{#if flag}` branch scanner the deploy-gate guards share.
// Invocation:
//   npx tsx --test src/lib/core/svelte_if_guard.test.ts
//
// Fixtures, so a scanner that stopped matching the template's shape cannot
// let a gate guard pass by finding nothing (decisions § 762).

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { insideIfBranch } from './svelte_if_guard';

const at = (prefix: string) => prefix.length + 1;

test('a guard two levels up still guards', () => {
	const t = '{#if weighInEnabled}{#each rows as r}<X/>{/each}{/if}';
	assert.equal(insideIfBranch(t, 'weighInEnabled')(at('{#if weighInEnabled}{#each rows as r}')), true);
	const u = '{#if a && weightFluid}{#if b}<X/>{/if}{/if}';
	assert.equal(insideIfBranch(u, 'weightFluid')(at('{#if a && weightFluid}{#if b}')), true);
});

test('an unguarded sibling after the block is refused', () => {
	const t = '{#if weighInEnabled}<A/>{/if}<B/>';
	assert.equal(insideIfBranch(t, 'weighInEnabled')(at('{#if weighInEnabled}<A/>{/if}')), false);
});

test('an {#if} naming something else is not a guard', () => {
	assert.equal(insideIfBranch('{#if somethingElse}<A/>{/if}', 'weighInEnabled')(at('{#if somethingElse}')), false);
});

test('the flag is matched as a whole word', () => {
	assert.equal(insideIfBranch('{#if weightFluidOld}<A/>{/if}', 'weightFluid')(at('{#if weightFluidOld}')), false);
});

test('{:else} leaves the branch and {:else if flag} re-enters it', () => {
	const t = '{#if weighInEnabled}<A/>{:else}<B/>{/if}';
	assert.equal(insideIfBranch(t, 'weighInEnabled')(at('{#if weighInEnabled}<A/>{:else}')), false);
	const u = '{#if other}<A/>{:else if weighInEnabled}<B/>{/if}';
	assert.equal(insideIfBranch(u, 'weighInEnabled')(at('{#if other}<A/>{:else if weighInEnabled}')), true);
});

test("an {#each}'s empty-state {:else} inside a guard stays guarded", () => {
	const t = '{#if weighInEnabled}{#each rows as r}<A/>{:else}<B/>{/each}{/if}';
	assert.equal(insideIfBranch(t, 'weighInEnabled')(at('{#if weighInEnabled}{#each rows as r}<A/>{:else}')), true);
});

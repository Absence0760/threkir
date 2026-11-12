// Unit tests for scripts/check_terraform_lock_platforms.mjs.
//
// The real locks are the positive control; each case mutates an in-memory copy
// into one shape the guard exists to refuse. Every mutation must match, so a
// reformatted lock fails here instead of quietly testing an unmutated tree.
//
// Run: node --test scripts/check_terraform_lock_platforms.test.mjs
// CI:  the `infra-guards` job in .github/workflows/ci.yml.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

import { INFRA_DIR, TERRAFORM_WORKFLOW, parseStackMatrix } from './check_infra_coverage.mjs';
import { REQUIRED_PLATFORMS, checkLocks, parseLock, readLocks } from './check_terraform_lock_platforms.mjs';

const LOCKS = readLocks(INFRA_DIR);
const MATRIX = parseStackMatrix(readFileSync(TERRAFORM_WORKFLOW, 'utf-8'));
const fresh = () => new Map(LOCKS);

/** @param {Map<string, string>} locks @param {string} stack @param {(src: string) => string} fn */
function edit(locks, stack, fn) {
	const src = locks.get(stack);
	assert.ok(src !== undefined, `${stack} has no lock in the scanned set`);
	const next = fn(src);
	assert.notEqual(next, src, `${stack}: the mutation matched nothing, so this case would test an unmutated tree`);
	locks.set(stack, next);
}

/** Drops every h1: line after the first in each provider block — a single-platform re-lock. */
const keepOneH1 = (/** @type {string} */ src) => {
	let seen = false;
	return src
		.split('\n')
		.filter((line) => {
			if (/^provider /.test(line)) seen = false;
			if (!/^\s*"h1:/.test(line)) return true;
			if (seen) return false;
			seen = true;
			return true;
		})
		.join('\n');
};

test('the real locks pass, and the walk read every validated stack', () => {
	const { errors, ok } = checkLocks(fresh(), MATRIX);
	assert.deepEqual(errors, []);
	assert.ok(LOCKS.size >= 5, `only ${LOCKS.size} lock files read`);
	assert.ok(MATRIX.length >= 5, `only ${MATRIX.length} validated stacks parsed`);
	assert.ok(ok.length >= 9, `only ${ok.length} provider blocks passed`);
});

test('parseLock reads each block\'s version and its own hashes, not a neighbour\'s', () => {
	const src = LOCKS.get('infra/envs/prod');
	assert.ok(src);
	const providers = parseLock(src);
	assert.deepEqual(
		providers.map((p) => p.source),
		['registry.terraform.io/carlpett/sops', 'registry.terraform.io/hashicorp/archive', 'registry.terraform.io/hashicorp/aws'],
	);
	for (const p of providers) {
		assert.match(p.version ?? '', /^\d+\.\d+\.\d+$/);
		assert.equal(p.h1.length, REQUIRED_PLATFORMS.length, `${p.source}`);
		assert.ok(p.zh > 0, `${p.source} parsed no zh: hashes`);
	}
});

test('a single-platform lock — what the CI runner and a one-flag re-lock write — fails per provider', () => {
	const locks = fresh();
	edit(locks, 'infra/envs/preview', keepOneH1);
	const { errors } = checkLocks(locks, MATRIX);
	const mine = errors.filter((e) => e.startsWith('infra/envs/preview/'));
	assert.ok(mine.length >= 3, errors.join('\n'));
	assert.ok(mine.every((e) => /1 h1: hash\(es\), need 3/.test(e) || /h1: set differs/.test(e)));
	assert.ok(mine.some((e) => e.includes('terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64')));
});

test('duplicate h1: lines are counted once', () => {
	const locks = fresh();
	edit(locks, 'infra/dns', (src) => {
		const one = keepOneH1(src);
		const line = one.split('\n').find((l) => /^\s*"h1:/.test(l));
		assert.ok(line);
		return one.replace(line, `${line}\n${line}\n${line}`);
	});
	assert.ok(checkLocks(locks, MATRIX).errors.some((e) => /^infra\/dns\/.*1 h1: hash\(es\)/.test(e)));
});

test('two stacks locking the same provider version for different platform sets disagree', () => {
	// The pair is built rather than found: Dependabot bumps each stack's
	// provider in its own PR, so whether two real stacks share a version on a
	// given day is an accident of merge order, and a case that waited for one
	// went red on every PR the day the bumps landed out of step.
	const locks = fresh();
	const [first, second] = [...locks.keys()];
	assert.ok(first && second, 'the walk found fewer than two stacks');
	const src = locks.get(first) ?? '';
	locks.set(second, src);
	const aws = parseLock(src).find((p) => p.source.endsWith('hashicorp/aws'));
	assert.ok(aws, `${first} locks no hashicorp/aws provider`);
	assert.ok(aws.h1.length > 0, `${first}'s aws lock carries no h1: hashes`);
	edit(locks, first, (s) => s.replace(aws.h1[0], 'h1:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='));
	assert.ok(checkLocks(locks, MATRIX).errors.some((e) => e.includes('h1: set differs')));
});

test('a validated stack with no committed lock fails', () => {
	const locks = fresh();
	assert.ok(locks.delete('infra/dns'));
	assert.ok(checkLocks(locks, MATRIX).errors.some((e) => e === 'infra/dns: validated by the terraform workflow but has no committed .terraform.lock.hcl'));
});

test('an empty walk, an empty matrix and an unparseable lock are findings, not passes', () => {
	assert.ok(checkLocks(new Map(), MATRIX).errors.some((e) => /walk read nothing/.test(e)));
	assert.ok(checkLocks(fresh(), []).errors.some((e) => /parsed empty/.test(e)));
	const locks = fresh();
	edit(locks, 'infra/dns', (src) => src.replace(/^provider /gm, 'resource '));
	assert.ok(checkLocks(locks, MATRIX).errors.some((e) => /infra\/dns\/.*no provider blocks parsed/.test(e)));
});

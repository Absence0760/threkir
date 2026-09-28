#!/usr/bin/env node
// Guardrail: every committed `.terraform.lock.hcl` under infra/ carries a
// package hash for each platform an operator or CI runs Terraform on.
//
// A lock records, per provider, `zh:` hashes (the registry's zip checksums,
// every platform it publishes) and `h1:` hashes (the unpacked package, one per
// platform that was actually locked). `terraform init` verifies the package it
// installs against the `h1:` set. The five locks used to carry ONE `h1:` per
// provider, linux_amd64's, because that is what the CI runner and Dependabot
// wrote; on a macOS workstation `terraform validate` then exits 1 with "the
// cached package ... does not match any of the checksums recorded in the
// dependency lock file" until `init` rewrites the committed file to add the
// darwin hash — a diff against an artefact nobody meant to change.
//
// The fix is a multi-platform lock (`terraform providers lock` with one
// `-platform` per entry of REQUIRED_PLATFORMS). What keeps it multi-platform is
// Dependabot: its terraform updater detects which platforms the existing `h1:`
// hashes belong to (it re-locks each candidate platform and matches) and
// regenerates for exactly that set, so a three-platform lock stays three —
// replayed against this tree's own locks. A platform outside its candidate list,
// a hand-run `providers lock` with one `-platform`, or an upstream change to
// that detection would strip hashes silently; this is what makes it loud.
//
// What is checked, and what is only proxied:
//   1. Every provider block carries at least REQUIRED_PLATFORMS.length distinct
//      `h1:` hashes. An `h1:` does not name its platform, so the count is a
//      proxy — it cannot tell three platforms from one platform hashed three
//      ways. Terraform never writes the second shape, and claim 2 narrows it.
//   2. The same provider at the same version carries the SAME `h1:` set in
//      every stack that locks it. Stacks locked for different platform sets
//      disagree here even when their counts agree.
//   3. Every stack the terraform workflow validates has a committed lock, so a
//      new stack cannot skip the check by having none (CI's `init` would then
//      write a linux-only lock nobody commits).
//
// Repair, for any finding: from the stack's directory,
//   terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64
// (an env root needs `terraform get` first for its local module). It reads the
// public registry only — no credentials, no backend.
//
// Offline by design: a directory walk and the lock files. No `terraform init`.
//
// Run: `node scripts/check_terraform_lock_platforms.mjs`
// CI:  the `infra-guards` job in .github/workflows/ci.yml.
// Unit tests: `node --test scripts/check_terraform_lock_platforms.test.mjs`

import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { INFRA_DIR, TERRAFORM_WORKFLOW, parseStackMatrix, terraformDirs } from './check_infra_coverage.mjs';

export const REQUIRED_PLATFORMS = Object.freeze(['linux_amd64', 'darwin_arm64', 'darwin_amd64']);

export const LOCK_FILE = '.terraform.lock.hcl';

/**
 * @typedef {{ source: string, version: string | null, h1: string[], zh: number }} LockProvider
 */

/**
 * Every `provider "..." { ... }` block of a lock file. Hashes are read from
 * the block's own `hashes = [ ... ]` list only.
 * @param {string} src
 * @returns {LockProvider[]}
 */
export function parseLock(src) {
  /** @type {LockProvider[]} */
  const out = [];
  const head = /^provider\s+"([^"]+)"\s*\{\s*$/gm;
  let m;
  while ((m = head.exec(src)) !== null) {
    const start = m.index + m[0].length;
    const close = src.slice(start).search(/^\}\s*$/m);
    const body = close === -1 ? src.slice(start) : src.slice(start, start + close);
    const version = body.match(/^\s*version\s*=\s*"([^"]+)"/m)?.[1] ?? null;
    const list = body.match(/^\s*hashes\s*=\s*\[([\s\S]*?)\]/m)?.[1] ?? '';
    const hashes = [...list.matchAll(/"([^"]+)"/g)].map((h) => h[1]);
    out.push({
      source: m[1],
      version,
      h1: [...new Set(hashes.filter((h) => h.startsWith('h1:')))].sort(),
      zh: hashes.filter((h) => h.startsWith('zh:')).length,
    });
  }
  return out;
}

/**
 * @param {Map<string, string>} locks stack path (e.g. `infra/dns`) -> lock source
 * @param {readonly string[]} validated the terraform workflow's `stack:` matrix
 * @param {readonly string[]} [platforms]
 * @returns {{ errors: string[], ok: string[] }}
 */
export function checkLocks(locks, validated, platforms = REQUIRED_PLATFORMS) {
  /** @type {string[]} */
  const errors = [];
  /** @type {string[]} */
  const ok = [];
  const need = platforms.length;
  /** @type {Map<string, { stack: string, h1: string }>} */
  const seen = new Map();

  if (locks.size === 0) errors.push(`no ${LOCK_FILE} found under infra/ — the walk read nothing, so every claim below would pass vacuously`);
  if (validated.length === 0) errors.push('the terraform workflow\'s `stack:` matrix parsed empty, so "every validated stack has a lock" would pass vacuously');

  for (const stack of validated) {
    if (!locks.has(stack)) errors.push(`${stack}: validated by the terraform workflow but has no committed ${LOCK_FILE}`);
  }

  for (const [stack, src] of [...locks].sort(([a], [b]) => a.localeCompare(b))) {
    const providers = parseLock(src);
    if (providers.length === 0) {
      errors.push(`${stack}/${LOCK_FILE}: no provider blocks parsed`);
      continue;
    }
    for (const p of providers) {
      const where = `${stack}/${LOCK_FILE}: ${p.source} ${p.version ?? '(no version)'}`;
      if (p.zh === 0 && p.h1.length === 0) {
        errors.push(`${where}: no hashes parsed from the block`);
        continue;
      }
      if (p.h1.length < need) {
        errors.push(
          `${where}: ${p.h1.length} h1: hash(es), need ${need} (${platforms.join(', ')}). ` +
            `Re-lock from ${stack}: terraform providers lock ${platforms.map((x) => `-platform=${x}`).join(' ')}`,
        );
      } else {
        ok.push(`${where}: ${p.h1.length} h1: hashes`);
      }
      const key = `${p.source}@${p.version}`;
      const set = p.h1.join(',');
      const prior = seen.get(key);
      if (prior === undefined) seen.set(key, { stack, h1: set });
      else if (prior.h1 !== set) {
        errors.push(`${where}: h1: set differs from ${prior.stack}'s for the same provider and version — the two were locked for different platforms`);
      }
    }
  }
  return { errors, ok };
}

/**
 * @param {string} infraDir
 * @returns {Map<string, string>}
 */
export function readLocks(infraDir) {
  /** @type {Map<string, string>} */
  const out = new Map();
  for (const rel of terraformDirs(infraDir, (d) => readdirSync(d))) {
    const abs = join(infraDir, rel.replace(/^infra\/?/, ''));
    const lock = join(abs, LOCK_FILE);
    if (existsSync(lock)) out.set(rel, readFileSync(lock, 'utf-8'));
  }
  return out;
}

export function main() {
  const validated = parseStackMatrix(readFileSync(TERRAFORM_WORKFLOW, 'utf-8'));
  const { errors, ok } = checkLocks(readLocks(INFRA_DIR), validated);
  for (const line of ok) console.log(`[OK] ${line}`);
  for (const line of errors) console.error(`[FAIL] ${line}`);
  if (errors.length > 0) {
    console.error(`\n${errors.length} lock file finding(s). Repair and rationale: infra/README.md, and the header of scripts/check_terraform_lock_platforms.mjs.`);
    return 1;
  }
  console.log(`\n${ok.length} provider lock(s) carry hashes for ${REQUIRED_PLATFORMS.join(', ')}.`);
  return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());

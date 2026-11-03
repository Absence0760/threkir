#!/usr/bin/env node
// Refreshes the esm.sh integrity pins in deno.lock's `remote` section that
// esm.sh has since rebuilt, and nothing else. `--check` reports them instead.
//
// esm.sh serves a versioned URL as `immutable`, but it rebuilds its output
// when its own build changes, and the rebuilt bytes replace the old ones at
// the same URL. The lock keeps the old hash, so a COLD resolve fails with
// "Integrity check failed for remote specifier" while a run that restores
// the Actions DENO_DIR cache passes. Worse, esm.sh's CDN can serve both
// builds at once: on 2026-11-03 `get-intrinsic@1.3.1/deno/get-intrinsic.mjs`
// came back as two different hashes 45 minutes apart (decisions § 2257).
// When that happens, moving the pin just fails the next cold run the other
// way. So run `--check` more than once, and move a pin only when every run
// agrees; when they disagree, the import belongs off esm.sh.
//
// The remedy is a cold resolve against the lock: deno names the first stale
// specifier and stops, so this drops exactly that pin, resolves again so deno
// writes the hash it now sees, and repeats until the graph is clean. Every
// moved pin is printed with both hashes, because a moved pin is a
// supply-chain change and the person committing it should look at what moved.
// No other entry is touched, and a failure that is not an integrity mismatch
// stops the run rather than being "fixed".
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const LOCK = path.join(REPO_ROOT, 'deno.lock');
const BACKEND = path.join(REPO_ROOT, 'apps', 'backend');
const MAX_ROUNDS = 25;

/**
 * The specifier deno reported as no longer matching its pin, or null when the
 * output carries no integrity failure.
 * @param {string} output deno's combined stdout + stderr
 * @returns {{ specifier: string, actual: string | null, expected: string | null } | null}
 */
export function integrityFailure(output) {
  // deno colours its output on a TTY; strip the escapes before matching.
  // eslint-disable-next-line no-control-regex
  const text = output.replace(/\u001b\[[0-9;]*m/g, '');
  const at = text.indexOf('Integrity check failed');
  if (at < 0) return null;
  const tail = text.slice(at);
  const field = (/** @type {string} */ name) =>
    new RegExp(`^\\s*${name}:\\s*(\\S+)`, 'm').exec(tail)?.[1] ?? null;
  const specifier = field('Specifier');
  if (!specifier) return null;
  return { specifier, actual: field('Actual'), expected: field('Expected') };
}

/**
 * The lockfile with one `remote` pin removed. Refuses a specifier the lock
 * does not pin, so a parse slip can never drop the wrong entry.
 * @template {{ remote?: Record<string, string> }} L
 * @param {L} lock
 * @param {string} specifier
 * @returns {L}
 */
export function withoutRemotePin(lock, specifier) {
  const remote = lock.remote ?? {};
  if (!Object.hasOwn(remote, specifier)) {
    throw new Error(`deno.lock pins no remote entry for ${specifier}`);
  }
  const { [specifier]: _dropped, ...rest } = remote;
  return { ...lock, remote: rest };
}

/** Every Edge Function module, the same set the CI warm step resolves. */
function functionFiles() {
  /** @type {string[]} */
  const out = [];
  /** @param {string} dir */
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.name.endsWith('.ts')) out.push(path.relative(BACKEND, full));
    }
  };
  walk(path.join(BACKEND, 'supabase', 'functions'));
  return out.sort();
}

/** @param {string} denoDir */
function coldResolve(denoDir) {
  const run = spawnSync('deno', ['cache', '--no-check', ...functionFiles()], {
    cwd: BACKEND,
    env: { ...process.env, DENO_DIR: denoDir, NO_COLOR: '1' },
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
  });
  if (run.error) throw run.error;
  return { ok: run.status === 0, output: `${run.stdout}${run.stderr}` };
}

function main() {
  const check = process.argv.includes('--check');
  // A fresh DENO_DIR is the whole point: a warm cache answers from the old
  // bytes and reports a stale pin as fine.
  const denoDir = fs.mkdtempSync(path.join(os.tmpdir(), 'deno-lock-cold-'));
  try {
    /** @type {{ specifier: string, expected: string | null }[]} */
    const moved = [];
    for (let round = 0; round < MAX_ROUNDS; round++) {
      const { ok, output } = coldResolve(denoDir);
      if (ok) break;
      const stale = integrityFailure(output);
      if (!stale) {
        process.stderr.write(output.slice(-4000));
        console.error(
          '::error::deno could not resolve the Edge Function graph, and not because of a stale integrity pin. Nothing was changed.',
        );
        process.exit(1);
      }
      if (check) {
        console.error(
          `::error::deno.lock pins ${stale.specifier} at ${stale.expected}, but esm.sh now serves ${stale.actual}. ` +
            'esm.sh rebuilt it; a cold resolve fails until the pin moves. Run `node scripts/refresh_deno_lock_remote.mjs`, review the moved pins, and commit deno.lock.',
        );
        process.exit(1);
      }
      const lock = JSON.parse(fs.readFileSync(LOCK, 'utf8'));
      fs.writeFileSync(LOCK, `${JSON.stringify(withoutRemotePin(lock, stale.specifier), null, 2)}\n`);
      moved.push({ specifier: stale.specifier, expected: stale.expected });
      if (round === MAX_ROUNDS - 1) {
        console.error(`::error::still stale after ${MAX_ROUNDS} rounds; stopping.`);
        process.exit(1);
      }
    }
    if (check) {
      console.log('deno.lock: every remote pin matches what its URL serves today.');
      return;
    }
    const remote = JSON.parse(fs.readFileSync(LOCK, 'utf8')).remote ?? {};
    for (const m of moved) {
      console.log(`moved ${m.specifier}\n  was ${m.expected}\n  now ${remote[m.specifier]}`);
    }
    console.log(
      moved.length
        ? `${moved.length} pin(s) moved. Review what each URL now serves before committing deno.lock.`
        : 'deno.lock: nothing stale.',
    );
  } finally {
    fs.rmSync(denoDir, { recursive: true, force: true });
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}

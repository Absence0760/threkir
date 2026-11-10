// Drives apply-pending-migrations.sh against a stub `psql` on PATH, so the
// lock_timeout and retry contract is pinned without a database: what each
// file's transaction sends, that a 55P03 is retried whole and bounded, and
// that any other failure stops at once. The stub prints the error line real
// psql prints under `\set VERBOSITY verbose`
// (`psql:<file>:<line>: ERROR:  55P03: canceling statement due to lock timeout`).

import { spawnSync } from 'node:child_process';
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import assert from 'node:assert/strict';

const SCRIPT = join(dirname(fileURLToPath(import.meta.url)), 'apply-pending-migrations.sh');

const STUB = `#!/usr/bin/env bash
set -u
state="$STUB_STATE"
for arg in "$@"; do
  if [[ "$arg" == "-tAc" ]]; then
    cat "$state/ledger" 2>/dev/null
    exit 0
  fi
done
sql="$(cat)"
n=$(( $(cat "$state/calls" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$state/calls"
printf '%s' "$sql" > "$state/call-$n.sql"
version="$(sed -n "s/^  values ('\\([0-9]*\\)'.*/\\1/p" <<<"$sql")"
mode="$(cat "$state/mode-$version" 2>/dev/null || echo ok)"
case "$mode" in
  lock:*)
    left="\${mode#lock:}"
    if [[ "$left" != "always" ]]; then
      if (( left <= 0 )); then mode=ok; else echo "lock:$(( left - 1 ))" > "$state/mode-$version"; fi
    fi
    ;;
esac
case "$mode" in
  ok)
    echo "$version" >> "$state/ledger"
    exit 0
    ;;
  lock:*)
    echo "psql:supabase/migrations/x.sql:3: ERROR:  55P03: canceling statement due to lock timeout" >&2
    exit 3
    ;;
  fail)
    echo "psql:supabase/migrations/x.sql:3: ERROR:  42P01: relation \\"nope\\" does not exist" >&2
    exit 3
    ;;
esac
`;

/**
 * @param {{ modes?: Record<string, string>, env?: Record<string, string>, applied?: string[] }} [options]
 */
function run({ modes = {}, env = {}, applied = [] } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'apply-pending-'));
  const bin = join(root, 'bin');
  const state = join(root, 'state');
  const migrations = join(root, 'supabase', 'migrations');
  mkdirSync(bin);
  mkdirSync(state);
  mkdirSync(migrations, { recursive: true });
  writeFileSync(join(bin, 'psql'), STUB);
  chmodSync(join(bin, 'psql'), 0o755);
  writeFileSync(join(migrations, '20990101000001_first.sql'), 'select 1;\n');
  writeFileSync(join(migrations, '20990101000002_second.sql'), 'select 2;\n');
  if (applied.length > 0) writeFileSync(join(state, 'ledger'), `${applied.join('\n')}\n`);
  for (const [version, mode] of Object.entries(modes)) {
    writeFileSync(join(state, `mode-${version}`), mode);
  }
  const result = spawnSync('bash', [SCRIPT], {
    cwd: root,
    encoding: 'utf8',
    env: {
      PATH: `${bin}:${process.env.PATH}`,
      HOME: root,
      TMPDIR: root,
      STUB_STATE: state,
      SUPABASE_DB_URL: 'postgresql://postgres@127.0.0.1:1/postgres',
      MIGRATION_RETRY_BASE_S: '0',
      ...env,
    },
  });
  const callCount = existsSync(join(state, 'calls'))
    ? Number(readFileSync(join(state, 'calls'), 'utf8'))
    : 0;
  const calls = Array.from({ length: callCount }, (_, i) =>
    readFileSync(join(state, `call-${i + 1}.sql`), 'utf8'),
  );
  const ledger = existsSync(join(state, 'ledger'))
    ? readFileSync(join(state, 'ledger'), 'utf8').split('\n').filter(Boolean)
    : [];
  return { ...result, calls, ledger, output: result.stdout + result.stderr };
}

test('each file runs in one transaction that sets lock_timeout before the SQL and records its ledger row', () => {
  const { status, calls, ledger } = run();
  assert.equal(status, 0);
  assert.deepEqual(ledger, ['20990101000001', '20990101000002']);
  assert.equal(calls.length, 2);
  const lines = calls[0].split('\n').map((l) => l.trim());
  const at = (prefix) => lines.findIndex((l) => l.startsWith(prefix));
  assert.ok(at('\\set VERBOSITY verbose') >= 0, 'the SQLSTATE must reach the error line');
  assert.ok(at('begin;') < at("set local lock_timeout = '5s';"));
  assert.ok(at("set local lock_timeout = '5s';") < at('\\i supabase/migrations/20990101000001_first.sql'));
  assert.ok(at('\\i ') < at('insert into supabase_migrations.schema_migrations'));
  assert.ok(at('insert into supabase_migrations.schema_migrations') < at('commit;'));
});

test('MIGRATION_LOCK_TIMEOUT sets the timeout, and a value that is not a duration is refused', () => {
  const ok = run({ env: { MIGRATION_LOCK_TIMEOUT: '750ms' } });
  assert.equal(ok.status, 0);
  assert.match(ok.calls[0], /set local lock_timeout = '750ms';/);

  const bad = run({ env: { MIGRATION_LOCK_TIMEOUT: "5s'; drop table runs; --" } });
  assert.equal(bad.status, 1);
  assert.equal(bad.calls.length, 0);
  assert.match(bad.output, /MIGRATION_LOCK_TIMEOUT must be a Postgres duration/);
});

test('a lock timeout is retried from the top of the file and then applies', () => {
  const { status, calls, ledger, output } = run({ modes: { '20990101000001': 'lock:2' } });
  assert.equal(status, 0, output);
  assert.equal(calls.length, 4, 'two timed-out attempts, one success, then the second file');
  assert.deepEqual(ledger, ['20990101000001', '20990101000002']);
  assert.equal(output.match(/::warning::20990101000001 waited longer than lock_timeout/g)?.length, 2);
  assert.match(output, /attempt 3\/5/);
});

test('retries are bounded: the last timed-out attempt fails loudly and nothing after it runs', () => {
  const { status, calls, ledger, output } = run({
    modes: { '20990101000001': 'lock:always' },
    env: { MIGRATION_LOCK_ATTEMPTS: '3' },
  });
  assert.equal(status, 1);
  assert.equal(calls.length, 3);
  assert.deepEqual(ledger, []);
  assert.match(output, /::error::20990101000001 \(first\) could not take its locks within lock_timeout=5s on any of 3 attempts/);
});

test('an error that is not a lock timeout is not retried', () => {
  const { status, calls, ledger, output } = run({ modes: { '20990101000002': 'fail' } });
  assert.equal(status, 1);
  assert.equal(calls.length, 2);
  assert.deepEqual(ledger, ['20990101000001']);
  assert.doesNotMatch(output, /::warning::/);
  assert.match(output, /::error::20990101000002 \(second\) failed \(psql exit 3\)/);
});

test('an already-recorded version is skipped without a transaction', () => {
  const { status, calls, output } = run({ applied: ['20990101000001'] });
  assert.equal(status, 0);
  assert.equal(calls.length, 1);
  assert.match(calls[0], /\\i supabase\/migrations\/20990101000002_second\.sql/);
  assert.match(output, /Done: applied 1 migration\(s\), 1 already present\./);
});

import test from 'node:test';
import assert from 'node:assert/strict';

import { integrityFailure, withoutRemotePin } from './refresh_deno_lock_remote.mjs';

// The failure as deno 2.9 printed it on main, run of 2026-11-03, colours and all.
const DENO_OUTPUT = [
  '\u001b[0m\u001b[32mDownload\u001b[0m https://esm.sh/dunder-proto@1.0.1/get.d.ts',
  '\u001b[0m\u001b[31merror:\u001b[0m Integrity check failed for remote specifier. The source code is invalid, as it does not match the expected hash in the lock file.',
  '',
  '  Specifier: https://esm.sh/get-intrinsic@1.3.1/deno/get-intrinsic.mjs',
  '  Actual: dba4cb556f6f2684f7c8c80593f76ea9baa003ef7a76dab4f562dc8a78508714',
  '  Expected: f4a5f1ff0abdbf6e62e36801e099c6dd2e65d01b9ff28eff957613c641753a0b',
  '',
  'This could be caused by:',
].join('\n');

test('names the stale specifier and both hashes from deno output', () => {
  assert.deepEqual(integrityFailure(DENO_OUTPUT), {
    specifier: 'https://esm.sh/get-intrinsic@1.3.1/deno/get-intrinsic.mjs',
    actual: 'dba4cb556f6f2684f7c8c80593f76ea9baa003ef7a76dab4f562dc8a78508714',
    expected: 'f4a5f1ff0abdbf6e62e36801e099c6dd2e65d01b9ff28eff957613c641753a0b',
  });
});

test('a failure that is not an integrity mismatch is not one', () => {
  // An esm.sh 522 is a transient the warm step's retry exists for; it must
  // never be "fixed" by moving a pin.
  const outage =
    'error: Import \'https://esm.sh/@supabase/supabase-js@2.110.0\' failed.\n    522 <unknown status code>';
  assert.equal(integrityFailure(outage), null);
  assert.equal(integrityFailure(''), null);
});

test('drops exactly the named pin and keeps every other one', () => {
  const lock = {
    version: '5',
    remote: {
      'https://esm.sh/a@1': 'aaa',
      'https://esm.sh/b@1': 'bbb',
      'https://esm.sh/c@1': 'ccc',
    },
    redirects: { 'https://esm.sh/a': 'https://esm.sh/a@1' },
  };
  const out = withoutRemotePin(lock, 'https://esm.sh/b@1');
  assert.deepEqual(out.remote, { 'https://esm.sh/a@1': 'aaa', 'https://esm.sh/c@1': 'ccc' });
  assert.deepEqual(out.redirects, lock.redirects);
  assert.equal(out.version, '5');
  assert.equal(Object.keys(lock.remote).length, 3, 'the input lock was mutated');
});

test('refuses a specifier the lock does not pin', () => {
  assert.throws(
    () => withoutRemotePin({ remote: { 'https://esm.sh/a@1': 'aaa' } }, 'https://esm.sh/z@9'),
    /pins no remote entry/,
  );
});

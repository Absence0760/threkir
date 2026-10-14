/// `findViewableRun` decides which of the two non-owner reads admitted a run.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/clip-public-track/viewable_run.test.ts`.

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';

import { findViewableRun, type ViewableRunRow } from './viewable_run.ts';

const ROW: ViewableRunRow = { user_id: 'owner', is_public: false, metadata: {} };

function reader(answers: Record<string, { data: ViewableRunRow | null; error: unknown }>) {
  const asked: string[] = [];
  return {
    asked,
    read: (view: 'public_runs' | 'shared_runs') => {
      asked.push(view);
      return Promise.resolve(answers[view] ?? { data: null, error: null });
    },
  };
}

Deno.test('a public run is answered by public_runs and shared_runs is never asked', async () => {
  const r = reader({ public_runs: { data: { ...ROW, is_public: true }, error: null } });
  const out = await findViewableRun(r.read, 'viewer');
  assertEquals(out.kind, 'found');
  assertEquals(out.kind === 'found' && out.audience, 'public');
  assertEquals(r.asked, ['public_runs']);
});

Deno.test('a run shared with the caller is found through shared_runs', async () => {
  const r = reader({ shared_runs: { data: ROW, error: null } });
  const out = await findViewableRun(r.read, 'viewer');
  assertEquals(out.kind === 'found' && out.audience, 'shared');
  assertEquals(out.kind === 'found' && out.run.user_id, 'owner');
  assertEquals(r.asked, ['public_runs', 'shared_runs']);
});

Deno.test('an anonymous caller has no audience to be in', async () => {
  const r = reader({ shared_runs: { data: ROW, error: null } });
  const out = await findViewableRun(r.read, null);
  assertEquals(out.kind, 'missing');
  assertEquals(r.asked, ['public_runs']);
});

Deno.test('a run in neither view is missing', async () => {
  const r = reader({});
  assertEquals((await findViewableRun(r.read, 'viewer')).kind, 'missing');
});

Deno.test('a failed read is a failure, not a miss, on either view', async () => {
  const pub = reader({ public_runs: { data: null, error: new Error('down') } });
  assertEquals((await findViewableRun(pub.read, 'viewer')).kind, 'failed');
  assertEquals(pub.asked, ['public_runs']);
  const shared = reader({ shared_runs: { data: null, error: { code: '500' } } });
  assertEquals((await findViewableRun(shared.read, 'viewer')).kind, 'failed');
});

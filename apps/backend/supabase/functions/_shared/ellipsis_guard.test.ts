/// Run with `cd apps/backend && deno test --allow-read supabase/functions/_shared/ellipsis_guard.test.ts`.
///
/// The copy an Edge Function writes for a person writes the one-character
/// ellipsis "…" (U+2026), never three full stops, which can wrap between the
/// dots and read as three sentences to a screen reader (decisions § 2539,
/// § 2556, § 2571).
///
/// Scope: the localized catalogues, which is where every sentence a person
/// reads lives — the auth emails (`auth-email/lib.ts`) and the plan
/// calendar's workout titles (`plan-calendar/lib.ts`). Everything else an
/// Edge Function returns is a machine code (`{ error: 'notes_required' }`)
/// that the client renders from its own guarded catalogue, or a log line, and
/// telling those apart from copy by reading literals would need an allowlist
/// longer than the copy. So the guard walks the catalogues' values, and fails
/// when a file outside the registry starts a locale-keyed table (a
/// `'pt-BR': {` entry), which is how a new catalogue would arrive unguarded.

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { authEmailCatalogue, authEmailShared } from '../auth-email/lib.ts';
import { KIND_LABELS } from '../plan-calendar/lib.ts';

const CATALOGUES: Record<string, { file: string; table: unknown }> = {
  authEmailCatalogue: { file: 'auth-email/lib.ts', table: authEmailCatalogue },
  authEmailShared: { file: 'auth-email/lib.ts', table: authEmailShared },
  KIND_LABELS: { file: 'plan-calendar/lib.ts', table: KIND_LABELS },
};

function offenders(path: string, node: unknown): string[] {
  if (typeof node === 'string') return node.includes('...') ? [`${path}: ${node}`] : [];
  if (Array.isArray(node)) return node.flatMap((v, i) => offenders(`${path}[${i}]`, v));
  if (node && typeof node === 'object') {
    return Object.entries(node).flatMap(([k, v]) => offenders(`${path}.${k}`, v));
  }
  return [];
}

const FUNCTIONS_DIR = new URL('../', import.meta.url);
const LOCALE_TABLE = /['"]pt-BR['"]\s*:\s*\{/;

async function* sources(dir: URL, rel = ''): AsyncGenerator<string> {
  for await (const e of Deno.readDir(dir)) {
    const name = rel + e.name;
    if (e.isDirectory) yield* sources(new URL(`${e.name}/`, dir), `${name}/`);
    else if (e.name.endsWith('.ts') && !e.name.endsWith('.test.ts')) yield name;
  }
}

Deno.test('Edge Function catalogues write the one-character ellipsis', () => {
  const found = Object.entries(CATALOGUES).flatMap(([name, { table }]) => offenders(name, table));
  assertEquals(found, []);
});

Deno.test('every locale-keyed copy table is in the ellipsis registry', async () => {
  const registered = new Set(Object.values(CATALOGUES).map((c) => c.file));
  const holding: string[] = [];
  for await (const rel of sources(FUNCTIONS_DIR)) {
    if (LOCALE_TABLE.test(await Deno.readTextFile(new URL(rel, FUNCTIONS_DIR)))) holding.push(rel);
  }
  assertEquals(
    holding.sort(),
    [...registered].sort(),
    'a file holding a locale-keyed table must be registered in CATALOGUES, and a registered file must still hold one',
  );
});

Deno.test('the guard catches the slips it exists for', () => {
  assertEquals(offenders('x', { en: { subject: 'Signing you in...' } }).length, 1);
  assertEquals(offenders('x', { ja: { body: ['送信中...'] } }).length, 1);
  assertEquals(offenders('x', { en: { subject: 'Signing you in…' } }).length, 0);
  assertEquals(offenders('x', { en: { subject: 'Wait. Then go.' } }).length, 0);
});

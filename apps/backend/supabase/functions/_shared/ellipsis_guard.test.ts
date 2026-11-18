/// Run with `cd apps/backend && deno test --allow-read supabase/functions/_shared/ellipsis_guard.test.ts`.
/// `--allow-read` is all this file needs: it reads the functions' sources and
/// the web locale list. CI runs it inside the whole-directory pure-helper step,
/// `deno test --no-check --allow-read --allow-env supabase/functions/`, whose
/// `--allow-env` is for `handler_envelope.test.ts`, not for this file.
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
/// when a file outside the registry holds a locale-keyed table, which is how a
/// new catalogue would arrive unguarded (see `holdsLocaleTable`).

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { authEmailCatalogue, authEmailShared } from '../auth-email/lib.ts';
import { KIND_LABELS } from '../plan-calendar/lib.ts';

const CATALOGUES: Record<string, { file: string; table: unknown }> = {
  authEmailCatalogue: { file: 'auth-email/lib.ts', table: authEmailCatalogue },
  authEmailShared: { file: 'auth-email/lib.ts', table: authEmailShared },
  KIND_LABELS: { file: 'plan-calendar/lib.ts', table: KIND_LABELS },
};

function strings(node: unknown): string[] {
  if (typeof node === 'string') return [node];
  if (Array.isArray(node)) return node.flatMap(strings);
  if (node && typeof node === 'object') return Object.values(node).flatMap(strings);
  return [];
}

function offenders(path: string, node: unknown): string[] {
  if (typeof node === 'string') return node.includes('...') ? [`${path}: ${node}`] : [];
  if (Array.isArray(node)) return node.flatMap((v, i) => offenders(`${path}[${i}]`, v));
  if (node && typeof node === 'object') {
    return Object.entries(node).flatMap(([k, v]) => offenders(`${path}.${k}`, v));
  }
  return [];
}

const FUNCTIONS_DIR = new URL('../', import.meta.url);

/// The shipped locales, read from the one list the product negotiates against
/// (`SUPPORTED_LOCALES` in the web's `locale.ts`) so a seventh locale reaches
/// this guard without an edit here. Normalized lowercase with `-`, plus each
/// tag's base language, so `pt-BR`, `'pt-br'`, `pt_BR` and a bare `pt` all
/// count as locale keys.
function shippedLocaleKeys(): Set<string> {
  const src = Deno.readTextFileSync(
    new URL('../../../../web/src/lib/i18n/locale.ts', import.meta.url),
  );
  const list = src.match(/export const SUPPORTED_LOCALES = \[([^\]]*)\]/);
  if (!list) throw new Error('SUPPORTED_LOCALES not found in apps/web/src/lib/i18n/locale.ts');
  const tags = [...list[1].matchAll(/'([^']+)'/g)].map((m) => m[1].toLowerCase());
  if (tags.length < 2) throw new Error(`SUPPORTED_LOCALES parsed as ${JSON.stringify(tags)}`);
  return new Set(tags.flatMap((t) => [t, t.split('-')[0]]));
}

const LOCALE_KEYS = shippedLocaleKeys();
const norm = (tag: string) => tag.toLowerCase().replaceAll('_', '-');

/// An object key that names a locale, in any spelling (quoted or bare,
/// `pt-BR` / `pt_BR` / `pt`), at the start of a line or after `{` or `,`,
/// and the start of its value. Comment lines start with `//` or `*`, so prose
/// mentioning a tag never matches the line-start arm.
const LOCALE_ENTRY =
  /(?:^|[{,])[ \t]*(['"]?)([A-Za-z]{2}(?:[-_][A-Za-z]{2})?)\1[ \t]*:[ \t]*(\{|\[|`|'([^'\n]*)'|"([^"\n]*)")/gm;

/// A file holds a locale-keyed copy table when two or more distinct shipped
/// locales are keys whose value is copy-shaped: a nested object or array, a
/// template, or a string that is not itself a locale tag. The last clause is
/// what leaves a locale-normalization map (`'pt-br': 'pt-BR'`) out, since it
/// holds tags, not sentences. Two, not one, so a lone `en:` field elsewhere
/// is not a catalogue; and any two, not `pt-BR` in particular, so a table
/// keyed `pt`/`pt_BR`, or one that has not got its Brazilian entry yet, is
/// still seen.
function holdsLocaleTable(src: string): boolean {
  const seen = new Set<string>();
  for (const m of src.matchAll(LOCALE_ENTRY)) {
    const key = norm(m[2]);
    if (!LOCALE_KEYS.has(key)) continue;
    const str = m[4] ?? m[5];
    if (str !== undefined && LOCALE_KEYS.has(norm(str))) continue;
    seen.add(key);
  }
  return seen.size >= 2;
}

async function* sources(dir: URL, rel = ''): AsyncGenerator<string> {
  for await (const e of Deno.readDir(dir)) {
    const name = rel + e.name;
    if (e.isDirectory) yield* sources(new URL(`${e.name}/`, dir), `${name}/`);
    else if (e.name.endsWith('.ts') && !e.name.endsWith('.test.ts')) yield name;
  }
}

Deno.test('Edge Function catalogues write the one-character ellipsis', () => {
  // Positive control: every registered catalogue must hand the guard real
  // copy, so an emptied or missing table fails instead of passing as clean.
  const empty = Object.entries(CATALOGUES)
    .filter(([, { table }]) => !strings(table).some((v) => v.trim().length > 0))
    .map(([name]) => name);
  assertEquals(empty, [], 'a registered catalogue holds no copy, so the guard would read nothing');

  // The guard's own probes ride on the same test, so they share its control.
  assertEquals(offenders('x', { en: { subject: 'Signing you in...' } }).length, 1);
  assertEquals(offenders('x', { ja: { body: ['送信中...'] } }).length, 1);
  assertEquals(offenders('x', { en: { subject: 'Signing you in…' } }).length, 0);
  assertEquals(offenders('x', { en: { subject: 'Wait. Then go.' } }).length, 0);

  const found = Object.entries(CATALOGUES).flatMap(([name, { table }]) => offenders(name, table));
  assertEquals(found, []);
});

Deno.test('every locale-keyed copy table is in the ellipsis registry', async () => {
  const registered = new Set(Object.values(CATALOGUES).map((c) => c.file));
  const holding: string[] = [];
  for await (const rel of sources(FUNCTIONS_DIR)) {
    if (holdsLocaleTable(await Deno.readTextFile(new URL(rel, FUNCTIONS_DIR)))) holding.push(rel);
  }
  assertEquals(
    holding.sort(),
    [...registered].sort(),
    'a file holding a locale-keyed table must be registered in CATALOGUES, and a registered file must still hold one',
  );
});

Deno.test('the registry sentinel sees a locale table in every shape', () => {
  const planted: Record<string, string> = {
    'quoted pt-BR': "const T = {\n  en: { a: 'Hi' },\n  'pt-BR': { a: 'Oi' },\n};",
    'bare pt': 'const T = {\n  en: { a: "Hi" },\n  pt: { a: "Olá" },\n};',
    'underscore pt_BR': "const T = {\n  de: ['Hallo'],\n  pt_BR: ['Oi'],\n};",
    'no pt-BR at all': "const T = {\n  en: { a: 'Hi' },\n  fr: { a: 'Salut' },\n};",
    'flat, one line': "const T = { en: 'Saving', ja: '保存中' };",
    'template values': 'const T = {\n  en: `Hi ${n}`,\n  es: `Hola ${n}`,\n};',
  };
  for (const [shape, src] of Object.entries(planted)) {
    assertEquals(holdsLocaleTable(src), true, shape);
  }
  const clean: Record<string, string> = {
    'tag-normalization map': "const M = {\n  en: 'en',\n  'pt-br': 'pt-BR',\n  pt: 'pt-PT',\n};",
    'one locale key': "const P = { en: { a: 'Hi' }, kind: 'x' };",
    'tags only in a comment': "// en: { a }, 'pt-BR': { b }\nconst x = 1;",
    'not a shipped locale': "const T = {\n  it: { a: 'Ciao' },\n  nl: { a: 'Hoi' },\n};",
  };
  for (const [shape, src] of Object.entries(clean)) {
    assertEquals(holdsLocaleTable(src), false, shape);
  }
});

import { assertEquals, assertStrictEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { clipText, dropLoneSurrogates } from './text_clip.ts';

/// True when `s` would survive a Postgres JSON parse: no unpaired surrogate.
function wellFormed(s: string): boolean {
  return !/[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/.test(s);
}

Deno.test('clipText — a cap through a surrogate pair drops the stranded half, not the text before it', () => {
  const out = clipText('abc\u{1F3C3}def', 4);
  assertStrictEquals(out, 'abc');
  assertStrictEquals(wellFormed(out), true);
  assertStrictEquals(clipText('abc\u{1F3C3}def', 5), 'abc\u{1F3C3}');
});

Deno.test('clipText — trims first, and again after a dropped half leaves trailing space', () => {
  assertStrictEquals(clipText('   Run club   ', 50), 'Run club');
  assertStrictEquals(clipText('Run \u{1F3C3}', 5), 'Run');
  assertStrictEquals(clipText('\u{1F3C3}', 1), '');
});

Deno.test('dropLoneSurrogates — keeps every whole pair, drops every half, in any order', () => {
  assertStrictEquals(dropLoneSurrogates('a\u{10000}b\u{10FFFF}c'), 'a\u{10000}b\u{10FFFF}c');
  assertStrictEquals(dropLoneSurrogates('\uDC00\uD800'), '');
  assertStrictEquals(dropLoneSurrogates('x\uD83Cy\uDFC3z'), 'xyz');
  // Every result of either function is well formed, whatever the input.
  for (const s of ['\uD800', '\uDFFF', 'a\uD83C', '\uDFC3a', 'ok']) {
    assertEquals(wellFormed(dropLoneSurrogates(s)), true, JSON.stringify(s));
    assertEquals(wellFormed(clipText(s, 1)), true, JSON.stringify(s));
  }
});

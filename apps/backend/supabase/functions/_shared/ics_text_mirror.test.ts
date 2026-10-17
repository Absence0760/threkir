/// `_shared/ics_text.ts` is a byte-for-byte copy of
/// `apps/web/src/lib/social/ics_text.ts`, the RFC 5545 primitives the club
/// event download already writes with. The Edge Function cannot import from
/// the web tree at run time (`_shared/database.ts` is the one crossing, and it
/// is type-only), so the serializer is shared by copy, and this is what keeps
/// the copy honest: a fold or escape fixed on one side and not the other
/// would make the plan feed and the event download disagree about the same
/// grammar.
///
/// Run with:
///   cd apps/backend && deno test --no-check --allow-read supabase/functions/_shared/ics_text_mirror.test.ts

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';

Deno.test('the Edge Function ics_text.ts is byte-identical to the web original', async () => {
  const here = await Deno.readTextFile(new URL('./ics_text.ts', import.meta.url));
  const web = await Deno.readTextFile(
    new URL('../../../../web/src/lib/social/ics_text.ts', import.meta.url),
  );
  assertEquals(here, web, 'copy apps/web/src/lib/social/ics_text.ts over _shared/ics_text.ts');
});

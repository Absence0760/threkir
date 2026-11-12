/// Run with `cd apps/backend && deno test --allow-read supabase/functions/strava-import/connect_errors.test.ts`.
///
/// Every refusal `connect` answers is a stable JSON code a client can map to
/// its own sentence. The missing-scope refusal used to be an English sentence
/// in a text/plain body; a client either rendered the server's English or
/// could not tell it apart from any other failure.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { LEGACY_CONNECT_MESSAGES, STRAVA_CONNECT_ERROR_CODES, connectRefusal } from './connect_errors.ts';

const SRC = await Deno.readTextFile(new URL('./index.ts', import.meta.url));

/// The source from `async function handleConnect(` to the next top-level
/// function, plus the top-level `connect` validation block.
function connectPath(): string {
	const start = SRC.indexOf('async function handleConnect(');
	assert(start >= 0, 'handleConnect moved');
	const end = SRC.indexOf('\nasync function ', start + 1);
	const handler = SRC.slice(start, end < 0 ? undefined : end);
	const vStart = SRC.indexOf("if (action === 'connect') {");
	const vEnd = SRC.indexOf("} else if (action === 'sync')", vStart);
	assert(vStart >= 0 && vEnd > vStart, 'the connect validation block moved');
	return SRC.slice(vStart, vEnd) + handler;
}

Deno.test('a connect refusal is a JSON code with its status', async () => {
	const res = connectRefusal('invalid_code', 400);
	assertEquals(res.status, 400);
	assertEquals(res.headers.get('content-type'), 'application/json');
	assertEquals(await res.json(), { error: 'invalid_code' });
});

// Mobile builds before 497c1b42e print a failed connect's decoded body, so the
// missing-scope refusal keeps the sentence they used to receive as text/plain.
// Delete this test with LEGACY_CONNECT_MESSAGES once the minimum supported
// mobile build includes 497c1b42e.
Deno.test('the missing-scope refusal still carries the sentence old mobile builds show', async () => {
	const res = connectRefusal('missing_scope', 400);
	assertEquals(res.status, 400);
	assertEquals(await res.json(), {
		error: 'missing_scope',
		message:
			'Strava connection is missing the activity:read_all scope. Please reconnect and accept all permissions.',
	});
	assertEquals(
		Object.keys(LEGACY_CONNECT_MESSAGES),
		['missing_scope'],
		'only the refusal that used to be a sentence has one; a new code is words-free from the start',
	);
});

Deno.test('every code is lower snake case, and none repeats', () => {
	for (const code of STRAVA_CONNECT_ERROR_CODES) {
		assert(/^[a-z]+(?:_[a-z]+)*$/.test(code), `${code} is not a machine code`);
	}
	assertEquals(new Set(STRAVA_CONNECT_ERROR_CODES).size, STRAVA_CONNECT_ERROR_CODES.length);
});

Deno.test('the connect path answers no prose body', () => {
	const path = connectPath();
	assert(
		!/new Response\(\s*['"`]/.test(path),
		'a connect refusal must be connectRefusal(code, status), not a text body a client has to show verbatim',
	);
	assert(
		!/Response\.json\(\s*\{\s*error:/.test(path),
		'a connect refusal goes through connectRefusal so its code is one of STRAVA_CONNECT_ERROR_CODES',
	);
});

Deno.test('the connect path uses every listed code, and only those', () => {
	const used = new Set(
		[...connectPath().matchAll(/connectRefusal\('([a-z_]+)'/g)].map((m) => m[1]),
	);
	assertEquals(
		[...used].sort(),
		[...STRAVA_CONNECT_ERROR_CODES].sort(),
		'STRAVA_CONNECT_ERROR_CODES is the list the clients map; it must match what connect answers',
	);
});

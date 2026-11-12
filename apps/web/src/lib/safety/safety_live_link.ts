// A safety contact's link to a safety-audience live run (decisions § 1964).
//
// The overdue / off-route alert carries `/live/{run_id}#k=<token>`. The token
// rides in the FRAGMENT so a browser never sends it to the server or in a
// Referer; this page reads it from `location.hash` and passes it to the two
// token-checked RPCs in a POST body, never a query string. The database mints
// v4 UUIDs, so anything that is not UUID-shaped is not one of ours and is
// treated as no token at all — the page then falls back to the public path.

const TOKEN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/// How often a token holder polls for new pings. A realtime channel carries
/// no token and live_run_pings RLS admits nobody but the runner, so a safety
/// contact polls instead; the broadcaster pings every ~5 s.
export const SAFETY_LINK_POLL_MS = 5_000;

export function parseSafetyLinkToken(hash: string | null | undefined): string | null {
	if (!hash) return null;
	const raw = hash.startsWith('#') ? hash.slice(1) : hash;
	const k = new URLSearchParams(raw).get('k');
	if (!k || !TOKEN.test(k)) return null;
	return k.toLowerCase();
}

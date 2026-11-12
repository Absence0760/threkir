/// Drives `makeStravaClubsHandler` with fake deps and a stubbed Strava, so
/// every branch runs without a stack or a real grant.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/strava-clubs/handler.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
	CLUBS_PER_PAGE,
	type LinkOutcome,
	makeStravaClubsHandler,
	projectStravaClub,
	type StoredTokens,
	stravaSaysAdmin,
	type StravaClubsDeps,
} from './handler.ts';

const NOW = Date.parse('2026-10-15T12:00:00Z');
const USER = '11111111-1111-1111-1111-111111111111';
const CLUB = '22222222-2222-2222-2222-222222222222';

const FRESH: StoredTokens = {
	access_token: 'stored-token',
	refresh_token: 'refresh-token',
	token_expiry: new Date(NOW + 3_600_000).toISOString(),
};
const EXPIRED: StoredTokens = {
	access_token: 'stale-token',
	refresh_token: 'refresh-token',
	token_expiry: new Date(NOW - 60_000).toISOString(),
};

function stravaClub(id: number, name: string, extra: Record<string, unknown> = {}) {
	return {
		id,
		resource_state: 2,
		name,
		profile_medium: `https://dgalywyr863hv.cloudfront.net/pictures/clubs/${id}/medium.jpg`,
		sport_type: 'running',
		city: 'Richmond',
		state: 'Virginia',
		country: 'United States',
		private: false,
		member_count: 42,
		...extra,
	};
}

interface Recorder {
	fetches: Array<{ url: string; auth: string | null }>;
	refreshes: string[];
	links: Array<{ userId: string; clubId: string; stravaClubId: number }>;
	linkedLookups: number[][];
}

function harness(opts: {
	user?: string | null;
	tokens?: StoredTokens | null;
	refreshed?: string | null;
	strava?: (url: string) => Response;
	linked?: Array<{ id: string; slug: string; name: string; strava_club_id: number }>;
	linkOutcome?: LinkOutcome;
	limited?: boolean;
}) {
	const rec: Recorder = { fetches: [], refreshes: [], links: [], linkedLookups: [] };
	const deps: StravaClubsDeps = {
		authenticate: () => Promise.resolve(opts.user === undefined ? USER : opts.user),
		rateLimit: () => Promise.resolve(opts.limited ? Response.json({ error: 'rate_limited' }, { status: 429 }) : null),
		getTokens: () => Promise.resolve(opts.tokens === undefined ? FRESH : opts.tokens),
		refreshToken: (_u, refreshToken) => {
			rec.refreshes.push(refreshToken);
			return Promise.resolve(opts.refreshed === undefined ? 'fresh-token' : opts.refreshed);
		},
		linkedClubs: (ids) => {
			rec.linkedLookups.push(ids);
			return Promise.resolve(opts.linked ?? []);
		},
		setLink: (userId, clubId, stravaClubId) => {
			rec.links.push({ userId, clubId, stravaClubId });
			return Promise.resolve(opts.linkOutcome ?? 'ok');
		},
		fetch: (input, init) => {
			const url = String(input);
			const headers = new Headers(init?.headers);
			rec.fetches.push({ url, auth: headers.get('Authorization') });
			return Promise.resolve(opts.strava ? opts.strava(url) : Response.json([]));
		},
		now: () => NOW,
	};
	return { handler: makeStravaClubsHandler(deps), rec };
}

function post(body: unknown, auth: string | null = 'Bearer user-jwt'): Request {
	const headers: Record<string, string> = { 'Content-Type': 'application/json' };
	if (auth) headers.Authorization = auth;
	return new Request('http://localhost/functions/v1/strava-clubs', {
		method: 'POST',
		headers,
		body: JSON.stringify(body),
	});
}

// ── list ────────────────────────────────────────────────────────────────────

Deno.test('list — connected: the caller\'s own clubs, projected, with the visible link attached', async () => {
	const { handler, rec } = harness({
		strava: () =>
			Response.json([
				stravaClub(101, 'Richmond Run Club', { admin: true, owner: false, membership: 'member' }),
				stravaClub(202, 'Trail Crew'),
				{ id: 'not-a-number', name: 'Broken' },
			]),
		linked: [{ id: CLUB, slug: 'richmond-run-club', name: 'Richmond RC', strava_club_id: 101 }],
	});
	const res = await handler(post({ action: 'list' }));
	assertEquals(res.status, 200);
	const body = await res.json();
	assertEquals(body.status, 'connected');
	assertEquals(body.clubs.length, 2);
	assertEquals(body.clubs[0], {
		strava_club_id: 101,
		name: 'Richmond Run Club',
		city: 'Richmond',
		state: 'Virginia',
		country: 'United States',
		sport_type: 'running',
		member_count: 42,
		profile_url: 'https://dgalywyr863hv.cloudfront.net/pictures/clubs/101/medium.jpg',
		viewer_is_admin: true,
		linked_club: { id: CLUB, slug: 'richmond-run-club', name: 'Richmond RC' },
	});
	assertEquals(body.clubs[1].strava_club_id, 202);
	assertEquals(body.clubs[1].viewer_is_admin, null);
	assertEquals(body.clubs[1].linked_club, null);
	assertEquals(rec.fetches.length, 1);
	assertEquals(rec.fetches[0].url, `https://www.strava.com/api/v3/athlete/clubs?page=1&per_page=${CLUBS_PER_PAGE}`);
	assertEquals(rec.fetches[0].auth, 'Bearer stored-token');
	assertEquals(rec.linkedLookups, [[101, 202]]);
	assertEquals(rec.refreshes, []);
});

Deno.test('list — not connected is a 200 answer, and Strava is never called', async () => {
	const { handler, rec } = harness({ tokens: null });
	const res = await handler(post({ action: 'list' }));
	assertEquals(res.status, 200);
	assertEquals(await res.json(), { status: 'not_connected' });
	assertEquals(rec.fetches.length, 0);
});

Deno.test('list — a stored row with no access token is not connected either', async () => {
	const { handler, rec } = harness({ tokens: { access_token: null, refresh_token: null, token_expiry: null } });
	assertEquals(await (await handler(post({ action: 'list' }))).json(), { status: 'not_connected' });
	assertEquals(rec.fetches.length, 0);
});

Deno.test('list — an expired token is refreshed through the helper and the fresh one is used', async () => {
	const { handler, rec } = harness({ tokens: EXPIRED, strava: () => Response.json([stravaClub(7, 'Club Seven')]) });
	const res = await handler(post({ action: 'list' }));
	assertEquals(res.status, 200);
	assertEquals((await res.json()).clubs.length, 1);
	assertEquals(rec.refreshes, ['refresh-token']);
	assertEquals(rec.fetches[0].auth, 'Bearer fresh-token');
});

Deno.test('list — an expired token whose refresh is refused asks for a reconnect without calling Strava', async () => {
	const { handler, rec } = harness({ tokens: EXPIRED, refreshed: null });
	const res = await handler(post({ action: 'list' }));
	assertEquals(res.status, 200);
	assertEquals(await res.json(), { status: 'reconnect_required' });
	assertEquals(rec.fetches.length, 0);
});

Deno.test('list — Strava rejecting the token asks for a reconnect', async () => {
	const { handler } = harness({ strava: () => new Response('{}', { status: 401 }) });
	assertEquals(await (await handler(post({ action: 'list' }))).json(), { status: 'reconnect_required' });
});

Deno.test('list — Strava throttling is a 503, an outage a 502', async () => {
	const throttled = harness({ strava: () => new Response('', { status: 429 }) });
	const r1 = await throttled.handler(post({ action: 'list' }));
	assertEquals(r1.status, 503);
	assertEquals(await r1.json(), { error: 'strava_rate_limited' });
	const down = harness({ strava: () => new Response('', { status: 500 }) });
	const r2 = await down.handler(post({ action: 'list' }));
	assertEquals(r2.status, 502);
	assertEquals(await r2.json(), { error: 'strava_unavailable' });
});

Deno.test('list — a full page is followed by the next, and a short page ends the walk', async () => {
	const full = Array.from({ length: CLUBS_PER_PAGE }, (_, i) => stravaClub(i + 1, `Club ${i + 1}`));
	const { handler, rec } = harness({
		strava: (url) => Response.json(url.includes('page=1&') ? full : [stravaClub(9999, 'Last')]),
	});
	const body = await (await handler(post({ action: 'list' }))).json();
	assertEquals(body.clubs.length, CLUBS_PER_PAGE + 1);
	assertEquals(rec.fetches.length, 2);
	assert(rec.fetches[1].url.includes('page=2&'));
});

Deno.test('list — no clubs means no linked-club lookup', async () => {
	const { handler, rec } = harness({ strava: () => Response.json([]) });
	assertEquals(await (await handler(post({ action: 'list' }))).json(), { status: 'connected', clubs: [] });
	assertEquals(rec.linkedLookups, []);
});

// ── link ────────────────────────────────────────────────────────────────────

const ADMIN_DETAIL = { id: 101, name: 'Richmond Run Club', membership: 'member', admin: true, owner: false };

Deno.test('link — a Strava admin links their club, through the one writer', async () => {
	const { handler, rec } = harness({ strava: () => Response.json(ADMIN_DETAIL) });
	const res = await handler(post({ action: 'link', club_id: CLUB, strava_club_id: 101 }));
	assertEquals(res.status, 200);
	assertEquals(await res.json(), { ok: true });
	assertEquals(rec.fetches[0].url, 'https://www.strava.com/api/v3/clubs/101');
	assertEquals(rec.fetches[0].auth, 'Bearer stored-token');
	assertEquals(rec.links, [{ userId: USER, clubId: CLUB, stravaClubId: 101 }]);
});

Deno.test('link — a plain member of the Strava club cannot claim it', async () => {
	const { handler, rec } = harness({
		strava: () => Response.json({ ...ADMIN_DETAIL, admin: false, owner: false }),
	});
	const res = await handler(post({ action: 'link', club_id: CLUB, strava_club_id: 101 }));
	assertEquals(res.status, 403);
	assertEquals(await res.json(), { error: 'strava_admin_required' });
	assertEquals(rec.links, []);
});

Deno.test('link — a club Strava will not show the caller cannot be claimed', async () => {
	const { handler, rec } = harness({ strava: () => new Response('', { status: 404 }) });
	const res = await handler(post({ action: 'link', club_id: CLUB, strava_club_id: 101 }));
	assertEquals(res.status, 403);
	assertEquals(rec.links, []);
});

Deno.test('link — each refusal from the writer has its own answer', async () => {
	const cases: Array<[LinkOutcome, number, string]> = [
		['not_club_admin', 403, 'not_club_admin'],
		['already_linked', 409, 'strava_club_already_linked'],
		['invalid_strava_club', 400, 'invalid_strava_club_id'],
		['error', 500, 'link_failed'],
	];
	for (const [outcome, status, error] of cases) {
		const { handler } = harness({ strava: () => Response.json(ADMIN_DETAIL), linkOutcome: outcome });
		const res = await handler(post({ action: 'link', club_id: CLUB, strava_club_id: 101 }));
		assertEquals(res.status, status, outcome);
		assertEquals(await res.json(), { error }, outcome);
	}
});

Deno.test('link — not connected is refused before Strava or the database is asked', async () => {
	const { handler, rec } = harness({ tokens: null });
	const res = await handler(post({ action: 'link', club_id: CLUB, strava_club_id: 101 }));
	assertEquals(res.status, 400);
	assertEquals(await res.json(), { error: 'strava_not_connected' });
	assertEquals(rec.fetches.length + rec.links.length, 0);
});

Deno.test('link — an expired token with a dead grant asks for a reconnect', async () => {
	const { handler, rec } = harness({ tokens: EXPIRED, refreshed: null });
	const res = await handler(post({ action: 'link', club_id: CLUB, strava_club_id: 101 }));
	assertEquals(res.status, 401);
	assertEquals(await res.json(), { error: 'refresh_failed', reconnect_required: true });
	assertEquals(rec.links, []);
});

Deno.test('link — malformed ids are refused before anything else runs', async () => {
	const bad: Array<[Record<string, unknown>, string]> = [
		[{ action: 'link', club_id: 'nope', strava_club_id: 101 }, 'invalid_club_id'],
		[{ action: 'link', club_id: CLUB, strava_club_id: '101' }, 'invalid_strava_club_id'],
		[{ action: 'link', club_id: CLUB, strava_club_id: -1 }, 'invalid_strava_club_id'],
		[{ action: 'link', club_id: CLUB, strava_club_id: 1.5 }, 'invalid_strava_club_id'],
		[{ action: 'link', club_id: CLUB }, 'invalid_strava_club_id'],
	];
	for (const [body, error] of bad) {
		const { handler, rec } = harness({ strava: () => Response.json(ADMIN_DETAIL) });
		const res = await handler(post(body));
		assertEquals(res.status, 400, JSON.stringify(body));
		assertEquals(await res.json(), { error }, JSON.stringify(body));
		assertEquals(rec.fetches.length + rec.links.length, 0);
	}
});

// ── envelope ─────────────────────────────────────────────────────────────────

Deno.test('envelope — no session, an unknown action, a GET and a throttled caller', async () => {
	assertEquals((await harness({}).handler(post({ action: 'list' }, null))).status, 401);
	assertEquals((await harness({ user: null }).handler(post({ action: 'list' }))).status, 401);
	const unknown = await harness({}).handler(post({ action: 'sync' }));
	assertEquals(unknown.status, 400);
	assertEquals((await unknown.json()).error, 'invalid_action');
	const get = await harness({}).handler(new Request('http://localhost/x', { method: 'GET' }));
	assertEquals(get.status, 405);
	const limited = harness({ limited: true });
	assertEquals((await limited.handler(post({ action: 'list' }))).status, 429);
	assertEquals(limited.rec.fetches.length, 0);
});

// ── pure projections ─────────────────────────────────────────────────────────

Deno.test('projectStravaClub — drops what it cannot render and keeps only an https image', () => {
	assertEquals(projectStravaClub(null), null);
	assertEquals(projectStravaClub({ id: 5 }), null);
	assertEquals(projectStravaClub({ id: 0, name: 'Zero' }), null);
	const plain = projectStravaClub({ id: 5, name: '  Five  ', profile_medium: 'http://insecure/x.jpg', member_count: -3 });
	assertEquals(plain?.name, 'Five');
	assertEquals(plain?.profile_url, null);
	assertEquals(plain?.member_count, null);
	assertEquals(plain?.city, null);
	assertEquals(projectStravaClub({ id: 5, name: 'Five', owner: true })?.viewer_is_admin, true);
	assertEquals(projectStravaClub({ id: 5, name: 'Five', admin: false, owner: false })?.viewer_is_admin, false);
});

Deno.test('stravaSaysAdmin — only a full member who administers or owns the club', () => {
	assert(stravaSaysAdmin({ membership: 'member', admin: true }));
	assert(stravaSaysAdmin({ membership: 'member', owner: true }));
	assert(!stravaSaysAdmin({ membership: 'pending', admin: true }));
	assert(!stravaSaysAdmin({ membership: 'member', admin: false, owner: false }));
	assert(!stravaSaysAdmin({ admin: true }));
	assert(!stravaSaysAdmin(null));
});

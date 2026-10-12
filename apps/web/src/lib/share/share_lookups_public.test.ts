import { afterEach, test } from 'node:test';
import assert from 'node:assert/strict';

import { lookupSharedClub } from './share_club_lookup';
import { lookupSharedEvent } from './share_event_lookup';
import { lookupSharedBadge } from './share_badge_lookup';
import { lookupSharedRace } from './share_race_lookup';

// The club / event / badge / race lookups serve logged-out /share/* pages.
// RLS is the first wall; these pin the second one the lookups themselves
// build (moderation and visibility filters, private-club drops), plus the
// `upstream_unreachable` tag a CloudWatch alarm pages on.

const CONFIG = { supabaseUrl: 'https://stub.supabase.co', supabaseAnonKey: 'anon' };
const ID = '11111111-1111-4111-8111-111111111111';
const USER_ID = '22222222-2222-4222-8222-222222222222';

const realFetch = globalThis.fetch;
const realError = console.error;
let requests: URL[] = [];
let errors: string[] = [];

function stubPostgrest(routes: Record<string, { status?: number; body: unknown }>) {
	requests = [];
	errors = [];
	console.error = (...args: unknown[]) => {
		errors.push(args.map(String).join(' '));
	};
	globalThis.fetch = (async (input: RequestInfo | URL) => {
		const url = new URL(input instanceof Request ? input.url : String(input));
		requests.push(url);
		const hit = Object.entries(routes).find(([path]) => url.pathname.endsWith(path));
		if (!hit) return new Response('[]', { status: 200 });
		const [, { status = 200, body }] = hit;
		return new Response(JSON.stringify(body), {
			status,
			headers: { 'content-type': 'application/json' },
		});
	}) as typeof fetch;
}

afterEach(() => {
	globalThis.fetch = realFetch;
	console.error = realError;
});

const alarmed = () => errors.some((e) => e.includes('upstream_unreachable'));

test('club: the query excludes moderation-hidden clubs and matches on slug', async () => {
	stubPostgrest({});
	await lookupSharedClub('river-runners', CONFIG);
	assert.equal(requests.length, 1);
	assert.equal(requests[0].pathname, '/rest/v1/clubs');
	assert.equal(requests[0].searchParams.get('shadow_hidden'), 'eq.false');
	assert.equal(requests[0].searchParams.get('slug'), 'eq.river-runners');
});

test('club: a private club that slips past RLS is still not shown', async () => {
	stubPostgrest({
		'/rest/v1/clubs': {
			body: [{ id: ID, slug: 'secret', name: 'Secret', is_public: false }],
		},
	});
	assert.deepEqual(await lookupSharedClub('secret', CONFIG), { club: null });
});

test('club: a PostgREST error raises the alarm tag; a clean miss does not', async () => {
	stubPostgrest({ '/rest/v1/clubs': { status: 400, body: { code: 'PGRST100', message: 'bad' } } });
	assert.deepEqual(await lookupSharedClub('x', CONFIG), { club: null });
	assert.equal(alarmed(), true);

	stubPostgrest({ '/rest/v1/clubs': { body: [] } });
	assert.deepEqual(await lookupSharedClub('x', CONFIG), { club: null });
	assert.equal(alarmed(), false);
});

const EVENT_ROW = {
	id: ID,
	club_id: USER_ID,
	title: 'Tuesday tempo',
	description: null,
	starts_at: '2026-10-13T18:00:00Z',
	duration_min: 60,
	distance_m: 8000,
	category: 'run',
	discipline: null,
};

test("event: an event of a private club is never shown", async () => {
	stubPostgrest({
		'/rest/v1/events': {
			body: [{ ...EVENT_ROW, clubs: { name: 'Secret', slug: 'secret', is_public: false, shadow_hidden: false } }],
		},
	});
	assert.deepEqual(await lookupSharedEvent(ID, CONFIG), { event: null });
});

test("event: an event of a moderation-hidden club is never shown", async () => {
	stubPostgrest({
		'/rest/v1/events': {
			body: [{ ...EVENT_ROW, clubs: { name: 'Hidden', slug: 'hidden', is_public: true, shadow_hidden: true } }],
		},
	});
	assert.deepEqual(await lookupSharedEvent(ID, CONFIG), { event: null });
});

test("event: a public club's event carries the club's name, slug and location", async () => {
	stubPostgrest({
		'/rest/v1/events': {
			body: [
				{
					...EVENT_ROW,
					clubs: { name: 'River Runners', slug: 'river-runners', location_label: 'Leeds', is_public: true, shadow_hidden: false },
				},
			],
		},
	});
	const { event } = await lookupSharedEvent(ID, CONFIG);
	assert.equal(event?.title, 'Tuesday tempo');
	assert.equal(event?.club_name, 'River Runners');
	assert.equal(event?.club_slug, 'river-runners');
	assert.equal(event?.club_location, 'Leeds');
	assert.equal(requests[0].searchParams.get('id'), `eq.${ID}`);
});

test('event, badge, race: a malformed id is a quiet not-found that never reaches PostgREST', async () => {
	stubPostgrest({});
	assert.deepEqual(await lookupSharedEvent('hello', CONFIG), { event: null });
	assert.deepEqual(await lookupSharedBadge('hello', CONFIG), { badge: null, displayName: null });
	assert.deepEqual(await lookupSharedRace('hello', CONFIG), { race: null });
	assert.equal(requests.length, 0);
	assert.equal(alarmed(), false);
});

test('badge: only a public badge is asked for, and the owner name comes from the profile RPC', async () => {
	stubPostgrest({
		'/rest/v1/achievements': {
			body: [{ id: ID, user_id: USER_ID, badge_key: 'distance_single', tier: 'gold', value_num: 42195, earned_at: '2026-10-01T00:00:00Z' }],
		},
		'/rest/v1/rpc/public_profile_by_id': { body: [{ display_name: 'Ana' }] },
	});
	const r = await lookupSharedBadge(ID, CONFIG);
	assert.equal(r.badge?.badge_key, 'distance_single');
	assert.equal(r.displayName, 'Ana');
	assert.equal(requests[0].pathname, '/rest/v1/achievements');
	assert.equal(requests[0].searchParams.get('is_public'), 'eq.true');
	assert.equal(requests[1].pathname, '/rest/v1/rpc/public_profile_by_id');
	assert.equal(requests[1].searchParams.get('p_id'), USER_ID);
});

test('race: reads the public_race_listings view, not the base table', async () => {
	stubPostgrest({
		'/rest/v1/public_race_listings': {
			body: [{ id: ID, name: 'City 10K', race_date: '2026-11-01', distance_m: 10000, location_label: null, entry_url: null, is_verified: true }],
		},
	});
	const { race } = await lookupSharedRace(ID, CONFIG);
	assert.equal(race?.name, 'City 10K');
	assert.deepEqual(
		requests.map((u) => u.pathname),
		['/rest/v1/public_race_listings'],
	);
});

test('club, event, badge, race: missing config makes no request at all', async () => {
	stubPostgrest({});
	assert.deepEqual(await lookupSharedClub('x', null), { club: null });
	assert.deepEqual(await lookupSharedEvent(ID, null), { event: null });
	assert.deepEqual(await lookupSharedBadge(ID, null), { badge: null, displayName: null });
	assert.deepEqual(await lookupSharedRace(ID, { supabaseUrl: '', supabaseAnonKey: 'anon' }), { race: null });
	assert.equal(requests.length, 0);
});

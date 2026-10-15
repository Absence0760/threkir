/// `strava-clubs` — a signed-in runner's own Strava clubs, and linking one of
/// them to a Threkir club (issue #1151 step 4, decisions § 1953).
///
/// Two actions, both scoped to the caller and nobody else:
///
/// - `list` calls Strava's `GET /athlete/clubs` with the caller's own token and
///   answers a small projection of each club plus the Threkir club already
///   linked to it, when the caller can see that club. Nothing is stored: Strava's
///   terms allow showing an athlete their own clubs, not building a directory
///   from them, so the response is the only place the list exists.
/// - `link` records that a Threkir club IS a Strava club. A link is a claim
///   (the column is unique), so the caller must be an admin or owner of that
///   club ON STRAVA — checked here with `GET /clubs/{id}`, whose
///   `membership` / `admin` / `owner` describe the authenticated athlete — and
///   an active owner/admin of the Threkir club, which `set_club_strava_link`
///   re-checks in SQL.
///
/// Both need only the `read` scope, which the connect flow has always asked
/// for alongside `activity:read_all`.
///
/// Not being connected is an answer, not an error: `list` returns
/// `{ status: 'not_connected' }` (or `'reconnect_required'` when the grant is
/// dead) with a 200 so the clubs page renders nothing rather than an error.
///
/// The handler takes its database, Strava and rate-limit access as injected
/// deps so `handler.test.ts` drives every branch without a stack; `index.ts`
/// is the wiring.

import { readJsonWithLimit } from '../_shared/body_limit.ts';
import { UPSTREAM_TIMEOUT_MS } from '../_shared/upstream_deadline.ts';

export const STRAVA_API = 'https://www.strava.com/api/v3';

/// Strava's own page-size ceiling is 200; 100 keeps one page well inside a
/// response anyone would scroll, and three pages is more clubs than any real
/// athlete belongs to.
export const CLUBS_PER_PAGE = 100;
export const MAX_CLUB_PAGES = 3;

/// Refresh the stored token when it is this close to expiry, matching
/// `strava-import`'s on-demand refresh.
export const REFRESH_MARGIN_MS = 300_000;

export interface StoredTokens {
	access_token: string | null;
	refresh_token: string | null;
	token_expiry: string | null;
}

export interface LinkedClub {
	id: string;
	slug: string;
	name: string;
}

export interface StravaClubSummary {
	strava_club_id: number;
	name: string;
	city: string | null;
	state: string | null;
	country: string | null;
	sport_type: string | null;
	member_count: number | null;
	profile_url: string | null;
	/// `true` / `false` when Strava said whether the caller administers the
	/// club; `null` when the list response did not carry it. The `link` action
	/// asks Strava again either way, so this only shapes the UI.
	viewer_is_admin: boolean | null;
	linked_club: LinkedClub | null;
}

export type LinkOutcome =
	| 'ok'
	| 'not_club_admin'
	| 'already_linked'
	| 'invalid_strava_club'
	| 'error';

export interface StravaClubsDeps {
	/// The caller's user id from the forwarded JWT, or null when it is not a
	/// signed-in session.
	authenticate(authHeader: string): Promise<string | null>;
	/// A 429 to return, or null when the caller is within budget. Fail-closed.
	rateLimit(userId: string, bucket: string, max: number, windowSeconds: number): Promise<Response | null>;
	/// The caller's stored Strava tokens, or null when there is no link.
	getTokens(userId: string): Promise<StoredTokens | null>;
	/// A fresh access token, or null when Strava refused the refresh.
	refreshToken(userId: string, refreshToken: string): Promise<string | null>;
	/// The Threkir clubs linked to these Strava ids that the CALLER can see.
	linkedClubs(stravaClubIds: number[]): Promise<Array<LinkedClub & { strava_club_id: number }>>;
	setLink(userId: string, clubId: string, stravaClubId: number): Promise<LinkOutcome>;
	fetch: typeof fetch;
	now(): number;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function json(body: unknown, status = 200): Response {
	return Response.json(body, { status });
}

function text(v: unknown): string | null {
	return typeof v === 'string' && v.trim() !== '' ? v.trim() : null;
}

export function isStravaClubId(v: unknown): v is number {
	return typeof v === 'number' && Number.isSafeInteger(v) && v > 0;
}

/// One Strava SummaryClub reduced to what the clubs page renders. Anything
/// without a usable id and name is dropped rather than rendered half-empty.
export function projectStravaClub(raw: unknown): StravaClubSummary | null {
	if (raw === null || typeof raw !== 'object') return null;
	const r = raw as Record<string, unknown>;
	const name = text(r.name);
	if (!isStravaClubId(r.id) || name === null) return null;
	const memberCount =
		typeof r.member_count === 'number' && Number.isSafeInteger(r.member_count) && r.member_count >= 0
			? r.member_count
			: null;
	const profile = text(r.profile_medium) ?? text(r.profile);
	const adminKnown = typeof r.admin === 'boolean' || typeof r.owner === 'boolean';
	return {
		strava_club_id: r.id,
		name,
		city: text(r.city),
		state: text(r.state),
		country: text(r.country),
		sport_type: text(r.sport_type),
		member_count: memberCount,
		profile_url: profile !== null && profile.startsWith('https://') ? profile : null,
		viewer_is_admin: adminKnown ? r.admin === true || r.owner === true : null,
		linked_club: null,
	};
}

/// Whether Strava's `GET /clubs/{id}` body says the authenticated athlete
/// administers the club. A pending or absent membership never counts, and a
/// body that omits the fields is a refusal.
export function stravaSaysAdmin(raw: unknown): boolean {
	if (raw === null || typeof raw !== 'object') return false;
	const r = raw as Record<string, unknown>;
	return r.membership === 'member' && (r.admin === true || r.owner === true);
}

type TokenResult =
	| { kind: 'ok'; accessToken: string }
	| { kind: 'not_connected' }
	| { kind: 'reconnect_required' };

async function accessTokenFor(deps: StravaClubsDeps, userId: string): Promise<TokenResult> {
	const tokens = await deps.getTokens(userId);
	if (!tokens?.access_token) return { kind: 'not_connected' };
	if (tokens.token_expiry) {
		const expiryMs = new Date(tokens.token_expiry).getTime();
		if (!Number.isFinite(expiryMs) || deps.now() + REFRESH_MARGIN_MS > expiryMs) {
			if (!tokens.refresh_token) return { kind: 'reconnect_required' };
			const fresh = await deps.refreshToken(userId, tokens.refresh_token);
			if (!fresh) return { kind: 'reconnect_required' };
			return { kind: 'ok', accessToken: fresh };
		}
	}
	return { kind: 'ok', accessToken: tokens.access_token };
}

type StravaGet =
	| { kind: 'ok'; body: unknown }
	| { kind: 'unauthorized' }
	| { kind: 'not_found' }
	| { kind: 'rate_limited' }
	| { kind: 'unavailable' };

async function stravaGet(deps: StravaClubsDeps, url: string, accessToken: string, signal: AbortSignal): Promise<StravaGet> {
	let resp: Response;
	try {
		resp = await deps.fetch(url, { headers: { Authorization: `Bearer ${accessToken}` }, signal });
	} catch (_) {
		return { kind: 'unavailable' };
	}
	if (resp.status === 401) return { kind: 'unauthorized' };
	if (resp.status === 403 || resp.status === 404) return { kind: 'not_found' };
	if (resp.status === 429) return { kind: 'rate_limited' };
	if (!resp.ok) return { kind: 'unavailable' };
	try {
		return { kind: 'ok', body: await resp.json() };
	} catch (_) {
		return { kind: 'unavailable' };
	}
}

function upstreamFailure(kind: 'rate_limited' | 'unavailable'): Response {
	return kind === 'rate_limited'
		? json({ error: 'strava_rate_limited' }, 503)
		: json({ error: 'strava_unavailable' }, 502);
}

async function handleList(deps: StravaClubsDeps, userId: string): Promise<Response> {
	const token = await accessTokenFor(deps, userId);
	if (token.kind !== 'ok') return json({ status: token.kind });

	const signal = AbortSignal.timeout(UPSTREAM_TIMEOUT_MS);
	const clubs: StravaClubSummary[] = [];
	const seen = new Set<number>();
	for (let page = 1; page <= MAX_CLUB_PAGES; page++) {
		const got = await stravaGet(
			deps,
			`${STRAVA_API}/athlete/clubs?page=${page}&per_page=${CLUBS_PER_PAGE}`,
			token.accessToken,
			signal,
		);
		if (got.kind === 'unauthorized') return json({ status: 'reconnect_required' });
		if (got.kind === 'not_found') return upstreamFailure('unavailable');
		if (got.kind !== 'ok') return upstreamFailure(got.kind);
		if (!Array.isArray(got.body)) return upstreamFailure('unavailable');
		for (const raw of got.body) {
			const club = projectStravaClub(raw);
			if (club && !seen.has(club.strava_club_id)) {
				seen.add(club.strava_club_id);
				clubs.push(club);
			}
		}
		if (got.body.length < CLUBS_PER_PAGE) break;
	}

	if (clubs.length > 0) {
		const linked = await deps.linkedClubs(clubs.map((c) => c.strava_club_id));
		const byId = new Map(linked.map((l) => [l.strava_club_id, l]));
		for (const club of clubs) {
			const l = byId.get(club.strava_club_id);
			if (l) club.linked_club = { id: l.id, slug: l.slug, name: l.name };
		}
	}
	return json({ status: 'connected', clubs });
}

async function handleLink(deps: StravaClubsDeps, userId: string, clubId: string, stravaClubId: number): Promise<Response> {
	const token = await accessTokenFor(deps, userId);
	if (token.kind === 'not_connected') return json({ error: 'strava_not_connected' }, 400);
	if (token.kind === 'reconnect_required') {
		return json({ error: 'refresh_failed', reconnect_required: true }, 401);
	}

	const got = await stravaGet(
		deps,
		`${STRAVA_API}/clubs/${stravaClubId}`,
		token.accessToken,
		AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
	);
	if (got.kind === 'unauthorized') return json({ error: 'refresh_failed', reconnect_required: true }, 401);
	if (got.kind === 'rate_limited' || got.kind === 'unavailable') return upstreamFailure(got.kind);
	if (got.kind === 'not_found' || !stravaSaysAdmin(got.body)) {
		return json({ error: 'strava_admin_required' }, 403);
	}

	const outcome = await deps.setLink(userId, clubId, stravaClubId);
	switch (outcome) {
		case 'ok':
			return json({ ok: true });
		case 'not_club_admin':
			return json({ error: 'not_club_admin' }, 403);
		case 'already_linked':
			return json({ error: 'strava_club_already_linked' }, 409);
		case 'invalid_strava_club':
			return json({ error: 'invalid_strava_club_id' }, 400);
		case 'error':
			return json({ error: 'link_failed' }, 500);
	}
}

export function makeStravaClubsHandler(deps: StravaClubsDeps): (req: Request) => Promise<Response> {
	return async (req: Request) => {
		if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

		const guarded = await readJsonWithLimit<Record<string, unknown>>(req, 1024);
		if ('tooLarge' in guarded) return guarded.tooLarge;

		const authHeader = req.headers.get('Authorization');
		if (!authHeader) return json({ error: 'unauthorized' }, 401);
		const userId = await deps.authenticate(authHeader);
		if (!userId) return json({ error: 'unauthorized' }, 401);

		const body = (guarded.body ?? {}) as Record<string, unknown>;
		const action = body.action;
		if (action !== 'list' && action !== 'link') {
			return json({ error: 'invalid_action', expected: ['list', 'link'] }, 400);
		}

		if (action === 'list') {
			const denied = await deps.rateLimit(userId, 'strava-clubs:list', 30, 3600);
			if (denied) return denied;
			return handleList(deps, userId);
		}

		const clubId = body.club_id;
		const stravaClubId = body.strava_club_id;
		if (typeof clubId !== 'string' || !UUID_RE.test(clubId)) {
			return json({ error: 'invalid_club_id' }, 400);
		}
		if (!isStravaClubId(stravaClubId)) {
			return json({ error: 'invalid_strava_club_id' }, 400);
		}
		const denied = await deps.rateLimit(userId, 'strava-clubs:link', 10, 3600);
		if (denied) return denied;
		return handleLink(deps, userId, clubId, stravaClubId);
	};
}

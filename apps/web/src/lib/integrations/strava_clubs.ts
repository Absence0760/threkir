/// The `strava-clubs` Edge Function's answers, graded rather than cast
/// (decisions § 1959), and the hand-off from a Strava club to the create form.
///
/// Pure on purpose: `strava.ts` imports `$app/env/public` and supabase-js and
/// so cannot run under `node --test`, while this can.

import type { MessageKey } from '../i18n/messages.ts';
import { TEXT_LIMITS } from '../core/text_limits.ts';
import { prefilledClubName } from '../social/club_setup.ts';

export interface StravaLinkedClub {
	id: string;
	slug: string;
	name: string;
}

export interface StravaClub {
	stravaClubId: number;
	name: string;
	city: string | null;
	state: string | null;
	country: string | null;
	sportType: string | null;
	memberCount: number | null;
	/// Strava said whether the viewer administers this club; `null` when the
	/// list did not carry it. The link action asks Strava again either way.
	viewerIsAdmin: boolean | null;
	linkedClub: StravaLinkedClub | null;
}

export type StravaClubsResult =
	| { status: 'connected'; clubs: StravaClub[] }
	| { status: 'not_connected' }
	| { status: 'reconnect_required' };

function str(v: unknown): string | null {
	return typeof v === 'string' && v.trim() !== '' ? v.trim() : null;
}

function isId(v: unknown): v is number {
	return typeof v === 'number' && Number.isSafeInteger(v) && v > 0;
}

function parseLinked(v: unknown): StravaLinkedClub | null {
	if (v === null || typeof v !== 'object') return null;
	const r = v as Record<string, unknown>;
	const id = str(r.id);
	const slug = str(r.slug);
	const name = str(r.name);
	return id && slug && name ? { id, slug, name } : null;
}

function parseClub(v: unknown): StravaClub | null {
	if (v === null || typeof v !== 'object') return null;
	const r = v as Record<string, unknown>;
	const name = str(r.name);
	if (!isId(r.strava_club_id) || name === null) return null;
	return {
		stravaClubId: r.strava_club_id,
		name,
		city: str(r.city),
		state: str(r.state),
		country: str(r.country),
		sportType: str(r.sport_type),
		memberCount:
			typeof r.member_count === 'number' && Number.isSafeInteger(r.member_count) && r.member_count >= 0
				? r.member_count
				: null,
		viewerIsAdmin: typeof r.viewer_is_admin === 'boolean' ? r.viewer_is_admin : null,
		linkedClub: parseLinked(r.linked_club),
	};
}

/// A body that is not one of the three shapes throws, so the section shows
/// its error rather than an empty "you're in no clubs" it was never told.
export function parseStravaClubsResult(data: unknown): StravaClubsResult {
	const r = (data ?? {}) as Record<string, unknown>;
	if (r.status === 'not_connected' || r.status === 'reconnect_required') {
		return { status: r.status };
	}
	if (r.status === 'connected' && Array.isArray(r.clubs)) {
		return {
			status: 'connected',
			clubs: r.clubs.map(parseClub).filter((c): c is StravaClub => c !== null),
		};
	}
	throw new Error('unexpected_response');
}

/// "Richmond, Virginia, United States" — whatever parts Strava filled in, in
/// that order, with an exact repeat dropped (a city-state names itself twice).
export function stravaClubLocation(club: Pick<StravaClub, 'city' | 'state' | 'country'>): string {
	const parts: string[] = [];
	for (const p of [club.city, club.state, club.country]) {
		if (p && !parts.includes(p)) parts.push(p);
	}
	return parts.join(', ');
}

/// The create form, prefilled from the Strava club and carrying its id so the
/// new club is linked once it exists.
export function stravaClubSetupHref(club: Pick<StravaClub, 'stravaClubId' | 'name' | 'city' | 'state' | 'country'>): string {
	const params = new URLSearchParams();
	const name = prefilledClubName(club.name);
	if (name) params.set('name', name);
	const location = prefilledClubLocation(stravaClubLocation(club));
	if (location) params.set('location', location);
	params.set('strava_club', String(club.stravaClubId));
	return `/clubs/new?${params.toString()}`;
}

/// The `strava_club` query parameter back as an id, or null for anything
/// that is not a positive integer.
export function parseStravaClubParam(raw: string | null | undefined): number | null {
	if (!raw || !/^[1-9][0-9]{0,15}$/.test(raw)) return null;
	const n = Number(raw);
	return Number.isSafeInteger(n) ? n : null;
}

/// The location half of the prefill, held to the same bound the editor's
/// field and the column's CHECK are.
export function prefilledClubLocation(raw: string | null | undefined): string {
	return Array.from((raw ?? '').trim()).slice(0, TEXT_LIMITS.clubLocationLabel).join('').trim();
}

/// The edge function's refusal codes the clubs page explains in words.
export type StravaClubLinkError =
	| 'strava_admin_required'
	| 'strava_club_already_linked'
	| 'not_club_admin'
	| 'reconnect'
	| 'generic';

export function stravaClubLinkError(code: string | null | undefined): StravaClubLinkError {
	switch (code) {
		case 'strava_admin_required':
		case 'strava_club_already_linked':
		case 'not_club_admin':
			return code;
		case 'refresh_failed':
		case 'strava_not_connected':
			return 'reconnect';
		default:
			return 'generic';
	}
}

/// The sentence for each refusal, shared by the clubs list and the create page.
export const STRAVA_CLUB_LINK_ERROR_KEYS: Record<StravaClubLinkError, MessageKey> = {
	strava_admin_required: 'stravaClubs.errAdminRequired',
	strava_club_already_linked: 'stravaClubs.errAlreadyLinked',
	not_club_admin: 'stravaClubs.errNotClubAdmin',
	reconnect: 'stravaClubs.errReconnect',
	generic: 'stravaClubs.errGeneric',
};

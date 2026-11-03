/// Single source of truth for the public share-challenge fetch shape.
/// Used by both:
///   - apps/web/src/routes/share/challenge/[id]/+page.ts (dev-server SSR),
///   - apps/web/src/routes/og/challenge/[id].png (dev-server card), and
///   - the production share-entity Lambda that owns /share/challenge/* and
///     /og/challenge/*.
///
/// A challenge is anon-readable only when `is_public = true` (challenges RLS),
/// so a non-public one resolves to "not found" here even for a viewer holding
/// its invite link: the invite path is /challenges/join/<token>, never this
/// page (decisions § 2261). The board comes from `challenge_leaderboard`,
/// which already nulls a name the viewer may not see; the page renders the
/// `Runner #ABCD` handle in its place.

import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { isEntityId } from '../core/entity_id';
import { TABLES } from '../core/schema';
import { thrownMessage } from '../core/supabase_error';
import type { ChallengeMetric } from '../social/challenge_progress';

export interface SharedChallenge {
	id: string;
	title: string;
	description: string | null;
	metric: ChallengeMetric;
	scope: string;
	goal_value: number | null;
	starts_at: string;
	ends_at: string;
	participant_count: number;
	creator_id: string | null;
}

export interface SharedChallengeLeader {
	user_id: string | null;
	display_name: string | null;
	value: number;
	rank: number;
}

export interface SharedChallengeLookup {
	challenge: SharedChallenge | null;
	creatorName: string | null;
	leaders: SharedChallengeLeader[];
}

export interface SharedChallengeLookupConfig {
	supabaseUrl: string;
	supabaseAnonKey: string;
}

/// How many board rows the share page and card show.
export const SHARE_CHALLENGE_LEADERS = 5;

const EMPTY: SharedChallengeLookup = { challenge: null, creatorName: null, leaders: [] };

export async function lookupSharedChallenge(
	id: string,
	config: SharedChallengeLookupConfig | null,
	makeClient: (url: string, key: string) => SupabaseClient = (url, key) =>
		createClient(url, key, { auth: { persistSession: false } }),
): Promise<SharedChallengeLookup> {
	if (!config?.supabaseUrl || !config?.supabaseAnonKey) return EMPTY;
	if (!isEntityId(id)) return EMPTY;
	try {
		const supabase = makeClient(config.supabaseUrl, config.supabaseAnonKey);
		const { data: row, error } = await supabase
			.from(TABLES.challenges)
			.select(
				'id, title, description, metric, scope, goal_value, starts_at, ends_at, participant_count, creator_id, is_public',
			)
			.eq('id', id)
			.eq('is_public', true)
			.maybeSingle();
		if (error) {
			console.error('[share-challenge] upstream_unreachable');
			return EMPTY;
		}
		if (!row) return EMPTY;
		const c = row as Record<string, unknown>;
		if (c.is_public === false) return EMPTY;

		// A club-vs-club board ranks clubs, not people; the share page shows
		// only the challenge for those.
		let leaders: SharedChallengeLeader[] = [];
		if (c.scope !== 'club_vs_club') {
			const { data: board, error: boardError } = await supabase.rpc(
				'challenge_leaderboard',
				{ p_challenge_id: id, p_by_team: false },
				{ get: true },
			);
			if (boardError) {
				console.error('[share-challenge] upstream_unreachable');
				return EMPTY;
			}
			leaders = ((board ?? []) as Array<Record<string, unknown>>)
				.slice(0, SHARE_CHALLENGE_LEADERS)
				.map((r) => ({
					user_id: (r.user_id as string | null) ?? null,
					display_name: (r.display_name as string | null) ?? null,
					value: Number(r.value ?? 0),
					rank: Number(r.rank ?? 0),
				}));
		}

		let creatorName: string | null = null;
		if (typeof c.creator_id === 'string') {
			const { data: profile } = await supabase
				.rpc('public_profile_by_id', { p_id: c.creator_id }, { get: true })
				.maybeSingle();
			creatorName =
				(profile as { display_name?: string | null } | null)?.display_name ?? null;
		}

		return {
			challenge: {
				id: c.id as string,
				title: (c.title as string) ?? '',
				description: (c.description as string | null) ?? null,
				metric: c.metric as ChallengeMetric,
				scope: c.scope as string,
				goal_value: c.goal_value == null ? null : Number(c.goal_value),
				starts_at: c.starts_at as string,
				ends_at: c.ends_at as string,
				participant_count: Number(c.participant_count ?? 0),
				creator_id: (c.creator_id as string | null) ?? null,
			},
			creatorName,
			leaders,
		};
	} catch (err) {
		console.error('[share-challenge] upstream_unreachable', thrownMessage(err));
		return EMPTY;
	}
}

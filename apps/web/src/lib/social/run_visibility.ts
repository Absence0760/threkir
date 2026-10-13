/// Who can see a run or a route, as the owner chooses it and as the row
/// stores it (migrations 20270802000001..3, decisions § R7SHARE-1).
///
/// Three columns' worth of state reach the owner as one of four levels:
/// `is_public` is Public, `followers_only` is Followers, a live grant in
/// `run_shares` / `route_shares` is Specific people, and none of them is Only
/// me. `is_public` wins over the other two, which is also what the server's
/// normalize trigger enforces. A grant is NOT cleared by choosing Followers or
/// Public — it is moot there and comes back into force if the owner narrows
/// again — but choosing Only me revokes every grant, because "only me" with a
/// named reader left in place would be a lie.
///
/// Lives in its own supabase-free module so it's unit-testable with
/// `tsx --test` (data.ts pulls in `./supabase` → `$app/env`, which the tsx
/// loader can't resolve).

export type AudienceLevel = 'private' | 'followers' | 'specific' | 'public';

export const AUDIENCE_LEVELS: readonly AudienceLevel[] = ['private', 'followers', 'specific', 'public'];

/// The two stored columns a level writes. Specific people is a private row
/// plus grants, so it writes the same columns as Only me.
export interface AudienceColumns {
	is_public: boolean;
	followers_only: boolean;
}

export function audienceColumns(level: AudienceLevel): AudienceColumns {
	return {
		is_public: level === 'public',
		followers_only: level === 'followers',
	};
}

/// The level a row is at. `shareCount` is the number of live grants; it only
/// decides between Only me and Specific people, because a grant on a public or
/// followers-only entity changes nothing the owner can see from the level.
export function audienceOf(
	row: { is_public: boolean | null; followers_only?: boolean | null },
	shareCount: number,
): AudienceLevel {
	if (row.is_public === true) return 'public';
	if (row.followers_only === true) return 'followers';
	return shareCount > 0 ? 'specific' : 'private';
}

/// The universal `privacy_default` preference, mapped to the columns a NEW
/// run is written with. `followers` now writes `followers_only` instead of
/// collapsing to owner-only, which is the bug the followers level fixes; the
/// server stores it as owner-only until audience sharing is switched on, so
/// nothing saved before the switch widens on the day it flips (§ R7SHARE-2).
/// Unknown values fail closed to owner-only. Callers pass the effective value
/// (`effective(settings, 'privacy_default', 'followers')`), so the registered
/// unset fallback is theirs to apply.
export function privacyDefaultToAudience(pref: string | null | undefined): AudienceColumns {
	if (pref === 'public') return audienceColumns('public');
	if (pref === 'followers') return audienceColumns('followers');
	return audienceColumns('private');
}

/// Whether choosing `next` has to revoke grants first. Only me is the one
/// level that promises no named reader is left.
export function levelRevokesGrants(next: AudienceLevel): boolean {
	return next === 'private';
}

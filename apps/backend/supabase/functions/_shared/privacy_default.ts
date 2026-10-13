// The visibility a server-side import gives a new run, from the owner's
// universal `privacy_default` preference (docs/backend/settings.md).
//
// Mirrors the web writer (`apps/web/src/lib/social/run_visibility.ts`
// `privacyDefaultToAudience`): `public` publishes, `followers` — and an unset
// pref, whose registered fallback is `followers` — writes `followers_only`,
// and anything else is owner-only. `followers_only` is stored as owner-only by
// the server until audience sharing is switched on (migration 20270802000001,
// decisions § R7SHARE-2), and a followers-only run is never in a feed or a
// notification, so importing history with the default never publishes it.
// A failed settings read falls closed to owner-only.

import type { DbClient } from './database.ts';

export interface ImportAudience {
  isPublic: boolean;
  followersOnly: boolean;
}

export const OWNER_ONLY: ImportAudience = { isPublic: false, followersOnly: false };

export function importAudience(prefs: Record<string, unknown> | null | undefined): ImportAudience {
  const pref = prefs?.privacy_default ?? 'followers';
  if (pref === 'public') return { isPublic: true, followersOnly: false };
  if (pref === 'followers') return { isPublic: false, followersOnly: true };
  return OWNER_ONLY;
}

export async function resolveImportAudience(client: DbClient, userId: string): Promise<ImportAudience> {
  try {
    const { data, error } = await client
      .from('user_settings')
      .select('prefs')
      .eq('user_id', userId)
      .maybeSingle();
    if (error) return OWNER_ONLY;
    return importAudience((data?.prefs ?? null) as Record<string, unknown> | null);
  } catch (_) {
    return OWNER_ONLY;
  }
}

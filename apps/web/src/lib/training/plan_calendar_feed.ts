// The subscribable plan calendar feed (migration 20270910000001, the
// plan-calendar Edge Function). The URL is the credential, because a calendar
// app sends no header, so the token is shown once when it is minted and can
// never be read back: the owner only ever sees the feed's two timestamps.

import type { SupabaseClient } from '@supabase/supabase-js';
import type { AppDatabase } from '#lib/core/database.ts';
import { dbError } from '#lib/core/supabase_error.ts';

const TOKEN = /^[0-9a-f]{96}$/;

export interface PlanCalendarFeedStatus {
	createdAt: string;
	lastFetchedAt: string | null;
}

export function isPlanCalendarFeedToken(token: string): boolean {
	return TOKEN.test(token);
}

/// The https URL a calendar subscribes to. Null for anything that is not a
/// token `rotate_plan_calendar_feed` could have minted, so a malformed RPC
/// result can never be offered as a link.
export function planCalendarFeedUrl(supabaseUrl: string, token: string): string | null {
	if (!isPlanCalendarFeedToken(token)) return null;
	let base: URL;
	try {
		base = new URL(supabaseUrl);
	} catch {
		return null;
	}
	const root = base.origin + base.pathname.replace(/\/+$/, '');
	return `${root}/functions/v1/plan-calendar/${token}.ics`;
}

/// The same feed as a `webcal:` link, which Apple Calendar and Outlook open
/// as "subscribe" rather than downloading a one-off copy. Only an https URL
/// converts: webcal has no secure variant, and a plain-http feed (the local
/// stack) is not worth handing to a calendar app.
export function webcalUrl(httpsUrl: string): string | null {
	return httpsUrl.startsWith('https://') ? `webcal://${httpsUrl.slice('https://'.length)}` : null;
}

export async function fetchPlanCalendarFeedStatus(
	client: SupabaseClient<AppDatabase>,
): Promise<PlanCalendarFeedStatus | null> {
	const { data, error } = await client.rpc('plan_calendar_feed_status', undefined, { get: true });
	if (error) throw dbError(error);
	const row = Array.isArray(data) ? data[0] : null;
	if (!row || typeof row.created_at !== 'string') return null;
	return { createdAt: row.created_at, lastFetchedAt: row.last_fetched_at ?? null };
}

/// Mints a new token, replacing any existing feed, so the previous URL stops
/// working at once. Returns the only copy of the token there will ever be.
export async function rotatePlanCalendarFeed(client: SupabaseClient<AppDatabase>): Promise<string> {
	const { data, error } = await client.rpc('rotate_plan_calendar_feed');
	if (error) throw dbError(error);
	if (typeof data !== 'string' || !isPlanCalendarFeedToken(data)) {
		throw new Error('rotate_plan_calendar_feed returned no token');
	}
	return data;
}

export async function revokePlanCalendarFeed(client: SupabaseClient<AppDatabase>): Promise<void> {
	const { error } = await client.rpc('revoke_plan_calendar_feed');
	if (error) throw dbError(error);
}

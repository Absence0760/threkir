// Forgetting a Strava grant on our side. Shared by the user-initiated
// Disconnect in `strava-import` and the athlete-deauthorization event in
// `strava-webhook`, so both leave the integration in the same state: Vault
// token rows gone, `disconnected_at` stamped, sync cursor cleared.

import type { DbClient } from './database.ts';

export type StravaDisconnectReason = 'user_initiated' | 'athlete_deauthorized';

export type StravaDisconnectResult = 'ok' | 'vault_cleanup_failed' | 'stamp_failed';

/// Drop the user's Strava tokens from Vault and stamp the integration row
/// disconnected. Idempotent. Needs a service-role client:
/// `delete_user_provider_secrets` is granted to service_role only.
export async function disconnectStravaLocally(
	supabase: DbClient,
	userId: string,
	reason: StravaDisconnectReason,
): Promise<StravaDisconnectResult> {
	const { error: rpcErr } = await supabase.rpc('delete_user_provider_secrets', {
		p_user_id: userId,
		p_provider: 'strava',
	});
	if (rpcErr) {
		console.error('strava disconnect: delete_user_provider_secrets failed (code):', rpcErr.code ?? 'unknown');
		return 'vault_cleanup_failed';
	}

	// The row is kept, not deleted, so the UI offers Reconnect and the
	// token-refresh sweep skips it (20261004_001).
	const { error: stampErr } = await supabase
		.from('integrations')
		.update({
			disconnected_at: new Date().toISOString(),
			disconnected_reason: reason,
			sync_cursor: null,
		})
		.eq('user_id', userId)
		.eq('provider', 'strava');
	if (stampErr) {
		console.error('strava disconnect: stamp disconnected_at failed (code):', stampErr.code ?? 'unknown');
		return 'stamp_failed';
	}
	return 'ok';
}

export type StravaWebhookEvent = {
	object_type?: string;
	object_id?: number;
	aspect_type?: string;
	owner_id?: number;
	event_time?: number;
	updates?: Record<string, unknown> | null;
};

/// Strava's deauthorization push: the athlete revoked our access from their
/// Strava settings. Strava sends `updates.authorized` as the string
/// `"false"`; a boolean is accepted too.
export function isAthleteDeauthorization(event: StravaWebhookEvent): boolean {
	if (event.object_type !== 'athlete' || event.aspect_type !== 'update') return false;
	const authorized = event.updates?.authorized;
	return authorized === 'false' || authorized === false;
}

/// Disconnect every live integration linked to the deauthorized Strava
/// athlete. Strava API terms require acting on this event; the tokens are
/// already dead at Strava's end, so no `/oauth/deauthorize` call is made.
export async function disconnectDeauthorizedAthlete(
	supabase: DbClient,
	athleteId: number,
): Promise<{ disconnected: number; failed: number }> {
	const { data, error } = await supabase
		.from('integrations')
		.select('user_id')
		.eq('provider', 'strava')
		.eq('external_id', String(athleteId))
		.is('disconnected_at', null);
	if (error) {
		console.error('strava deauthorization: integration lookup failed (code):', error.code ?? 'unknown');
		return { disconnected: 0, failed: 1 };
	}
	let disconnected = 0;
	let failed = 0;
	for (const row of data ?? []) {
		const result = await disconnectStravaLocally(supabase, row.user_id, 'athlete_deauthorized');
		if (result === 'ok') disconnected++;
		else failed++;
	}
	return { disconnected, failed };
}

// The refusals the `connect` action answers with, as stable codes.
//
// A client maps each one to its own localized sentence (`stravaConnectError`
// in apps/web/src/lib/integrations/strava_sync_result.ts and
// packages/core_models/lib/src/strava_sync_result.dart) and never renders the
// body's text. Every refusal is the `{ error: '<code>' }` envelope the other
// actions already use; the missing-scope refusal used to be an English
// sentence in a text/plain body, which a client could only show verbatim or
// not at all. Adding a code here without teaching the two clients is safe:
// an unknown code reads as their generic connect failure.
export const STRAVA_CONNECT_ERROR_CODES = [
	'invalid_code',
	'invalid_scope',
	'invalid_redirect_uri',
	'strava_not_configured',
	'strava_token_exchange_failed',
	'missing_scope',
	'store_integration_failed',
	'store_tokens_failed',
] as const;

export type StravaConnectErrorCode = (typeof STRAVA_CONNECT_ERROR_CODES)[number];

export function connectRefusal(code: StravaConnectErrorCode, status: number): Response {
	return Response.json({ error: code }, { status });
}

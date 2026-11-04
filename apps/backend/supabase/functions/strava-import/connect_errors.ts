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

// The sentence the missing-scope refusal used to be, carried beside its code
// for mobile builds that predate the code. Those builds show a failed connect
// as the transport's exception text, which prints the decoded body, so this
// field is what keeps the sentence in front of them; current clients read
// `error` only and never render `message`. Web builds of the same age read
// `error` only, so they gain nothing from it and lose nothing without it.
// Remove it (and its test) once the minimum supported mobile build includes
// commit 497c1b42e, the one that words `missing_scope` from the catalogue.
export const LEGACY_CONNECT_MESSAGES: Partial<Record<StravaConnectErrorCode, string>> = {
	missing_scope:
		'Strava connection is missing the activity:read_all scope. Please reconnect and accept all permissions.',
};

export function connectRefusal(code: StravaConnectErrorCode, status: number): Response {
	const message = LEGACY_CONNECT_MESSAGES[code];
	return Response.json(message ? { error: code, message } : { error: code }, { status });
}

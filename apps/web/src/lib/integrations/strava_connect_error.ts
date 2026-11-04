/// The `AppError` a refused Strava connect throws, so the Settings card shows
/// catalogue copy for the refusal and never the function's code or text
/// (decisions § 2316). The code-to-reason map is the parity-paired
/// `stravaConnectError`; this is the web half of the wording.

import { AppError } from '../core/app_error';
import { edgeFunctionErrorCode } from '../core/edge_function_error';
import type { MessageKey } from '../i18n/messages';
import { stravaConnectError, type StravaConnectError } from './strava_sync_result';

export const STRAVA_CONNECT_ERROR_KEYS: Record<Exclude<StravaConnectError, 'generic'>, MessageKey> = {
	not_configured: 'settingsIntegrations.stravaNotConfigured',
	missing_scope: 'settingsIntegrations.stravaErrMissingScope',
	code_rejected: 'settingsIntegrations.stravaErrCodeRejected',
	signed_out: 'errorCopy.signedOut',
	reconnect: 'settingsIntegrations.stravaErrReconnect',
};

/// The error to throw for a connect the function refused with [code], or null
/// when the card has no words of its own for it and the caller should rethrow
/// the transport's error for `errorCopy` to classify (offline, rate limit).
export function stravaConnectAppError(code: string | null | undefined): AppError | null {
	const reason = stravaConnectError(code);
	if (reason === 'generic') return null;
	return new AppError(STRAVA_CONNECT_ERROR_KEYS[reason], { message: code ?? reason });
}

/// What to throw for any `strava-import` call (connect, sync, disconnect) that
/// failed. A refusal the card has words for becomes its `AppError`; any other
/// coded refusal is rethrown as the bare code, so `errorCopy` can still tell a
/// rate limit (`rate_limit_exceeded`) from the generic line and the code is
/// logged rather than shown; with no readable envelope the transport's own
/// error goes through as it came, so a dropped connection
/// (`FunctionsFetchError`) still reads as offline.
export async function stravaRefusal(fnError: unknown): Promise<unknown> {
	const code = await edgeFunctionErrorCode(fnError);
	return stravaConnectAppError(code) ?? (code ? new Error(code) : fnError);
}

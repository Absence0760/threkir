/// The `AppError` a refused Strava connect throws, so the Settings card shows
/// catalogue copy for the refusal and never the function's code or text
/// (decisions § 2316). The code-to-reason map is the parity-paired
/// `stravaConnectError`; this is the web half of the wording.

import { AppError } from '../core/app_error';
import type { MessageKey } from '../i18n/messages';
import { stravaConnectError, type StravaConnectError } from './strava_sync_result';

export const STRAVA_CONNECT_ERROR_KEYS: Record<Exclude<StravaConnectError, 'generic'>, MessageKey> = {
	not_configured: 'settingsIntegrations.stravaNotConfigured',
	missing_scope: 'settingsIntegrations.stravaErrMissingScope',
	code_rejected: 'settingsIntegrations.stravaErrCodeRejected',
	signed_out: 'errorCopy.signedOut',
};

/// The error to throw for a connect the function refused with [code], or null
/// when the card has no words of its own for it and the caller should rethrow
/// the transport's error for `errorCopy` to classify (offline, rate limit).
export function stravaConnectAppError(code: string | null | undefined): AppError | null {
	const reason = stravaConnectError(code);
	if (reason === 'generic') return null;
	return new AppError(STRAVA_CONNECT_ERROR_KEYS[reason], { message: code ?? reason });
}

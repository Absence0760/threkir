/**
 * The text of a failure as it may be logged. Console output reaches error
 * reporting as breadcrumbs once a reader has consented to it, and server text
 * can quote the row it refused (`Key (email)=(…)`, `invalid input syntax for
 * type uuid: "…"`). Quoted runs, key/value details and email addresses are
 * blanked and the rest is cut short; the code and the context still say which
 * failure it was.
 *
 * Dart twin: `apps/mobile_android/lib/loggable_message.dart`.
 */

/// Longest message `loggableMessage` returns.
export const LOGGED_MESSAGE_MAX_CHARS = 160;

export function loggableMessage(message: string): string {
	const cleaned = message
		.replace(/\([^()]*\)=\([^()]*\)/g, '(…)=(…)')
		.replace(/"[^"]*"/g, '"…"')
		.replace(/'[^']*'/g, "'…'")
		.replace(/[^\s@"'()]+@[^\s@"'()]+/g, '<email>');
	return cleaned.length > LOGGED_MESSAGE_MAX_CHARS
		? `${cleaned.slice(0, LOGGED_MESSAGE_MAX_CHARS - 1)}…`
		: cleaned;
}

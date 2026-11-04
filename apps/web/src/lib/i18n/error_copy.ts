/// The sentence a reader sees in place of a thrown error's own text.
///
/// A failure toast framed as `m('x.failed', { error: thrownMessage(e) })`
/// dropped the database's or the browser's English into a localized sentence:
/// "Échec de la publication : new row violates check constraint …" or
/// "… : Failed to fetch". This maps the failures the app knows how to name to
/// catalogue copy and everything else to a generic line, and sends the code
/// and a scrubbed copy of the text to the console instead, where it still
/// helps whoever debugs it.
///
/// The lookup arrives as an argument, like `rate_limit_message.ts`: `m` lives
/// in a runes module the `tsx --test` runner cannot compile.

import type { MessageKey } from './messages';
import type { Translate } from './rate_limit_message';
import { rateLimitErrorMessage } from './rate_limit_message';
import { databaseCodeDecides } from '../core/auth_errors';
import { AppError } from '../core/app_error';
import { loggableMessage } from '../util/loggable_message';

function field(e: unknown, name: 'code' | 'message' | 'name'): string {
	if (e && typeof e === 'object') {
		const v = (e as Record<string, unknown>)[name];
		if (typeof v === 'string') return v;
	}
	return typeof e === 'string' && name === 'message' ? e : '';
}

function status(e: unknown): number | null {
	if (e && typeof e === 'object') {
		const v = (e as Record<string, unknown>).status;
		if (typeof v === 'number') return v;
	}
	return null;
}

/// The catalogue key for a failure. An `AppError` names its own; a rate-limit
/// refusal has a sentence of its own, which `errorCopy` checks for first.
export function errorCopyKey(e: unknown): MessageKey {
	if (e instanceof AppError) return e.key;
	const code = field(e, 'code');
	const name = field(e, 'name');
	const msg = field(e, 'message').toLowerCase();
	const httpStatus = status(e);
	// A coded database failure is classified by its code, not by a word its
	// message happens to contain (a constraint, parameter or bucket name).
	const says = (text: string) => !databaseCodeDecides(code) && msg.includes(text);

	if (code === '23P01') return 'planDetail.planOverlap';
	if (name === 'AbortError' || name === 'TimeoutError' || code === '57014' || says('timed out')) {
		return 'errorCopy.timeout';
	}
	if (
		(name === 'TypeError' &&
			(msg.includes('failed to fetch') || msg.includes('networkerror') || msg === 'load failed')) ||
		// supabase-js's wrapper for a fetch that rejected before an Edge
		// Function answered: the same failure as the bare TypeError above.
		name === 'FunctionsFetchError' ||
		(typeof navigator !== 'undefined' && navigator.onLine === false)
	) {
		return 'errorCopy.offline';
	}
	if (
		httpStatus === 401 ||
		code === 'PGRST301' ||
		code === 'PGRST303' ||
		// The RPCs' own signed-out guard: `raise exception 'not authenticated'
		// using errcode = '42501'` when auth.uid() is null.
		(code === '42501' && msg.includes('not authenticated')) ||
		says('not signed in') ||
		says('not authenticated') ||
		says('jwt expired')
	) {
		return 'errorCopy.signedOut';
	}
	if (code === '42501' || httpStatus === 403 || says('only the plan owner')) {
		return 'errorCopy.forbidden';
	}
	if (
		httpStatus === 429 ||
		code === 'over_request_rate_limit' ||
		code === 'over_email_send_rate_limit' ||
		code === 'over_sms_send_rate_limit' ||
		says('rate limit') ||
		// The Edge Functions' shared limiter (`_shared/rate_limit.ts`) answers
		// 429 with this code; a rethrown `new Error(code)` keeps only the code.
		code === 'rate_limit_exceeded' ||
		says('rate_limit_exceeded') ||
		says('for security purposes, you can only request this')
	) {
		return 'errorCopy.tooManyRequests';
	}
	if (code === 'same_password') return 'errorCopy.samePassword';
	if (code === 'weak_password') return 'errorCopy.weakPassword';
	if (code === 'email_exists' || code === 'user_already_exists') return 'errorCopy.emailTaken';
	if (code === '23505') return 'errorCopy.duplicate';
	if (code === 'PGRST116' || code === 'P0002' || httpStatus === 404 || says('not found')) {
		return 'errorCopy.notFound';
	}
	if (
		code === '23514' ||
		code === '23502' ||
		code === '22023' ||
		code === '22P02' ||
		code === '22007' ||
		code === '22003' ||
		httpStatus === 400
	) {
		return 'errorCopy.invalid';
	}
	return 'errorCopy.generic';
}

/// Localized copy for a thrown value, to drop into a `{error}` slot or show
/// on its own. The code and a scrubbed message (`loggableMessage`) go to the
/// console, never the UI. An `AppError` renders its own key and params: the
/// one way a thrown failure says something more specific than its category.
///
/// `fallback` replaces the generic line for a failure the app cannot name,
/// for a surface that shows the copy on its own and has a sentence of its
/// own that says more than "Something went wrong".
export function errorCopy(
	e: unknown,
	t: Translate,
	context = 'operation failed',
	fallback?: MessageKey,
): string {
	console.error(context, {
		code: field(e, 'code') || undefined,
		message: loggableMessage(field(e, 'message')),
	});
	if (e instanceof AppError) return t(e.key, e.params);
	const code = field(e, 'code');
	const rateLimited = rateLimitErrorMessage(t, { code, message: field(e, 'message') });
	if (rateLimited) return rateLimited;
	const key = errorCopyKey(e);
	return t(key === 'errorCopy.generic' && fallback ? fallback : key);
}

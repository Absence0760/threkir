import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
	classifyAuthError,
	authErrorMessageKey,
	databaseCodeDecides,
	isDatabaseCode,
	signUpErrorRevealsAccountExistence
} from './auth_errors.js';

/// Duck-typed stand-in for supabase-js's `AuthApiError` (carries `code`
/// + `status`) so the classifier can be exercised without importing the
/// supabase auth types. Mirrors `_FakeAuthException` in mobile's
/// auth_error_test.dart.
function authError(message: string, opts: { code?: string; status?: number } = {}) {
	return { message, code: opts.code, status: opts.status };
}

test('fetch failure → offline', () => {
	assert.equal(classifyAuthError(new TypeError('Failed to fetch')), 'offline');
	assert.equal(classifyAuthError(new TypeError('NetworkError when attempting to fetch')), 'offline');
	// Safari's wording for the same condition.
	assert.equal(classifyAuthError(new TypeError('Load failed')), 'offline');
});

test('invalid_credentials code → invalidCredentials', () => {
	assert.equal(
		classifyAuthError(authError('Invalid login credentials', { code: 'invalid_credentials', status: 400 })),
		'invalidCredentials'
	);
});

test('"Invalid login credentials" message (no code) → invalidCredentials', () => {
	assert.equal(classifyAuthError(authError('Invalid login credentials')), 'invalidCredentials');
});

test('status 429 → rateLimited', () => {
	assert.equal(classifyAuthError(authError('Too many requests', { status: 429 })), 'rateLimited');
});

test('over_email_send_rate_limit code → rateLimited', () => {
	assert.equal(
		classifyAuthError(
			authError('For security purposes, you can only request this after 60 seconds', {
				code: 'over_email_send_rate_limit'
			})
		),
		'rateLimited'
	);
});

test('an Edge Function limiter code rethrown as the message → rateLimited', () => {
	// `_shared/rate_limit.ts` answers 429 with `rate_limit_exceeded`; a caller
	// that rethrows `new Error(code)` keeps the code and drops the status.
	assert.equal(classifyAuthError(new Error('rate_limit_exceeded')), 'rateLimited');
});

test('user_already_exists code → emailExists', () => {
	assert.equal(
		classifyAuthError(authError('User already registered', { code: 'user_already_exists', status: 422 })),
		'emailExists'
	);
});

test('"already registered" message (no code) → emailExists', () => {
	assert.equal(classifyAuthError(authError('User already registered')), 'emailExists');
});

test('email_not_confirmed code → emailNotConfirmed', () => {
	assert.equal(
		classifyAuthError(authError('Email not confirmed', { code: 'email_not_confirmed', status: 400 })),
		'emailNotConfirmed'
	);
});

test('invalid_grant + "Email not confirmed" message → emailNotConfirmed (not invalidCredentials)', () => {
	// GoTrue's token endpoint can report an unconfirmed-email sign-in via
	// the OAuth-style `invalid_grant` error with the descriptive message
	// "Email not confirmed", not the dedicated code. The specific message
	// must win over the generic invalid_grant → invalidCredentials branch
	// so the user gets the resend affordance, not a wrong-password banner.
	assert.equal(
		classifyAuthError(authError('Email not confirmed', { code: 'invalid_grant', status: 400 })),
		'emailNotConfirmed'
	);
});

test('otp_expired code → linkExpired', () => {
	// The refusal GoTrue redirects with when an emailed sign-in,
	// confirmation or reset link is opened after it expired or twice.
	assert.equal(
		classifyAuthError(authError('Email link is invalid or has expired', { code: 'otp_expired', status: 403 })),
		'linkExpired'
	);
});

test('"link is invalid or has expired" message (no code) → linkExpired', () => {
	assert.equal(classifyAuthError(authError('Email link is invalid or has expired')), 'linkExpired');
});

test('weak_password code → weakPassword', () => {
	assert.equal(
		classifyAuthError(
			authError('Password should be at least 8 characters', { code: 'weak_password', status: 422 })
		),
		'weakPassword'
	);
});

test('"password should be at least" message (no code) → weakPassword', () => {
	assert.equal(classifyAuthError(authError('Password should be at least 6 characters')), 'weakPassword');
});

test('a database code is not overridden by a word in its message', () => {
	assert.equal(
		classifyAuthError(authError('duplicate key value violates unique constraint "rate limit buckets_pkey"', { code: '23505' })),
		'generic'
	);
	assert.equal(classifyAuthError(authError('relation "invalid credentials" does not exist', { code: '42P01' })), 'generic');
	assert.equal(classifyAuthError(authError('failed to fetch row', { code: 'PGRST116' })), 'generic');
});

test('a bare-raise P0001 is still read by its message', () => {
	assert.equal(
		classifyAuthError(authError('rate limit exceeded for create_club, retry in 30s', { code: 'P0001' })),
		'rateLimited'
	);
});

test('a five-character code that is not a SQLSTATE still has its message read', () => {
	assert.equal(classifyAuthError(authError('Failed to fetch', { code: 'EPIPE' })), 'offline');
	assert.equal(classifyAuthError(authError('Invalid login credentials', { code: 'stale' })), 'invalidCredentials');
});

test('isDatabaseCode accepts SQLSTATE and PostgREST codes in either case', () => {
	const codes = ['23505', '42501', '42P01', '22P02', '57014', 'P0001', 'P0002', 'XX000', 'HV000', 'F0000',
		'TR001', 'RR001', 'RR002', 'RW001', 'PGRST116', 'PGRST301', 'PGRST303', 'PT429'];
	for (const c of codes) {
		assert.ok(isDatabaseCode(c), c);
		assert.ok(isDatabaseCode(c.toLowerCase()), c.toLowerCase());
	}
	for (const c of codes.filter((c) => c !== 'P0001')) assert.ok(databaseCodeDecides(c), c);
	assert.ok(!databaseCodeDecides('P0001'));
	assert.ok(!databaseCodeDecides('p0001'));
});

test('no GoTrue, Storage or network code is taken for a database code', () => {
	const codes = [
		// GoTrue (auth-js ErrorCode): snake_case words, the shortest seven long.
		'bad_jwt', 'bad_json', 'conflict', 'not_admin', 'otp_expired', 'invalid_credentials', 'invalid_grant',
		'email_exists', 'user_already_exists', 'email_not_confirmed', 'weak_password', 'same_password',
		'over_request_rate_limit', 'over_email_send_rate_limit', 'session_not_found', 'user_not_found',
		// Storage API codes, and its string statusCode.
		'NoSuchKey', 'NoSuchBucket', 'InvalidJWT', 'AccessDenied', 'EntityTooLarge', 'S3Error', '404', '400',
		// Node / undici network errnos, five-letter ones included.
		'EPIPE', 'EPERM', 'EBUSY', 'EXDEV', 'ECONNREFUSED', 'ETIMEDOUT', 'EAI_AGAIN', 'UND_ERR_CONNECT_TIMEOUT',
		// Five characters but no SQLSTATE class, and PGRST without its digits.
		'10000', 'ABCDE', 'stale', 'PGRST', 'PGRSTX', '',
	];
	for (const c of codes) {
		assert.ok(!isDatabaseCode(c), c);
		assert.ok(!isDatabaseCode(c.toLowerCase()), c.toLowerCase());
	}
	assert.ok(!isDatabaseCode(null));
	assert.ok(!isDatabaseCode(undefined));
});

test('every SQLSTATE a migration raises is a database code', () => {
	const dir = resolve('../backend/supabase/migrations');
	const seen = new Set<string>();
	for (const file of readdirSync(dir).filter((f) => f.endsWith('.sql'))) {
		const sql = readFileSync(resolve(dir, file), 'utf-8');
		for (const m of sql.matchAll(/errcode\s*=\s*'([0-9A-Za-z]{5})'/gi)) seen.add(m[1]);
	}
	assert.ok(seen.size >= 10, `read ${seen.size} SQLSTATEs from the migrations`);
	for (const c of seen) assert.ok(isDatabaseCode(c), `${c} is raised by a migration`);
});

test('unrecognised error → generic', () => {
	assert.equal(classifyAuthError(new Error('boom')), 'generic');
});

test('null / undefined / non-error values → generic, never throw', () => {
	assert.equal(classifyAuthError(null), 'generic');
	assert.equal(classifyAuthError(undefined), 'generic');
	assert.equal(classifyAuthError('boom'), 'generic');
});

test('sign-up neutralises an existing-email error (no account-existence oracle, issue #399)', () => {
	// With GoTrue enable_confirmations=false a duplicate sign-up throws
	// user_already_exists; the sign-up surface must collapse that to the
	// SAME neutral check-your-email outcome a fresh sign-up shows, never
	// a distinct "that email already has an account" message.
	const dup = authError('User already registered', { code: 'user_already_exists', status: 422 });
	assert.equal(signUpErrorRevealsAccountExistence(classifyAuthError(dup)), true);
	// The message-shape classification itself is unchanged — LOGIN still
	// reads emailExists as before; only the sign-up call site neutralises.
	assert.equal(classifyAuthError(dup), 'emailExists');
});

test('sign-up does NOT neutralise non-enumerating auth errors', () => {
	for (const err of [
		new TypeError('Failed to fetch'),
		authError('Invalid login credentials', { code: 'invalid_credentials', status: 400 }),
		authError('Too many requests', { status: 429 }),
		authError('Password should be at least 8 characters', { code: 'weak_password', status: 422 }),
		authError('Email not confirmed', { code: 'email_not_confirmed', status: 400 }),
		new Error('boom')
	]) {
		assert.equal(signUpErrorRevealsAccountExistence(classifyAuthError(err)), false);
	}
});

test('every kind maps to a distinct message key', () => {
	const kinds = [
		'offline',
		'invalidCredentials',
		'rateLimited',
		'emailExists',
		'emailNotConfirmed',
		'linkExpired',
		'weakPassword',
		'generic'
	] as const;
	const keys = kinds.map(authErrorMessageKey);
	assert.equal(new Set(keys).size, kinds.length);
	// No key resolves to the raw-jargon fallback path.
	for (const key of keys) assert.match(key, /^login\.error/);
});

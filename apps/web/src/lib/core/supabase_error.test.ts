import { test } from 'node:test';
import assert from 'node:assert/strict';

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { inspect } from 'node:util';

import {
	appErrorMessage,
	DbError,
	dbError,
	isPlanOverlapError,
	isPlanTrimBlockedError,
	isPlanRestartRaceAheadError,
	PlanOverlapError,
	supabaseErrorFields,
	isDuplicateKeyError,
	thrownMessage
} from './supabase_error';
import { stripComments } from './strip_comments';

test('supabaseErrorFields keeps only code + message, drops details/hint', () => {
	// Reason: the server handlers log Supabase errors on paths carrying
	// Art 9 health/injury chat (coach) and precise location (routes). A
	// raw PostgrestError carries `.details` and `.hint`, which can echo
	// row fragments — the caller's chat content, emails, injury free
	// text — straight into CloudWatch. This helper is the scrub every
	// log site routes through; pin that it never carries the leaky
	// fields through. /audit/pii-in-logs.
	const raw = {
		code: '23505',
		message: 'duplicate key value violates unique constraint',
		details: "Key (user_id, content)=(uuid, 'left knee ITB flare, DNF at mile 62') already exists.",
		hint: 'runner@example.com',
	};
	const safe = supabaseErrorFields(raw);
	assert.deepEqual(safe, {
		code: '23505',
		message: 'duplicate key value violates unique constraint',
	});
	// The scrubbed object, serialised the way console.error would emit
	// it, must not carry any PII fragment from details/hint.
	const serialised = JSON.stringify(safe);
	assert.doesNotMatch(serialised, /ITB flare/);
	assert.doesNotMatch(serialised, /runner@example\.com/);
	assert.doesNotMatch(serialised, /details|hint/);
});

test('supabaseErrorFields tolerates null / undefined / empty errors', () => {
	assert.deepEqual(supabaseErrorFields(null), { code: undefined, message: undefined });
	assert.deepEqual(supabaseErrorFields(undefined), { code: undefined, message: undefined });
	assert.deepEqual(supabaseErrorFields({}), { code: undefined, message: undefined });
});

test('isDuplicateKeyError matches 23505 and nothing else', () => {
	// Reason: this is the predicate that turns a double-tapped Join into a
	// no-op. Widening it would swallow a real failure — 23503 is a dangling
	// FK, 23514 a CHECK the row genuinely violates, 42501 an RLS refusal —
	// and each of those must still reach the caller as a failure.
	assert.equal(isDuplicateKeyError({ code: '23505' }), true);
	for (const code of ['23503', '23514', '23502', '42501', 'PGRST116', '', '2350']) {
		assert.equal(
			isDuplicateKeyError({ code }),
			false,
			`${code} is not a unique violation and must not be absorbed`,
		);
	}
	assert.equal(isDuplicateKeyError(null), false);
	assert.equal(isDuplicateKeyError(undefined), false);
	assert.equal(isDuplicateKeyError({}), false);
	assert.equal(isDuplicateKeyError({ code: null }), false);
});

test('every join-shaped write in data.ts absorbs a duplicate through the one predicate', () => {
	// Reason: five writes hand-rolled `error.code !== '23505'` and a sixth —
	// joinChallenge — never got it, so the (challenge_id, user_id) primary key
	// turned a double-tap on Join into a raw failure toast for the state the
	// user had already reached. A comparison copied to each site is a
	// comparison that can be missed at a site; there is now one predicate, and
	// no site may restate the literal.
	const source = readFileSync(resolve('src/lib/core/data.ts'), 'utf-8');
	const stripped = stripComments(source);
	assert.doesNotMatch(
		stripped,
		/'23505'/,
		"data.ts must test for a duplicate through isDuplicateKeyError, not by restating '23505'",
	);
	for (const fn of [
		'bookmarkRoute',
		'joinClub',
		'joinChallenge',
	]) {
		const start = stripped.indexOf(`export async function ${fn}(`);
		assert.ok(start > 0, `${fn} not found — rename it here too.`);
		const body = stripped.slice(start, stripped.indexOf('\nexport ', start + 1));
		assert.match(
			body,
			/isDuplicateKeyError\(/,
			`${fn} must absorb a duplicate insert — re-pressing it is the success case restated.`,
		);
	}
});

test('a follow absorbs a duplicate in SQL, so followUser has no client insert to guard', () => {
	// Reason: followUser moved off a client insert onto the request_follow RPC
	// (decisions § 1967), so the duplicate the predicate above guards is now
	// absorbed where the rows are written. Both of its inserts must still say so.
	const stripped = stripComments(readFileSync(resolve('src/lib/core/data.ts'), 'utf-8'));
	const start = stripped.indexOf('export async function followUser(');
	const body = stripped.slice(start, stripped.indexOf('\nexport ', start + 1));
	assert.match(body, /\.rpc\('request_follow'/);
	const sql = readFileSync(
		resolve('../backend/supabase/migrations/20270822000001_private_profiles.sql'),
		'utf-8',
	);
	const fn = sql.slice(sql.indexOf('create or replace function public.request_follow'));
	const fnBody = fn.slice(0, fn.indexOf('$$;'));
	assert.equal((fnBody.match(/on conflict do nothing/g) ?? []).length, 2);
});

test('thrownMessage reads a raw PostgREST error instead of printing [object Object]', () => {
	assert.equal(thrownMessage({ message: 'permission denied for table events', code: '42501', details: 'row' }), 'permission denied for table events (42501)');
	assert.equal(thrownMessage({ message: 'timeout', code: '' }), 'timeout');
	assert.equal(thrownMessage(new Error('boom')), 'boom');
	assert.equal(thrownMessage('plain'), 'plain');
	for (const v of [{ foo: 'bar' }, null, undefined, 42, { message: 7 }]) assert.equal(thrownMessage(v), '');
});

const PII_ERROR = {
	code: '23514',
	message: 'new row for relation "runs" violates check constraint "runs_distance_check"',
	details: 'Failing row contains (uuid, left knee ITB flare, 51.5074, -0.1278).',
	hint: 'runner@example.com',
};

test('dbError turns a PostgREST result error into an Error carrying only message + code', () => {
	// Reason: postgrest-js returns `error` as the parsed JSON body, a plain
	// object. Thrown raw, Sentry recorded "Object captured as exception" with no
	// stack and `instanceof Error` was false at every catch site.
	const e = dbError(PII_ERROR);
	assert.ok(e instanceof Error);
	assert.ok(e instanceof DbError);
	assert.equal(e.name, 'DbError');
	assert.equal(e.message, 'new row for relation "runs" violates check constraint "runs_distance_check" (23514)');
	assert.equal((e as DbError).code, '23514');
	assert.equal(typeof e.stack, 'string');
	assert.doesNotMatch(e.stack!.split('\n')[1] ?? '', /dbError/, 'the helper frame is trimmed from the stack');
});

test('dbError keeps details and hint out of the message, the keys and the serialised form', () => {
	// Reason: `details` / `hint` can echo the offending row — injury free text,
	// coordinates, an email — and a thrown error reaches console.error,
	// CloudWatch and Sentry. Nothing of them may survive the conversion, and no
	// `cause` either: Node prints a cause even when it is non-enumerable.
	const e = dbError(PII_ERROR);
	for (const surface of [e.message, JSON.stringify(e), Object.keys(e).join(','), e.stack ?? '', inspect(e)]) {
		assert.doesNotMatch(surface, /ITB flare|51\.5074|runner@example\.com|details|hint/);
	}
	assert.equal('cause' in e, false);
	assert.deepEqual(Object.keys(e).sort(), ['code', 'name', 'status']);
});

test('dbError keeps the code every caught-error branch reads', () => {
	assert.equal(isDuplicateKeyError(dbError({ code: '23505', message: 'duplicate key' })), true);
	assert.equal((dbError({ code: 'PGRST116', message: 'no rows' }) as DbError).code, 'PGRST116');
	assert.equal((dbError({ code: '42501', message: 'denied' }) as DbError).code, '42501');
	assert.equal((dbError({ message: 'Bad Gateway', status: 502 }) as DbError).status, 502);
	assert.equal((dbError({ message: 'FetchError: offline', code: '' }) as DbError).code, undefined);
	assert.equal(dbError({ message: 'FetchError: offline', code: '' }).message, 'FetchError: offline');
	assert.equal(dbError({ code: '42501' }).message, '(42501)');
});

test('dbError passes a real Error through and rebuilds a PostgrestError', () => {
	// Reason: auth-js / storage-js / functions-js already throw Error subclasses
	// with their own stack, and a FunctionsHttpError's `context` (the Response)
	// is read by callers — rebuilding would drop it. postgrest-js's own
	// PostgrestError is an Error too, but its toJSON serialises details + hint.
	const functionsErr = Object.assign(new Error('Edge Function returned a non-2xx status code'), {
		name: 'FunctionsHttpError',
		context: { status: 409 },
	});
	assert.equal(dbError(functionsErr), functionsErr);
	const already = new DbError('x', '42501');
	assert.equal(dbError(already), already);
	class PostgrestError extends Error {
		details = PII_ERROR.details;
		hint = PII_ERROR.hint;
		code = PII_ERROR.code;
		constructor(m: string) {
			super(m);
			this.name = 'PostgrestError';
		}
		toJSON() {
			return { message: this.message, details: this.details, hint: this.hint, code: this.code };
		}
	}
	const rebuilt = dbError(new PostgrestError('violates check'));
	assert.ok(rebuilt instanceof DbError);
	assert.equal((rebuilt as DbError).code, '23514');
	assert.doesNotMatch(JSON.stringify(rebuilt), /ITB flare|runner@example/);
});

test('dbError tolerates a string or a shapeless value', () => {
	assert.equal(dbError('upstream refused').message, 'upstream refused');
	assert.equal(dbError({ foo: 1 }).message, '');
	assert.ok(dbError(null) instanceof DbError);
});

test('thrownMessage formats a DbError exactly as it formatted the raw object', () => {
	// Reason: § 1914 made every surface read a caught value through
	// thrownMessage, which appended the code to a raw object's message. A
	// DbError's message already carries it, so the text a reader sees is
	// unchanged by the switch.
	assert.equal(thrownMessage(dbError(PII_ERROR)), thrownMessage(PII_ERROR));
	assert.equal(thrownMessage(dbError({ message: 'timeout', code: '' })), 'timeout');
	assert.equal(thrownMessage(dbError({ foo: 1 })), '');
});

test('appErrorMessage reads an app-raised Error and leaves a database failure to the surface copy', () => {
	// Reason: `e instanceof Error ? e.message : m('copy')` used to send a failed
	// query (a plain object) to the localised copy. A DbError is an Error, so
	// that idiom would now print "invalid invite token (P0001)" where the page
	// said "This invite link is invalid or expired". The helper keeps the old
	// split: the app's own machine codes still read through, a DbError does not.
	assert.equal(appErrorMessage(new Error('event_full')), 'event_full');
	assert.equal(appErrorMessage(Object.assign(new Error('Edge Function returned a non-2xx status code'), { name: 'FunctionsHttpError' })), 'Edge Function returned a non-2xx status code');
	assert.equal(appErrorMessage(dbError({ code: 'P0001', message: 'invalid invite token' })), null);
	assert.equal(appErrorMessage({ message: 'invalid invite token', code: 'P0001' }), null);
	assert.equal(appErrorMessage('x'), null);
	assert.equal(appErrorMessage(undefined), null);
});

test('dbError turns a 23P01 plan-window overlap into a readable PlanOverlapError', () => {
	// Reason: training_plans_active_no_overlap is the schema's one exclusion
	// constraint; a shift or re-plan that trips it otherwise toasts a raw
	// constraint name and code (decisions § 2008).
	const err = dbError({
		message: 'conflicting key value violates exclusion constraint "training_plans_active_no_overlap"',
		code: '23P01',
		details: 'Key (user_id, daterange(...))',
		hint: null
	});
	assert.ok(err instanceof PlanOverlapError);
	assert.ok(err instanceof DbError);
	assert.equal((err as DbError).code, '23P01');
	assert.match(err.message, /overlap another active training plan/);
	assert.doesNotMatch(err.message, /23P01|exclusion|Key \(/);
	assert.equal(thrownMessage(err), err.message);
	assert.equal(appErrorMessage(err), err.message);
	assert.equal(isPlanOverlapError(err), true);
	assert.equal(isPlanOverlapError({ code: '23505' }), false);
});

test('a restart refused over a race ahead keeps its own SQLSTATE', () => {
	const err = dbError({ message: 'restart_training_plan: this plan has a race still ahead', code: 'RR001' });
	assert.ok(err instanceof DbError);
	assert.equal(isPlanRestartRaceAheadError(err), true);
	assert.equal(isPlanOverlapError(err), false);
	assert.equal(isPlanRestartRaceAheadError({ code: 'TR001' }), false);
});

test('a refused trim keeps its own SQLSTATE and is not an overlap', () => {
	const err = dbError({ message: 'trim_training_plan: completed workouts fall after 2031-04-11', code: 'TR001' });
	assert.ok(err instanceof DbError);
	assert.ok(!(err instanceof PlanOverlapError));
	assert.equal(isPlanTrimBlockedError(err), true);
	assert.equal(isPlanOverlapError(err), false);
	assert.equal(isPlanTrimBlockedError({ code: '23P01' }), false);
});

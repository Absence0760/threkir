import { test } from 'node:test';
import assert from 'node:assert/strict';
import { errorCopy, errorCopyKey } from './error_copy';
import { DbError, PlanOverlapError } from '../core/supabase_error';
import { AppError } from '../core/app_error';
import { interpolate } from './interpolate';
import { SUPPORTED_LOCALES } from './locale';
import { CATALOGUE_LOADERS } from './catalogues';
import type { MessageKey } from './messages';

const quiet = () => {
	const original = console.error;
	const logged: unknown[][] = [];
	console.error = (...args: unknown[]) => void logged.push(args);
	return { logged, restore: () => (console.error = original) };
};

async function english() {
	const en = (await CATALOGUE_LOADERS.en()) as Record<string, string>;
	const t = (key: MessageKey, params?: Record<string, string | number>) =>
		interpolate(en[key], params ?? {});
	return { en, t };
}

test('known failures map to their own catalogue copy', () => {
	assert.equal(errorCopyKey(new TypeError('Failed to fetch')), 'errorCopy.offline');
	assert.equal(
		errorCopyKey(new TypeError('NetworkError when attempting to fetch resource.')),
		'errorCopy.offline',
	);
	assert.equal(errorCopyKey(new DOMException('signal timed out', 'TimeoutError')), 'errorCopy.timeout');
	assert.equal(errorCopyKey(new Error('Not signed in')), 'errorCopy.signedOut');
	assert.equal(errorCopyKey(new DbError('JWT expired', 'PGRST301', 401)), 'errorCopy.signedOut');
	assert.equal(
		errorCopyKey(new DbError('permission denied for table training_plans', '42501')),
		'errorCopy.forbidden',
	);
	assert.equal(errorCopyKey(new Error('Only the plan owner can publish')), 'errorCopy.forbidden');
	assert.equal(errorCopyKey(new DbError('duplicate key value', '23505')), 'errorCopy.duplicate');
	assert.equal(
		errorCopyKey(new DbError('JSON object requested, multiple (or no) rows returned', 'PGRST116')),
		'errorCopy.notFound',
	);
	assert.equal(
		errorCopyKey(new DbError('new row for relation "plan_workouts" violates check constraint', '23514')),
		'errorCopy.invalid',
	);
	assert.equal(errorCopyKey(new PlanOverlapError()), 'planDetail.planOverlap');
	assert.equal(errorCopyKey(new DbError('something odd', 'XX000')), 'errorCopy.generic');
	assert.equal(
		errorCopyKey({ name: 'AuthApiError', message: 'Email rate limit exceeded', status: 429, code: 'over_email_send_rate_limit' }),
		'errorCopy.tooManyRequests',
	);
	// The Edge Functions' shared limiter code, rethrown with no status.
	assert.equal(errorCopyKey(new Error('rate_limit_exceeded')), 'errorCopy.tooManyRequests');
	assert.equal(errorCopyKey({ code: 'rate_limit_exceeded' }), 'errorCopy.tooManyRequests');
	assert.equal(
		errorCopyKey({ message: 'For security purposes, you can only request this after 42 seconds.' }),
		'errorCopy.tooManyRequests',
	);
	assert.equal(
		errorCopyKey({ message: 'New password should be different from the old password.', status: 422, code: 'same_password' }),
		'errorCopy.samePassword',
	);
	assert.equal(errorCopyKey({ message: 'Password is known to be weak', code: 'weak_password' }), 'errorCopy.weakPassword');
	assert.equal(
		errorCopyKey({ message: 'A user with this email address has already been registered', code: 'email_exists' }),
		'errorCopy.emailTaken',
	);
	assert.equal(errorCopyKey({}), 'errorCopy.generic');
	assert.equal(errorCopyKey(null), 'errorCopy.generic');
});

test('a database code decides; a word in its message does not', () => {
	// Each message names a different category than its code does.
	assert.equal(
		errorCopyKey(new DbError('create_training_plan: race listing not found', '22023')),
		'errorCopy.invalid',
	);
	assert.equal(
		errorCopyKey(new DbError('duplicate key value violates unique constraint "rate limit buckets_pkey"', '23505')),
		'errorCopy.duplicate',
	);
	assert.equal(
		errorCopyKey(new DbError('new row violates check constraint "session timed out flag"', '23514')),
		'errorCopy.invalid',
	);
	assert.equal(
		errorCopyKey(new DbError('permission denied: plan not found for caller', '42501')),
		'errorCopy.forbidden',
	);
	assert.equal(errorCopyKey(new DbError('jwt expired somewhere in a hint', 'XX000')), 'errorCopy.generic');
});

test('a message is still read when there is no code, or only the bare-raise P0001', () => {
	assert.equal(errorCopyKey(new DbError('clone_plan_template: template not found', 'P0001')), 'errorCopy.notFound');
	assert.equal(errorCopyKey(new Error('request timed out')), 'errorCopy.timeout');
	assert.equal(errorCopyKey({ message: 'Email rate limit exceeded' }), 'errorCopy.tooManyRequests');
	// The RPCs' signed-out guard keeps its meaning under its 42501.
	assert.equal(errorCopyKey(new DbError('not authenticated', '42501')), 'errorCopy.signedOut');
});

test('codes that name a category without a message are mapped', () => {
	assert.equal(errorCopyKey(new DbError('canceling statement due to statement timeout', '57014')), 'errorCopy.timeout');
	assert.equal(errorCopyKey(new DbError('JWT expired', 'PGRST303', 401)), 'errorCopy.signedOut');
	assert.equal(errorCopyKey(new DbError('query returned no rows', 'P0002')), 'errorCopy.notFound');
});

test('a five-character code that is not a SQLSTATE still has its message read', () => {
	// Node's errno for a socket closed mid-write, and a lower-case word: both
	// passed the old bare five-character test and were filed as generic.
	assert.equal(errorCopyKey({ code: 'EPIPE', message: 'request timed out' }), 'errorCopy.timeout');
	assert.equal(errorCopyKey({ code: 'stale', message: 'session not found' }), 'errorCopy.notFound');
	// A SQLSTATE in lower case is still one.
	assert.equal(errorCopyKey({ code: '23514', message: 'row not found' }), 'errorCopy.invalid');
	assert.equal(errorCopyKey({ code: 'pgrst116', message: 'request timed out' }), 'errorCopy.generic');
});

test('the raw text reaches the console and never the copy', async () => {
	const { en, t } = await english();
	const raw =
		'new row for relation "plan_workouts" violates check constraint "plan_workouts_kind_check"';
	const log = quiet();
	try {
		const copy = errorCopy(new DbError(raw, '23514'), t, 'saving a workout failed');
		assert.equal(copy, en['errorCopy.invalid']);
		assert.ok(!copy.includes('violates'));
		assert.equal(log.logged.length, 1);
		assert.equal(log.logged[0][0], 'saving a workout failed');
		assert.match(JSON.stringify(log.logged[0][1]), /violates check constraint/);
		assert.doesNotMatch(JSON.stringify(log.logged[0][1]), /plan_workouts_kind_check/);
		assert.match(JSON.stringify(log.logged[0][1]), /23514/);
	} finally {
		log.restore();
	}
});

test('a rate-limit refusal keeps its own sentence', async () => {
	const { en, t } = await english();
	const log = quiet();
	try {
		const copy = errorCopy(
			new DbError('rate limit exceeded for clone_public_plan, retry in 30s', 'P0001'),
			t,
		);
		assert.notEqual(copy, en['errorCopy.generic']);
		assert.ok(!copy.includes('rate limit exceeded'));
	} finally {
		log.restore();
	}
});

test('a fallback key replaces only the generic line', async () => {
	const { en, t } = await english();
	const log = quiet();
	try {
		assert.equal(
			errorCopy(new DbError('something odd', 'XX000'), t, 'ctx', 'settingsAccount.passwordUpdateFailed'),
			en['settingsAccount.passwordUpdateFailed'],
		);
		assert.equal(
			errorCopy(new TypeError('Failed to fetch'), t, 'ctx', 'settingsAccount.passwordUpdateFailed'),
			en['errorCopy.offline'],
		);
	} finally {
		log.restore();
	}
});

test('an AppError renders its own key and params, and its message stays in the log', async () => {
	// Reason: `appErrorMessage(e) ?? m('copy')` showed an app-raised Error's
	// text as it was, so a specific failure could only be specific in English.
	// An AppError carries the catalogue key instead.
	const { en, t } = await english();
	const log = quiet();
	try {
		const err = new AppError('errorCopy.imageTooLarge', {
			params: { mb: 10 },
			message: 'Image too large (10 MB max)',
		});
		assert.equal(errorCopyKey(err), 'errorCopy.imageTooLarge');
		const copy = errorCopy(err, t, 'photo upload failed', 'clubEvent.photoUploadFailed');
		assert.equal(copy, interpolate(en['errorCopy.imageTooLarge'], { mb: 10 }));
		assert.match(copy, /10 MB/);
		assert.doesNotMatch(copy, /max\)/);
		assert.match(JSON.stringify(log.logged), /Image too large/);
		assert.equal(new AppError('importRoute.kmzNoKml').message, 'importRoute.kmzNoKml');
	} finally {
		log.restore();
	}
});

test('an app-raised sentence or a fetch failure never reaches the copy as text', async () => {
	// Reason: the follow-up this closes — `appErrorMessage(e) ?? m(...)` showed
	// "TypeError: Failed to fetch" and the data layer's English to the reader.
	const { en, t } = await english();
	const log = quiet();
	try {
		const fallback = 'reportDialog.errorSubmitFailed' as const;
		assert.equal(
			errorCopy(new Error('You already have a pending report against this content.'), t, 'ctx', fallback),
			en[fallback],
		);
		assert.equal(errorCopy(new Error('event_full'), t, 'ctx', fallback), en[fallback]);
		assert.equal(errorCopy(new TypeError('Failed to fetch'), t, 'ctx', fallback), en['errorCopy.offline']);
		assert.equal(errorCopy(new TypeError('Load failed'), t, 'ctx', fallback), en['errorCopy.offline']);
		const relay = Object.assign(new Error('Failed to send a request to the Edge Function'), {
			name: 'FunctionsFetchError',
		});
		assert.equal(errorCopyKey(relay), 'errorCopy.offline');
		// A bug in our own code is not a network failure.
		assert.equal(
			errorCopy(new TypeError("Cannot read properties of undefined (reading 'id')"), t, 'ctx', fallback),
			en[fallback],
		);
	} finally {
		log.restore();
	}
});

test('every errorCopy key is translated in every locale', async () => {
	const keys = [
		'errorCopy.offline',
		'errorCopy.timeout',
		'errorCopy.signedOut',
		'errorCopy.forbidden',
		'errorCopy.invalid',
		'errorCopy.notFound',
		'errorCopy.duplicate',
		'errorCopy.tooManyRequests',
		'errorCopy.samePassword',
		'errorCopy.weakPassword',
		'errorCopy.emailTaken',
		'errorCopy.generic',
		'errorCopy.imageTooLarge',
		'errorCopy.imageType',
		'importRoute.unsupportedFormat',
		'importRoute.noRouteInFile',
		'importRoute.kmzNoKml',
		'reportDialog.errorAlreadyPending',
	];
	const { en } = await english();
	for (const locale of SUPPORTED_LOCALES) {
		const cat = (await CATALOGUE_LOADERS[locale]()) as Record<string, string>;
		for (const key of keys) {
			assert.ok(cat[key], `${locale} is missing ${key}`);
			if (locale !== 'en') assert.notEqual(cat[key], en[key], `${locale} ${key} is still English`);
		}
	}
});

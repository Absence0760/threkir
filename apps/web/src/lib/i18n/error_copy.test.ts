import { test } from 'node:test';
import assert from 'node:assert/strict';
import { errorCopy, errorCopyKey } from './error_copy';
import { DbError, PlanOverlapError } from '../core/supabase_error';
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
	assert.equal(errorCopyKey({}), 'errorCopy.generic');
	assert.equal(errorCopyKey(null), 'errorCopy.generic');
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

test('every errorCopy key is translated in every locale', async () => {
	const keys = [
		'errorCopy.offline',
		'errorCopy.timeout',
		'errorCopy.signedOut',
		'errorCopy.forbidden',
		'errorCopy.invalid',
		'errorCopy.notFound',
		'errorCopy.duplicate',
		'errorCopy.generic',
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

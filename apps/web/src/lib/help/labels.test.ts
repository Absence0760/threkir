// `npx tsx --test src/lib/help/labels.test.ts`
//
// tsc already makes each map exhaustive and each value a MessageKey. What it
// cannot see is two values sharing a label, which would make two help filter
// chips read the same, so that is checked here against the English catalogue.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { en } from '../i18n/locales/en';
import {
	AUDIENCE_LABEL,
	CATEGORY_LABEL,
	KIND_LABEL,
	PLATFORM_LABEL,
	REQUIREMENT_LABEL,
} from './labels';

const MAPS = {
	CATEGORY_LABEL,
	KIND_LABEL,
	AUDIENCE_LABEL,
	PLATFORM_LABEL,
	REQUIREMENT_LABEL,
} as const;

test('every map names a distinct catalogue key per value', () => {
	for (const [name, map] of Object.entries(MAPS)) {
		const keys = Object.values(map);
		assert.equal(new Set(keys).size, keys.length, `${name} reuses a key`);
	}
});

test('every key has non-empty English text, distinct within its map', () => {
	const catalogue = en as Record<string, string>;
	for (const [name, map] of Object.entries(MAPS)) {
		const texts = Object.values(map).map((k) => catalogue[k]);
		for (const [i, t] of texts.entries()) {
			assert.ok(t && t.trim().length > 0, `${name}: ${Object.values(map)[i]} is empty`);
		}
		assert.equal(new Set(texts).size, texts.length, `${name}: two values read the same in English`);
	}
});

test('every key lives in the help namespace', () => {
	for (const [name, map] of Object.entries(MAPS)) {
		for (const k of Object.values(map)) assert.match(k, /^help\./, `${name}: ${k}`);
	}
});

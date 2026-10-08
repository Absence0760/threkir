// The loader table the i18n plugin serves (decisions § 1802, § 1812).
// Invocation: npx tsx --test src/lib/i18n/vite_plugin.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { AREA_NAMES } from './areas';
import type { Part } from './area_scan';
import { SUPPORTED_LOCALES } from './locale';
import { loadersModule, partId, partNames } from './vite_plugin';

const groups = { '_history~gym': ['/gym', '/history'], _sessions: ['/sessions'] };

test('the loader table serves the derived groups and a loader for every area and group', () => {
	const source = loadersModule({ groups });
	assert.ok(source.includes(`export const GROUPS = ${JSON.stringify(groups)};`));
	for (const locale of SUPPORTED_LOCALES) {
		for (const part of [...AREA_NAMES, ...Object.keys(groups)]) {
			assert.ok(
				source.includes(`import(${JSON.stringify(partId(locale, part as Part))})`),
				`no loader for ${locale}/${part}`,
			);
		}
	}
});

test('a part id never nests: every part name is one path segment', () => {
	// The bundle budget reads `virtual:i18n-catalogue/<tag>/<part>` with one
	// segment per field, so a group name containing `/` would be invisible.
	for (const part of partNames({ groups })) assert.ok(!part.includes('/'), part);
});

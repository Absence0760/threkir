// The loader table the i18n plugin serves (decisions § 1802, § 1812).
// Invocation: npx tsx --test src/lib/i18n/vite_plugin.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { AREA_NAMES } from './areas';
import type { Part } from './area_scan';
import { SUPPORTED_LOCALES } from './locale';
import { codeLiteral, loadersModule, partId, partNames } from './vite_plugin';

const groups = { '_history~gym': ['/gym', '/history'], _sessions: ['/sessions'] };

test('the loader table serves the derived groups and a loader for every area and group', () => {
	const source = loadersModule({ groups });
	const table = source.slice(source.indexOf('export const GROUPS = {'));
	const served = table.slice(table.indexOf('{'), table.indexOf('};') + 1).replaceAll("'", '"').replace(/,(\s*[\]}])/g, '$1');
	assert.deepEqual(JSON.parse(served), groups);
	for (const locale of SUPPORTED_LOCALES) {
		for (const part of [...AREA_NAMES, ...Object.keys(groups)]) {
			assert.ok(
				source.includes(`import('${partId(locale, part as Part)}')`),
				`no loader for ${locale}/${part}`,
			);
		}
	}
});

test('nothing outside the route-name character set reaches the generated module', () => {
	// The module is code, so an embedded value is refused rather than escaped
	// (CodeQL js/improper-code-sanitization on the JSON.stringify form).
	assert.equal(codeLiteral('virtual:i18n-catalogue/pt-BR/_history~gym'), "'virtual:i18n-catalogue/pt-BR/_history~gym'");
	assert.equal(codeLiteral('/runs/[id]'), "'/runs/[id]'");
	for (const bad of ["a'b", 'a"b', 'a\nb', 'a\u2028b', 'a b', '</script>', '${x}', '']) {
		assert.throws(() => codeLiteral(bad), /refusing to embed/, JSON.stringify(bad));
	}
	assert.throws(() => loadersModule({ groups: { "_x'y": ['/x'] } }), /refusing to embed/);
	assert.throws(() => loadersModule({ groups: { _x: ['/x\n'] } }), /refusing to embed/);
});

test('a part id never nests: every part name is one path segment', () => {
	// The bundle budget reads `virtual:i18n-catalogue/<tag>/<part>` with one
	// segment per field, so a group name containing `/` would be invisible.
	for (const part of partNames({ groups })) assert.ok(!part.includes('/'), part);
});

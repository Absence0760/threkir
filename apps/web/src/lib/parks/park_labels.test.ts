import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { CATALOGUE_LOADERS } from '../i18n/catalogues.ts';
import { SUPPORTED_LOCALES } from '../i18n/locale.ts';
import type { MessageKey } from '../i18n/messages.ts';
import {
	AGENCY_LABEL,
	ATTRIBUTION_LABEL,
	DIFFICULTY_LABEL,
	SHAPE_LABEL,
	STATUS_LABEL,
	courseCredit,
	labelKey,
} from './park_labels.ts';
import {
	COURSE_DIFFICULTIES,
	COURSE_SHAPES,
	COURSE_STATUSES,
	GEOMETRY_SOURCES,
	PARK_AGENCIES,
} from './park_courses.ts';

// Each map against the vocabulary it labels. The vocabularies are the client
// rails check_constraint_unions.mjs pins to the CHECKs on parks.agency and
// park_courses.{course_shape,status,difficulty,geometry_source}, so a value
// the column gains reaches this test through that guard.
const TABLES: readonly { name: string; table: Record<string, MessageKey>; values: readonly string[] }[] = [
	{ name: 'AGENCY_LABEL', table: AGENCY_LABEL, values: PARK_AGENCIES },
	{ name: 'SHAPE_LABEL', table: SHAPE_LABEL, values: COURSE_SHAPES },
	{ name: 'STATUS_LABEL', table: STATUS_LABEL, values: COURSE_STATUSES },
	{ name: 'DIFFICULTY_LABEL', table: DIFFICULTY_LABEL, values: COURSE_DIFFICULTIES },
	{ name: 'ATTRIBUTION_LABEL', table: ATTRIBUTION_LABEL, values: GEOMETRY_SOURCES },
];

test('each label map covers exactly the values its column allows', () => {
	for (const { name, table, values } of TABLES) {
		assert.deepEqual(Object.keys(table).sort(), [...values].sort(), name);
	}
});

test('no two values of one map share a label key', () => {
	for (const { name, table } of TABLES) {
		const keys = Object.values(table);
		assert.equal(new Set(keys).size, keys.length, name);
	}
});

test('every label key is a non-empty string in every locale', async () => {
	for (const loc of SUPPORTED_LOCALES) {
		const dict = (await CATALOGUE_LOADERS[loc]()) as Record<string, string>;
		for (const { name, table } of TABLES) {
			for (const [value, key] of Object.entries(table)) {
				const text = dict[key];
				assert.equal(typeof text, 'string', `${loc}: ${name}.${value} -> ${key} is missing`);
				assert.ok(text.trim().length > 0, `${loc}: ${name}.${value} -> ${key} is empty`);
				assert.doesNotMatch(text, /[{}]/, `${loc}: ${key} takes a placeholder the map cannot fill`);
			}
		}
	}
});

test('labelKey: a stored value maps to its key', () => {
	assert.equal(labelKey(SHAPE_LABEL, 'out_and_back'), 'parks.shapeOutAndBack');
	assert.equal(labelKey(AGENCY_LABEL, 'nps'), 'parks.agencyNps');
	assert.equal(labelKey(STATUS_LABEL, 'seasonal'), 'parks.statusSeasonal');
});

test('labelKey: a value outside the vocabulary, or none, is null', () => {
	assert.equal(labelKey(SHAPE_LABEL, 'spiral'), null);
	assert.equal(labelKey(SHAPE_LABEL, null), null);
	assert.equal(labelKey(SHAPE_LABEL, undefined), null);
	assert.equal(labelKey(SHAPE_LABEL, ''), null);
	assert.equal(labelKey(DIFFICULTY_LABEL, 'toString'), null);
	assert.equal(labelKey(DIFFICULTY_LABEL, '__proto__'), null);
});

test('courseCredit: the course text wins, else the source label, else nothing', () => {
	assert.deepEqual(courseCredit('  Fairfax County Park Authority ', 'osm'), { text: 'Fairfax County Park Authority' });
	assert.deepEqual(courseCredit('   ', 'osm'), { key: 'parks.attributionOsm' });
	assert.deepEqual(courseCredit(null, 'traced'), { key: 'parks.attributionTraced' });
	assert.equal(courseCredit(null, 'gpsies'), null);
	assert.equal(courseCredit(undefined, null), null);
});

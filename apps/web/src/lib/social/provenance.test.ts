import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
	PROVENANCE_KINDS,
	contentProvenance,
	provenanceShowsBadge,
	raceCourseProvenance,
	raceListingProvenance,
	type Provenance,
} from './provenance.ts';

// The TS reader of fixtures/provenance_cases.json, the case table the
// provenance pair shares with apps/mobile_android/test/provenance_test.dart.

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', '..', '..');
const fixture = JSON.parse(
	readFileSync(join(REPO, 'fixtures', 'provenance_cases.json'), 'utf-8'),
) as Record<string, unknown>;

const SECTIONS = ['content', 'listing', 'course', 'badge'];
const META = new Set(['spec', 'reference', 'readers', 'schema', 'kinds']);

type Case = Record<string, unknown>;
const section = (name: string) => fixture[name] as Case[];

test('the fixture has no section this reader does not run', () => {
	const unknown = Object.keys(fixture).filter((k) => !META.has(k) && !SECTIONS.includes(k));
	assert.deepEqual(unknown, []);
	for (const s of SECTIONS) assert.ok(section(s).length > 0, `${s} has cases`);
});

test('the kinds list matches the fixture', () => {
	assert.deepEqual([...PROVENANCE_KINDS], fixture.kinds);
});

test('content provenance', () => {
	for (const c of section('content')) {
		assert.equal(contentProvenance(c.isOfficial as boolean | null), c.out, JSON.stringify(c));
	}
});

test('race listing provenance', () => {
	for (const c of section('listing')) {
		const got = raceListingProvenance({
			organiserIsOfficial: c.organiserIsOfficial as boolean | null,
			provider: c.provider as string | null,
			isVerified: c.isVerified as boolean | null,
		});
		assert.equal(got, c.out, JSON.stringify(c));
	}
});

test('race course provenance', () => {
	for (const c of section('course')) {
		const got = raceCourseProvenance({
			hasCourse: c.hasCourse as boolean,
			organiserIsOfficial: c.organiserIsOfficial as boolean | null,
			courseSource: c.courseSource as string | null,
		});
		assert.equal(got, c.out, JSON.stringify(c));
	}
});

test('which provenance shows a badge', () => {
	for (const c of section('badge')) {
		assert.equal(provenanceShowsBadge(c.kind as Provenance), c.out, JSON.stringify(c));
	}
});

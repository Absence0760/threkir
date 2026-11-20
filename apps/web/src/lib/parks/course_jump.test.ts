import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { COURSE_JUMP_MIN_SPAN_M, courseJumps, type CourseJump } from './course_jump';
import { planeXY } from '../races/course_gates';
import type { Gate } from '../geo/gate_crossing';

// The TS reader of fixtures/course_jump_cases.json, the case table the Dart
// twin (apps/mobile_android/test/course_jump_test.dart) reads too.
const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', '..', '..');
const { cases } = JSON.parse(readFileSync(join(REPO, 'fixtures', 'course_jump_cases.json'), 'utf-8')) as {
	cases: {
		name: string;
		gates: { start: Gate; finish: Gate } | null;
		line: { lat: number | null; lng: number }[];
		endsShared: boolean;
		jumps: CourseJump[];
	}[];
};

const input = (c: (typeof cases)[number]) => ({
	gates: c.gates,
	line: c.line.map((p) => ({ lat: p.lat ?? NaN, lng: p.lng })),
	endsShared: c.endsShared,
});

for (const c of cases) {
	test(c.name, () => {
		const got = courseJumps(input(c));
		assert.deepEqual(
			got.map((j) => j.target),
			c.jumps.map((j) => j.target),
		);
		got.forEach((j, i) => {
			for (const k of ['south', 'west', 'north', 'east'] as const) {
				assert.ok(Math.abs(j.bounds[k] - c.jumps[i].bounds[k]) < 1e-9, `${j.target}.${k}`);
			}
		});
	});
}

test('every start or finish jump shows at least the least span each way', () => {
	for (const c of cases) {
		for (const j of courseJumps(input(c))) {
			if (j.target === 'course') continue;
			const { x, y } = planeXY({ lat: j.bounds.south, lng: j.bounds.west }, { lat: j.bounds.north, lng: j.bounds.east });
			assert.ok(x >= COURSE_JUMP_MIN_SPAN_M - 0.5, `${c.name}: ${x} across`);
			assert.ok(y >= COURSE_JUMP_MIN_SPAN_M - 0.5, `${c.name}: ${y} along`);
		}
	}
});

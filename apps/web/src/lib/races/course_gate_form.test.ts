import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { COURSE_GATE_DEFAULT_HALF_WIDTH_M, courseGate, type CourseGateColumns } from './course_gates.ts';
import { gateFormSeed, sameGate, shouldReseed, widthFromEntry, type GateFormSync } from './course_gate_form.ts';

function row(finish: { lat: number; lng: number; bearing: number; width: number } | null): CourseGateColumns {
	return {
		start_gate_lat: null,
		start_gate_lng: null,
		start_gate_bearing_deg: null,
		start_gate_half_width_m: null,
		start_gate_source: null,
		finish_gate_lat: finish?.lat ?? null,
		finish_gate_lng: finish?.lng ?? null,
		finish_gate_bearing_deg: finish?.bearing ?? null,
		finish_gate_half_width_m: finish?.width ?? null,
		finish_gate_source: finish ? 'organiser' : null
	};
}

const placed = { lat: 37.5407, lng: -77.436, bearing: 0, width: 20 };

test('a refetched row with the same values is the same line', () => {
	const a = courseGate(row(placed), 'finish');
	const b = courseGate(row(placed), 'finish');
	assert.notEqual(a, b);
	assert.ok(sameGate(a, b));
	assert.ok(!sameGate(a, courseGate(row({ ...placed, bearing: 90 }), 'finish')));
	assert.ok(!sameGate(a, null));
	assert.ok(sameGate(null, null));
});

test('a refresh of unchanged lines mid-edit keeps what was typed', () => {
	// The CI failure in #1358: a second load of the same row arrived after
	// the organiser typed a new bearing, and the form took the server's 0.
	const seeded = courseGate(row(placed), 'finish');
	const sync: GateFormSync = { which: 'finish', seededFrom: seeded, dirty: true };
	assert.equal(shouldReseed(sync, 'finish', courseGate(row(placed), 'finish')), false);
	// Clean form, same values: nothing to take either.
	assert.equal(shouldReseed({ ...sync, dirty: false }, 'finish', courseGate(row(placed), 'finish')), false);
});

test('a moved line never replaces unapplied edits, and replaces a clean form', () => {
	const seeded = courseGate(row(placed), 'finish');
	const moved = courseGate(row({ ...placed, lat: 37.6 }), 'finish');
	assert.equal(shouldReseed({ which: 'finish', seededFrom: seeded, dirty: true }, 'finish', moved), false);
	assert.equal(shouldReseed({ which: 'finish', seededFrom: seeded, dirty: false }, 'finish', moved), true);
});

test('a late first load does not reopen a form being typed into', () => {
	// Place opened the inputs empty (seeded from no line); the first load then
	// lands with the line still absent.
	const sync: GateFormSync = { which: 'finish', seededFrom: null, dirty: true };
	assert.equal(shouldReseed(sync, 'finish', courseGate(row(null), 'finish')), false);
});

test('switching lines always takes the other line, edits or not', () => {
	const seeded = courseGate(row(placed), 'finish');
	assert.equal(shouldReseed({ which: 'finish', seededFrom: seeded, dirty: true }, 'start', null), true);
	assert.equal(shouldReseed({ which: null, seededFrom: null, dirty: false }, 'finish', null), true);
});

test('a cleared or half-typed width keeps the last valid one', () => {
	assert.equal(widthFromEntry(null, 20), 20);
	assert.equal(widthFromEntry(undefined, 20), 20);
	assert.equal(widthFromEntry(Number.NaN, 20), 20);
	assert.equal(widthFromEntry(30, 20), 30);
	assert.equal(widthFromEntry(0, 20), 0, 'out of range is clamped at save, not here');
});

test('the seed rounds for the inputs and defaults the width when there is no line', () => {
	assert.deepEqual(gateFormSeed(null), {
		lat: null,
		lng: null,
		bearingDeg: null,
		halfWidthM: COURSE_GATE_DEFAULT_HALF_WIDTH_M
	});
	const g = courseGate(row({ lat: 37.12345678, lng: -77.98765432, bearing: 90.04, width: 25 }), 'finish');
	assert.deepEqual(gateFormSeed(g), { lat: 37.123457, lng: -77.987654, bearingDeg: 90, halfWidthM: 25 });
});

// Source-level: the reseed and the width pair live in a `$effect` and two
// bindings that a DOM-free test cannot drive, so pin that the component goes
// through the helpers above rather than re-seeding on every new `lines`.
const editor = readFileSync(new URL('../components/CourseGateEditor.svelte', import.meta.url), 'utf8');

test('CourseGateEditor re-seeds through shouldReseed and marks typing dirty', () => {
	const effect = editor.slice(editor.indexOf('$effect(() => {\n\t\tconst g = edited;'));
	assert.ok(effect.length > 0, 'reseed effect not found — renamed?');
	assert.match(effect.slice(0, 300), /shouldReseed\(sync, which, g\)/);
	assert.match(editor, /oninput=\{onFormInput\}/);
});

test('neither width input binds formWidth directly', () => {
	assert.doesNotMatch(editor, /bind:value=\{formWidth\}/);
	assert.match(editor, /widthFromEntry\(v, formWidth\)/);
});

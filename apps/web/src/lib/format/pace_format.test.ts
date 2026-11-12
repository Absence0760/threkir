import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	paceFieldFromSecPerKm,
	paceMinutesSeconds,
	paceParts,
	isMeaningfulPace,
	paceToleranceFromUnit,
	paceToleranceLabel,
	paceToleranceToUnit,
	secPerKmFromPaceField
} from './pace_format';

test('formats whole and exact paces', () => {
	assert.equal(paceMinutesSeconds(330), '5:30');
	assert.equal(paceMinutesSeconds(305), '5:05');
	assert.equal(paceMinutesSeconds(0), '0:00');
	assert.equal(paceMinutesSeconds(59), '0:59');
	assert.equal(paceMinutesSeconds(60), '1:00');
});

test('never emits a ":60" seconds field for a fractional input', () => {
	// The bug this guards: independent floor(min) + round(sec) produced
	// "4:60" for 299.6 instead of rolling over to "5:00".
	assert.equal(paceMinutesSeconds(299.6), '5:00');
	assert.equal(paceMinutesSeconds(359.7), '6:00');
	assert.equal(paceMinutesSeconds(119.6), '2:00');
	for (const x of [59.5, 119.6, 179.8, 299.6, 359.7, 599.9]) {
		const out = paceMinutesSeconds(x);
		assert.ok(!/:60$/.test(out), `${x} produced malformed ${out}`);
	}
});

test('rounds to the nearest whole second', () => {
	assert.equal(paceMinutesSeconds(330.4), '5:30');
	assert.equal(paceMinutesSeconds(330.5), '5:31');
});

test('isMeaningfulPace gates non-physical duration/distance', () => {
	// Both strictly positive + finite is the only meaningful case.
	assert.equal(isMeaningfulPace(300, 1000), true);
	// Zero or negative duration — a corrupt / manually-edited row. Web's
	// formatPace used to render these as "0:00 /km" / "-5:00 /km" while the
	// Dart UnitFormat.pace returned the "--:--" sentinel (the parity drift).
	assert.equal(isMeaningfulPace(0, 1000), false);
	assert.equal(isMeaningfulPace(-300, 1000), false);
	// Zero or negative distance.
	assert.equal(isMeaningfulPace(300, 0), false);
	assert.equal(isMeaningfulPace(300, -1000), false);
	// Non-finite inputs never produce a pace string.
	assert.equal(isMeaningfulPace(NaN, 1000), false);
	assert.equal(isMeaningfulPace(300, Infinity), false);
});

test('paceParts keeps seconds in 0-59 after rollover', () => {
	assert.deepEqual(paceParts(330), { minutes: 5, seconds: 30 });
	assert.deepEqual(paceParts(299.6), { minutes: 5, seconds: 0 });
	assert.deepEqual(paceParts(359.7), { minutes: 6, seconds: 0 });
	for (const x of [59.5, 119.6, 299.6, 359.7, 599.9]) {
		assert.ok(paceParts(x).seconds <= 59, `${x} produced seconds > 59`);
	}
});

test('a degenerate pace gets the placeholder, never NaN, Infinity or a sign', () => {
	// What a brand-new account's minimal data divides to: seconds over a 0 m
	// run is Infinity, 0 s over 0 m is NaN, and a 10 s / 3 m run is a real
	// (slow) 55:33. Mirrors `UnitFormat.pace degenerate input` in
	// preferences_helpers_test.dart.
	const cases: Array<[number, string]> = [
		[Number.POSITIVE_INFINITY, '--:--'],
		[Number.NEGATIVE_INFINITY, '--:--'],
		[Number.NaN, '--:--'],
		[-1, '--:--'],
		[-0, '0:00'],
		[0, '0:00'],
		[3333.3, '55:33'],
	];
	for (const [input, expected] of cases) {
		assert.equal(paceMinutesSeconds(input), expected, `paceMinutesSeconds(${input})`);
	}
});

test('a pace tolerance is converted to the pace unit and labelled with it', () => {
	assert.equal(paceToleranceLabel(10, 'km'), '±10s/km');
	// 10 s/km is 16.09 s/mi.
	assert.equal(paceToleranceLabel(10, 'mi'), '±16s/mi');
	assert.equal(paceToleranceLabel(15, 'mi'), '±24s/mi');
});

// The editor shows and takes the tolerance per the display unit; the column
// is per km. ±10 s/mi typed as-is was stored as ±10 s/km and read back as
// "±16s/mi" beside the pace.
test('an editor tolerance round-trips through the per-km column', () => {
	assert.equal(paceToleranceFromUnit(10, 'mi'), 6);
	assert.equal(paceToleranceToUnit(6, 'mi'), 10);
	assert.equal(paceToleranceLabel(paceToleranceFromUnit(10, 'mi'), 'mi'), '±10s/mi');
	assert.equal(paceToleranceFromUnit(10, 'km'), 10);
	assert.equal(paceToleranceToUnit(10, 'km'), 10);
	// The column is whole seconds per km, about 1.6 s per mile, so a mile
	// tolerance comes back within a second of what was typed, never 60% off.
	for (let typed = 0; typed <= 60; typed++) {
		const back = paceToleranceToUnit(paceToleranceFromUnit(typed, 'mi'), 'mi');
		assert.ok(Math.abs(back - typed) <= 1, `${typed} s/mi came back as ${back}`);
	}
});

// The plan wizard's outline pace sits beside distances in the runner's unit.
// It used to be shown and stored per km whatever the unit: 5:30/km read as a
// mile pace, and 8:51 typed for a mile was stored as 8:51/km (14:15/mi).
test('a pace field reads and writes in the runner\'s unit', () => {
	assert.equal(paceFieldFromSecPerKm(330, 'km'), '5:30');
	assert.equal(paceFieldFromSecPerKm(330, 'mi'), '8:51');
	assert.equal(paceFieldFromSecPerKm(null, 'mi'), '');
	assert.equal(paceFieldFromSecPerKm(0, 'km'), '');
	assert.equal(secPerKmFromPaceField('5:30', 'km'), 330);
	assert.equal(secPerKmFromPaceField('8:51', 'mi'), 330);
	assert.equal(secPerKmFromPaceField(' 8:51 ', 'mi'), 330);
	assert.equal(secPerKmFromPaceField('', 'mi'), null);
	assert.equal(secPerKmFromPaceField('8:75', 'mi'), null);
	assert.equal(secPerKmFromPaceField('851', 'mi'), null);
	assert.equal(secPerKmFromPaceField('0:00', 'km'), null);
	// Whole seconds per km, the column's type, and stable on a second pass.
	for (const secPerKm of [180, 240, 299, 300, 330, 420, 600]) {
		const field = paceFieldFromSecPerKm(secPerKm, 'mi');
		assert.ok(Number.isInteger(secPerKmFromPaceField(field, 'mi')));
		assert.equal(paceFieldFromSecPerKm(secPerKmFromPaceField(field, 'mi'), 'mi'), field);
	}
});

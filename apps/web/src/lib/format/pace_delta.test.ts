import { test } from 'node:test';
import assert from 'node:assert/strict';
import { paceDeltaLabel } from './pace_delta';

// Mirrored case for case by apps/mobile_android/test/unit_format_pace_delta_test.dart.

test('per km: signed whole seconds with the unit', () => {
	assert.equal(paceDeltaLabel(12, 'km'), '+12s/km');
	assert.equal(paceDeltaLabel(-5, 'km'), '−5s/km');
	assert.equal(paceDeltaLabel(0, 'km'), '0s/km');
});

test('per mile: converted, not relabelled', () => {
	assert.equal(paceDeltaLabel(10, 'mi'), '+16s/mi');
	assert.equal(paceDeltaLabel(-10, 'mi'), '−16s/mi');
});

test('the "+428s" badge of issue #1300 reads +689s/mi', () => {
	assert.equal(paceDeltaLabel(428, 'mi'), '+689s/mi');
});

test('a delta that rounds to zero carries no sign', () => {
	assert.equal(paceDeltaLabel(0.2, 'mi'), '0s/mi');
	assert.equal(paceDeltaLabel(-0.2, 'km'), '0s/km');
	assert.equal(paceDeltaLabel(-0.5, 'km'), '0s/km');
});

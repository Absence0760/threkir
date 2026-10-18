import { test } from 'node:test';
import assert from 'node:assert/strict';
import { planCalibrationFrom } from './plan_calibration.ts';
import type { PrefsBag } from '#lib/settings/settings_overlay.ts';

const NOW = Date.UTC(2026, 9, 18, 12);
const settingsWith = (universal: PrefsBag) => ({ universal, device: {} });

test('planCalibrationFrom: a consented date of birth gives the age and a usable state', () => {
	const c = planCalibrationFrom(
		{ gender: 'female', date_of_birth: '1970-03-02', health_data_consent_at: '2026-01-01T00:00:00Z' },
		settingsWith({}),
		NOW,
	);
	assert.deepEqual(c, { gender: 'female', age: 56, dobState: 'usable', extraRecovery: false });
});

test('planCalibrationFrom: no date of birth reads as absent, a withheld consent as consent_withheld', () => {
	assert.equal(planCalibrationFrom({ date_of_birth: null }, null, NOW).dobState, 'absent');
	const withheld = planCalibrationFrom({ date_of_birth: '1970-03-02', health_data_consent_at: null }, null, NOW);
	assert.equal(withheld.dobState, 'consent_withheld');
	assert.equal(withheld.age, null);
});

test('planCalibrationFrom: a failed profile read hides the date-of-birth state rather than call it absent', () => {
	const c = planCalibrationFrom(undefined, settingsWith({ extra_recovery: true }), NOW);
	assert.deepEqual(c, { gender: null, age: null, dobState: null, extraRecovery: true });
});

test('planCalibrationFrom: only a literal true turns extra recovery on', () => {
	assert.equal(planCalibrationFrom(null, settingsWith({ extra_recovery: 'true' }), NOW).extraRecovery, false);
	assert.equal(planCalibrationFrom(null, settingsWith({ extra_recovery: false }), NOW).extraRecovery, false);
	assert.equal(planCalibrationFrom(null, null, NOW).extraRecovery, false);
	assert.equal(
		planCalibrationFrom(null, { universal: {}, device: { extra_recovery: true } }, NOW).extraRecovery,
		true,
	);
});

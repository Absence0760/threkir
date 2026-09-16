// Invocation:
//   cd apps/web && npx tsx --test src/lib/integrations/integration_visibility.test.ts
//
// Mirror suite: `apps/mobile_android/test/integration_visibility_test.dart`.
import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	gateIntegrations,
	integrationIsActionable,
	integrationIsStranded,
	integrationIsVisible,
	integrationStatus,
	visibleIntegrations,
	type IntegrationGate
} from './integration_visibility';

const SPECS = [
	{ provider: 'strava', gate: 'env' as IntegrationGate },
	{ provider: 'parkrun', gate: 'probe' as IntegrationGate },
	{ provider: 'garmin', gate: 'unbuilt' as IntegrationGate },
	{ provider: 'healthkit', gate: 'unsupported' as IntegrationGate },
	{ provider: 'stravazip', gate: 'always' as IntegrationGate }
];

test('a resolved env / probe gate reads its verdict', () => {
	assert.equal(integrationStatus('env', true), 'usable');
	assert.equal(integrationStatus('env', false), 'unconfigured');
	assert.equal(integrationStatus('probe', true), 'usable');
	assert.equal(integrationStatus('probe', false), 'unconfigured');
});

test('an unresolved verdict is pending, not unconfigured', () => {
	// The two want different copy, and collapsing them would make every page
	// load flash the "not configured on this deployment" explainer before the
	// probe lands.
	assert.equal(integrationStatus('probe', null), 'pending');
	assert.equal(integrationStatus('env', null), 'pending');
});

test('always / unsupported / unbuilt ignore the verdict entirely', () => {
	for (const verdict of [true, false, null] as const) {
		assert.equal(integrationStatus('always', verdict), 'usable');
		assert.equal(integrationStatus('unsupported', verdict), 'unsupported');
		assert.equal(integrationStatus('unbuilt', verdict), 'unbuilt');
	}
});

test('only a usable provider is actionable', () => {
	assert.equal(integrationIsActionable('usable'), true);
	for (const status of ['pending', 'unconfigured', 'unsupported', 'unbuilt'] as const) {
		assert.equal(integrationIsActionable(status), false, status);
	}
});

test('visibility is fail-closed for an unconnected provider', () => {
	assert.equal(integrationIsVisible('usable', false), true);
	for (const status of ['pending', 'unconfigured', 'unsupported', 'unbuilt'] as const) {
		assert.equal(integrationIsVisible(status, false), false, status);
	}
});

test('a connected provider stays visible whatever its gate says', () => {
	// An `integrations` row outlives the configuration that created it. Hiding
	// one would strand it: no surface to disconnect from, and on Strava's path
	// a stored grant still rotating its token server-side.
	for (const status of ['usable', 'pending', 'unconfigured', 'unsupported', 'unbuilt'] as const) {
		assert.equal(integrationIsVisible(status, true), true, status);
	}
});

test('a connected-but-ungated provider is visible without being actionable', () => {
	const [garmin] = gateIntegrations([SPECS[2]], {}, ['garmin']);
	assert.equal(garmin.connected, true);
	assert.equal(garmin.status, 'unbuilt');
	assert.equal(garmin.actionable, false);
	assert.equal(integrationIsVisible(garmin.status, garmin.connected), true);
});

test('a missing verdict key reads as pending, not as a crash or a false', () => {
	// Surfaces start with an empty map and fill it as probes land; requiring a
	// seeded entry per provider would make an added provider default to
	// "unconfigured" in the window before anyone wrote its probe.
	const graded = gateIntegrations(SPECS, {}, []);
	assert.equal(graded.find((g) => g.spec.provider === 'parkrun')?.status, 'pending');
});

test('visibleIntegrations filters and preserves catalogue order', () => {
	const visible = visibleIntegrations(
		SPECS,
		{ strava: true, parkrun: false },
		['healthkit']
	);
	assert.deepEqual(
		visible.map((v) => v.spec.provider),
		['strava', 'healthkit', 'stravazip']
	);
});

test('an unconfigured deployment offers nothing it cannot honour', () => {
	// The shape this whole module exists for: no env var, no reachable Edge
	// Functions, no connected rows.
	const visible = visibleIntegrations(SPECS, { strava: false, parkrun: false }, []);
	assert.deepEqual(
		visible.map((v) => v.spec.provider),
		['stravazip']
	);
});

test('grading never mutates the catalogue it was handed', () => {
	const before = JSON.stringify(SPECS);
	gateIntegrations(SPECS, { strava: true }, ['strava']);
	assert.equal(JSON.stringify(SPECS), before);
});

test('only a connected row against a leg that exists nowhere is stranded', () => {
	// `unconfigured` is deliberately NOT stranded: the env var gates starting a
	// new grant, not syncing one that already exists.
	assert.equal(integrationIsStranded('unconfigured', true), false);
	assert.equal(integrationIsStranded('usable', true), false);
	assert.equal(integrationIsStranded('pending', true), false);
	assert.equal(integrationIsStranded('unsupported', true), true);
	assert.equal(integrationIsStranded('unbuilt', true), true);
	for (const status of ['usable', 'pending', 'unconfigured', 'unsupported', 'unbuilt'] as const) {
		assert.equal(integrationIsStranded(status, false), false, status);
	}
});

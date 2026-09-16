import 'package:flutter_test/flutter_test.dart';

import '../lib/integration_visibility.dart';

/// Mirror suite: `apps/web/src/lib/integrations/integration_visibility.test.ts`.
void main() {
  const specs = [
    IntegrationSpec(provider: 'strava', gate: IntegrationGate.env),
    IntegrationSpec(provider: 'parkrun', gate: IntegrationGate.probe),
    IntegrationSpec(provider: 'garmin', gate: IntegrationGate.unbuilt),
    IntegrationSpec(provider: 'healthkit', gate: IntegrationGate.unsupported),
    IntegrationSpec(provider: 'stravazip', gate: IntegrationGate.always),
  ];

  test('a resolved env / probe gate reads its verdict', () {
    expect(integrationStatus(IntegrationGate.env, true),
        IntegrationStatus.usable);
    expect(integrationStatus(IntegrationGate.env, false),
        IntegrationStatus.unconfigured);
    expect(integrationStatus(IntegrationGate.probe, true),
        IntegrationStatus.usable);
    expect(integrationStatus(IntegrationGate.probe, false),
        IntegrationStatus.unconfigured);
  });

  test('an unresolved verdict is pending, not unconfigured', () {
    // The two want different copy, and collapsing them would make every screen
    // open flash the "not configured on this deployment" explainer before the
    // probe lands.
    expect(integrationStatus(IntegrationGate.probe, null),
        IntegrationStatus.pending);
    expect(
        integrationStatus(IntegrationGate.env, null), IntegrationStatus.pending);
  });

  test('always / unsupported / unbuilt ignore the verdict entirely', () {
    for (final verdict in <bool?>[true, false, null]) {
      expect(integrationStatus(IntegrationGate.always, verdict),
          IntegrationStatus.usable);
      expect(integrationStatus(IntegrationGate.unsupported, verdict),
          IntegrationStatus.unsupported);
      expect(integrationStatus(IntegrationGate.unbuilt, verdict),
          IntegrationStatus.unbuilt);
    }
  });

  test('only a usable provider is actionable', () {
    expect(integrationIsActionable(IntegrationStatus.usable), isTrue);
    for (final status in [
      IntegrationStatus.pending,
      IntegrationStatus.unconfigured,
      IntegrationStatus.unsupported,
      IntegrationStatus.unbuilt,
    ]) {
      expect(integrationIsActionable(status), isFalse, reason: '$status');
    }
  });

  test('visibility is fail-closed for an unconnected provider', () {
    expect(integrationIsVisible(IntegrationStatus.usable, false), isTrue);
    for (final status in [
      IntegrationStatus.pending,
      IntegrationStatus.unconfigured,
      IntegrationStatus.unsupported,
      IntegrationStatus.unbuilt,
    ]) {
      expect(integrationIsVisible(status, false), isFalse, reason: '$status');
    }
  });

  test('a connected provider stays visible whatever its gate says', () {
    // An `integrations` row outlives the configuration that created it. Hiding
    // one would strand it: no surface to disconnect from, and on Strava's path
    // a stored grant still rotating its token server-side.
    for (final status in IntegrationStatus.values) {
      expect(integrationIsVisible(status, true), isTrue, reason: '$status');
    }
  });

  test('a connected-but-ungated provider is visible without being actionable',
      () {
    final garmin = gateIntegrations([specs[2]], {}, ['garmin']).single;
    expect(garmin.connected, isTrue);
    expect(garmin.status, IntegrationStatus.unbuilt);
    expect(garmin.actionable, isFalse);
    expect(integrationIsVisible(garmin.status, garmin.connected), isTrue);
  });

  test('a missing verdict key reads as pending, not as a crash or a false', () {
    // Surfaces start with an empty map and fill it as probes land; requiring a
    // seeded entry per provider would make an added provider default to
    // "unconfigured" in the window before anyone wrote its probe.
    final graded = gateIntegrations(specs, {}, []);
    expect(graded.firstWhere((g) => g.spec.provider == 'parkrun').status,
        IntegrationStatus.pending);
  });

  test('visibleIntegrations filters and preserves catalogue order', () {
    final visible = visibleIntegrations(
      specs,
      {'strava': true, 'parkrun': false},
      ['healthkit'],
    );
    expect(visible.map((v) => v.spec.provider).toList(),
        ['strava', 'healthkit', 'stravazip']);
  });

  test('an unconfigured deployment offers nothing it cannot honour', () {
    // The shape this whole module exists for: no env var, no reachable Edge
    // Functions, no connected rows.
    final visible =
        visibleIntegrations(specs, {'strava': false, 'parkrun': false}, []);
    expect(visible.map((v) => v.spec.provider).toList(), ['stravazip']);
  });

  test('grading never mutates the catalogue it was handed', () {
    final before = specs.map((s) => '${s.provider}:${s.gate}').toList();
    gateIntegrations(specs, {'strava': true}, ['strava']);
    expect(specs.map((s) => '${s.provider}:${s.gate}').toList(), before);
  });

  test('only a connected row against a leg that exists nowhere is stranded',
      () {
    // `unconfigured` is deliberately NOT stranded: the env var gates starting a
    // new grant, not syncing one that already exists.
    expect(integrationIsStranded(IntegrationStatus.unconfigured, true), isFalse);
    expect(integrationIsStranded(IntegrationStatus.usable, true), isFalse);
    expect(integrationIsStranded(IntegrationStatus.pending, true), isFalse);
    expect(integrationIsStranded(IntegrationStatus.unsupported, true), isTrue);
    expect(integrationIsStranded(IntegrationStatus.unbuilt, true), isTrue);
    for (final status in IntegrationStatus.values) {
      expect(integrationIsStranded(status, false), isFalse, reason: '$status');
    }
  });
}

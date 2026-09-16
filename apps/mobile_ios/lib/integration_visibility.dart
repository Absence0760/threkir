/// Whether an integration is offered to this runner, on this deployment.
///
/// TS↔Dart parity pair with
/// `apps/web/src/lib/integrations/integration_visibility.ts`. Read that file
/// for why the rules are what they are; this half states them in Dart and
/// nothing else. The only shape difference: web's `IntegrationGate` and
/// `IntegrationStatus` are string unions, which are enums here.
library;

/// How a provider's availability is decided. The kind is a fact about the
/// PROVIDER, not about one deployment: [unbuilt] and [unsupported] describe
/// something no operator can configure their way out of, which is why they are
/// separate from an [env] / [probe] gate that is merely unset today.
enum IntegrationGate {
  /// A build-time env var decides it (Strava's `STRAVA_CLIENT_ID` in dotenv).
  env,

  /// An Edge Function probe decides it (parkrun, the three race-results legs).
  probe,

  /// Nothing to configure: the work happens entirely on the device.
  always,

  /// Cannot work on this client at all, on any deployment.
  unsupported,

  /// The connect leg does not exist yet, on any deployment.
  unbuilt,
}

enum IntegrationStatus { usable, pending, unconfigured, unsupported, unbuilt }

/// A resolved gate answer. `null` means "not yet known" — a probe still in
/// flight — and is NOT the same as `false`, because the two want different
/// copy: an unresolved probe has nothing to explain to the runner yet.
IntegrationStatus integrationStatus(IntegrationGate gate, bool? verdict) {
  switch (gate) {
    case IntegrationGate.always:
      return IntegrationStatus.usable;
    case IntegrationGate.unsupported:
      return IntegrationStatus.unsupported;
    case IntegrationGate.unbuilt:
      return IntegrationStatus.unbuilt;
    case IntegrationGate.env:
    case IntegrationGate.probe:
      if (verdict == true) return IntegrationStatus.usable;
      if (verdict == false) return IntegrationStatus.unconfigured;
      return IntegrationStatus.pending;
  }
}

/// Whether the runner may start a connect / import from this tile.
bool integrationIsActionable(IntegrationStatus status) =>
    status == IntegrationStatus.usable;

/// Whether the tile is rendered at all. Fail-closed, except that a connected
/// row is always shown so it can still be disconnected.
bool integrationIsVisible(IntegrationStatus status, bool connected) =>
    connected || status == IntegrationStatus.usable;

/// Whether a connected row is STRANDED — still linked to the account, but
/// attached to something this client can never drive.
bool integrationIsStranded(IntegrationStatus status, bool connected) =>
    connected &&
    (status == IntegrationStatus.unsupported ||
        status == IntegrationStatus.unbuilt);

class IntegrationSpec {
  final String provider;
  final IntegrationGate gate;

  const IntegrationSpec({required this.provider, required this.gate});
}

class IntegrationGated<T extends IntegrationSpec> {
  final T spec;
  final IntegrationStatus status;
  final bool connected;
  final bool actionable;

  const IntegrationGated({
    required this.spec,
    required this.status,
    required this.connected,
    required this.actionable,
  });
}

/// Grade a whole catalogue in one pass — what a surface renders from.
///
/// [verdicts] is keyed by provider and a missing key reads as `null`, so a
/// surface may start with an empty map and fill it as probes land without
/// having to seed one entry per provider first.
List<IntegrationGated<T>> gateIntegrations<T extends IntegrationSpec>(
  List<T> specs,
  Map<String, bool?> verdicts,
  List<String> connectedProviders,
) {
  final connected = connectedProviders.toSet();
  return [
    for (final spec in specs)
      () {
        final status = integrationStatus(spec.gate, verdicts[spec.provider]);
        return IntegrationGated<T>(
          spec: spec,
          status: status,
          connected: connected.contains(spec.provider),
          actionable: integrationIsActionable(status),
        );
      }(),
  ];
}

/// The subset a surface renders. Order is the catalogue's, so hiding one
/// provider never reorders the rest.
List<IntegrationGated<T>> visibleIntegrations<T extends IntegrationSpec>(
  List<T> specs,
  Map<String, bool?> verdicts,
  List<String> connectedProviders,
) =>
    gateIntegrations(specs, verdicts, connectedProviders)
        .where((g) => integrationIsVisible(g.status, g.connected))
        .toList();

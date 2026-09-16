/// Whether an integration is offered to this runner, on this deployment.
///
/// Every provider surface used to decide this for itself, and the four answers
/// did not agree. Strava checked its client ID only INSIDE the click handler,
/// so an unconfigured deployment rendered a live Connect button whose sole
/// disclosure was the error toast it raised after the tap. The three race legs
/// probed their Edge Function properly. parkrun, Garmin Connect and Apple
/// HealthKit checked nothing at all — and two of those can never work from a
/// browser, whatever is configured: HealthKit is an on-device iOS API with no
/// web binding, and Garmin Connect OAuth is blocked on Garmin's developer
/// programme rather than on a key anyone can set.
///
/// This module is the one place that grades them. It is deliberately pure —
/// it takes a resolved verdict rather than reaching for `$env` or supabase-js —
/// so the rules below are reachable from a unit test; `availability.ts` is the
/// thin layer that wires each gate to its real source.
///
/// TS↔Dart parity pair with `apps/mobile_android/lib/integration_visibility.dart`.

/// How a provider's availability is decided. The kind is a fact about the
/// PROVIDER, not about one deployment: `unbuilt` and `unsupported` describe
/// something no operator can configure their way out of, which is why they are
/// separate from an `env` / `probe` gate that is merely unset today.
export type IntegrationGate =
	/// A build-time public env var decides it (Strava's `PUBLIC_STRAVA_CLIENT_ID`).
	/// Resolves synchronously, so such a card never flashes in and out.
	| 'env'
	/// An Edge Function probe decides it (parkrun, the three race-results legs).
	/// Resolves over the network, so the verdict is null until it lands.
	| 'probe'
	/// Nothing to configure: the work happens entirely in the browser. The bulk
	/// importers parse a file locally and write through the same client every
	/// other page already uses, so there is no leg that can be missing.
	| 'always'
	/// Cannot work on this client at all, on any deployment.
	| 'unsupported'
	/// The connect leg does not exist yet, on any deployment.
	| 'unbuilt';

/// A resolved gate answer. `null` means "not yet known" — a probe still in
/// flight — and is NOT the same as `false`, because the two want different
/// copy: an unresolved probe has nothing to explain to the runner yet.
export type GateVerdict = boolean | null;

export type IntegrationStatus =
	| 'usable'
	| 'pending'
	| 'unconfigured'
	| 'unsupported'
	| 'unbuilt';

export function integrationStatus(gate: IntegrationGate, verdict: GateVerdict): IntegrationStatus {
	switch (gate) {
		case 'always':
			return 'usable';
		case 'unsupported':
			return 'unsupported';
		case 'unbuilt':
			return 'unbuilt';
		case 'env':
		case 'probe':
			return verdict === true ? 'usable' : verdict === false ? 'unconfigured' : 'pending';
	}
}

/// Whether the runner may start a connect / import from this card.
export function integrationIsActionable(status: IntegrationStatus): boolean {
	return status === 'usable';
}

/// Whether the card is rendered at all.
///
/// Two rules, and the second is the one that is easy to get wrong:
///
///  1. **Fail-closed.** Only a `usable` provider is offered. A pending probe
///     hides, like a refused one — the house default everywhere else, and the
///     cheaper mistake in both directions: a card that appears a moment late
///     costs nothing, a card offered before its leg answered costs a runner who
///     taps Connect and is refused.
///  2. **A connected provider is ALWAYS shown, whatever its gate says.** An
///     `integrations` row outlives the configuration that created it — a
///     deployment can lose its Strava client ID, and the placeholder Garmin /
///     HealthKit rows the old ungated cards wrote are still out there. Hiding
///     those would strand the row: the runner can no longer see the connection,
///     cannot disconnect it, and on Strava's path the stored grant keeps its
///     token rotating server-side with no surface that admits it exists.
export function integrationIsVisible(status: IntegrationStatus, connected: boolean): boolean {
	return connected || status === 'usable';
}

/// Whether a connected row is STRANDED — still linked to the account, but
/// attached to something this client can never drive.
///
/// Narrower than `!actionable` on purpose. An `unconfigured` Strava is not
/// stranded: `PUBLIC_STRAVA_CLIENT_ID` builds the OAuth redirect and so gates
/// starting a NEW grant, while syncing an existing one runs entirely on the
/// Edge Function's own server-side credentials. Saying "this can't sync here"
/// over a connection that syncs fine would be its own lie, and the sync's real
/// refusal already has a sentence of its own.
///
/// `unsupported` and `unbuilt` are different: no leg exists on any deployment,
/// so a row against one is a placeholder an earlier ungated card wrote, and
/// disconnecting it is the only thing left to do with it.
export function integrationIsStranded(
	status: IntegrationStatus,
	connected: boolean
): boolean {
	return connected && (status === 'unsupported' || status === 'unbuilt');
}

export interface IntegrationGated<T extends { provider: string; gate: IntegrationGate }> {
	spec: T;
	status: IntegrationStatus;
	connected: boolean;
	actionable: boolean;
}

/// Grade a whole catalogue in one pass — what a surface renders from.
///
/// `verdicts` is keyed by provider and read with a missing key meaning `null`,
/// so a surface may start with an empty map and fill it as probes land without
/// having to seed one entry per provider first.
export function gateIntegrations<T extends { provider: string; gate: IntegrationGate }>(
	specs: readonly T[],
	verdicts: Readonly<Record<string, GateVerdict>>,
	connectedProviders: readonly string[]
): IntegrationGated<T>[] {
	const connectedSet = new Set(connectedProviders);
	return specs.map((spec) => {
		const status = integrationStatus(spec.gate, verdicts[spec.provider] ?? null);
		return {
			spec,
			status,
			connected: connectedSet.has(spec.provider),
			actionable: integrationIsActionable(status)
		};
	});
}

/// The subset a surface renders. Order is the catalogue's, so hiding one
/// provider never reorders the rest.
export function visibleIntegrations<T extends { provider: string; gate: IntegrationGate }>(
	specs: readonly T[],
	verdicts: Readonly<Record<string, GateVerdict>>,
	connectedProviders: readonly string[]
): IntegrationGated<T>[] {
	return gateIntegrations(specs, verdicts, connectedProviders).filter((g) =>
		integrationIsVisible(g.status, g.connected)
	);
}

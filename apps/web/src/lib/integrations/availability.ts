/// The integration catalogue, and the wiring from each provider's gate to the
/// real thing that decides it.
///
/// Split from `integration_visibility.ts` on purpose: the rules live there and
/// are unit-testable, while this half reaches for `$env` and supabase-js and so
/// can only be exercised through the browser. Keep decisions out of here — this
/// file should read as a table plus four calls.

import {
	isChronoTrackConfigured,
	isParkrunConfigured,
	isRunSignUpConfigured,
	isUltraSignUpConfigured
} from '$lib/core/data';
import { isStravaConfigured } from './strava';
import type { GateVerdict, IntegrationGate } from './integration_visibility';

export interface IntegrationSpec {
	provider: string;
	gate: IntegrationGate;
	/// Material Symbols ligature. Must be in the subset — `pnpm gen:icon-font`
	/// after adding one that isn't (decisions § 780).
	icon: string;
	/// The brand's own name. Deliberately NOT translated: "Strava" is "Strava"
	/// in every locale, and routing it through the catalogue would invite a
	/// translator to localise a company name.
	name: string;
}

/// The account-connection cards. Order is the render order.
export const CONNECT_INTEGRATIONS: readonly IntegrationSpec[] = [
	{ provider: 'strava', gate: 'env', icon: 'directions_run', name: 'Strava' },
	{ provider: 'parkrun', gate: 'probe', icon: 'emoji_events', name: 'parkrun' },
	// Garmin Connect's OAuth + webhook sync is blocked on Garmin's developer
	// programme (NDA, multi-week review) — neither leg can be implemented
	// client-side, so no operator can configure this into existence. The card
	// used to render a live Connect button that wrote a placeholder
	// `integrations` row and synced nothing. The Garmin path that DOES work is
	// the bulk .fit / .zip importer further down the page, which needs no
	// account at all. Flip to 'env' or 'probe' when the programme grants access.
	{ provider: 'garmin', gate: 'unbuilt', icon: 'watch', name: 'Garmin Connect' },
	// HealthKit is an on-device iOS framework with no web binding and no server
	// leg — there is nothing for a browser to connect to, on any deployment.
	// It belongs to the iOS app, where it is a system permission rather than an
	// integration card.
	{ provider: 'healthkit', gate: 'unsupported', icon: 'favorite', name: 'Apple HealthKit' }
];

/// The race-results cards. Each is a deep link into `/races` whose import leg
/// is separately credential-gated server-side.
export const RACE_INTEGRATIONS: readonly IntegrationSpec[] = [
	{ provider: 'runsignup', gate: 'probe', icon: 'flag', name: 'RunSignUp' },
	{ provider: 'ultrasignup', gate: 'probe', icon: 'terrain', name: 'UltraSignup' },
	{ provider: 'chronotrack', gate: 'probe', icon: 'timer', name: 'ChronoTrack' }
];

/// Every probe the page runs, keyed by provider.
const PROBES: Record<string, () => Promise<boolean>> = {
	parkrun: isParkrunConfigured,
	runsignup: isRunSignUpConfigured,
	ultrasignup: isUltraSignUpConfigured,
	chronotrack: isChronoTrackConfigured
};

/// Resolve every gate in the catalogue.
///
/// Each probe is settled independently and degrades to `false` on its own —
/// one unreachable leg must not decide the others or take the page down, which
/// is the L4 rule the recording stack states and a settings page has no excuse
/// to break. `Promise.all` over per-probe catches rather than `allSettled` so
/// the caller gets a plain map.
export async function resolveIntegrationVerdicts(): Promise<Record<string, GateVerdict>> {
	const verdicts: Record<string, GateVerdict> = { strava: isStravaConfigured() };
	await Promise.all(
		Object.entries(PROBES).map(async ([provider, probe]) => {
			try {
				verdicts[provider] = await probe();
			} catch {
				verdicts[provider] = false;
			}
		})
	);
	return verdicts;
}

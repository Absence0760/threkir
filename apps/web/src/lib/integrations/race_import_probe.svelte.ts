import { isRaceImportProviderConfigured } from '#lib/core/data.ts';
import type { RaceImportLeg } from '#lib/integrations/race_import_providers.ts';

// One credential probe per import leg, shared by the race calendar and the race
// detail page. Absent means "not answered yet" and the import dialog renders
// nothing for that leg; only a resolved probe lets it offer the import or say
// the provider is unavailable. Probing spends the import function's own hourly
// rate limit, and a 429 reads as unavailable, so each leg is asked once and
// the answer is kept — a second surface asking again could only make a
// configured provider look unavailable.
export const raceLegAvailable = $state<Partial<Record<RaceImportLeg, boolean>>>({});

const probed = new Set<RaceImportLeg>();

export async function probeRaceLeg(leg: RaceImportLeg): Promise<void> {
	if (probed.has(leg)) return;
	probed.add(leg);
	let ok = false;
	try {
		ok = await isRaceImportProviderConfigured(leg);
	} catch {
		ok = false;
	}
	raceLegAvailable[leg] = ok;
}

/// The leg refused a call after its probe said yes; the dialog must stop
/// offering the form rather than keep failing.
export function markRaceLegUnavailable(leg: RaceImportLeg): void {
	probed.add(leg);
	raceLegAvailable[leg] = false;
}

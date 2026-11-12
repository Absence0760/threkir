// Kept out of units.svelte.ts on purpose: the root layout loads that module,
// and plan_nudges reaches the replan and volume-anchor code, so importing it
// there put the plan logic in every route's download (decisions § 2215).

import { distanceInPreferred, fmtKm } from './units.svelte';
import { overrunDigits } from '../training/plan_nudges';

/// How far a workout ran past its target, for "Done · +3 km": whole units
/// unless a tenth says something (`overrunDigits`, plan_nudges.ts).
export function fmtOverrun(metres: number): string {
	return fmtKm(metres, overrunDigits(distanceInPreferred(metres).value));
}

import {
	MODALITIES,
	MODALITY_VISIBILITY_KEYS,
	explicitModalityChoice,
	modalityShown,
	type Modality,
} from '$lib/settings/modality_visibility';
import type { LoadedSettings } from '$lib/settings/settings_overlay';
import { updateUniversal } from '$lib/settings/settings';
import { fetchModalityHasData } from '$lib/core/data';
import { showToast } from '$lib/stores/toast.svelte';
import { m } from '$lib/i18n/store.svelte';
import { goto } from '$app/navigation';

/// Session-wide answer to "is Gym / Nutrition surfaced?", read by the sidebar,
/// /dashboard, /history and the settings toggles so they all agree. The
/// resolution itself is `modalityShown` in `settings/modality_visibility.ts`.
///
/// `hasData` is null until the one-row presence read lands, and reads as no
/// data meanwhile: a runner with lifts sees Gym appear a beat after first
/// paint, which is the cheaper failure than flashing it at every runner who
/// has none. The read is skipped for a modality with an explicit choice,
/// since the data cannot change the answer.
interface Slot {
	explicit: boolean | null;
	hasData: boolean | null;
}

const state = $state<{ userId: string | null } & Record<Modality, Slot>>({
	userId: null,
	gym: { explicit: null, hasData: null },
	nutrition: { explicit: null, hasData: null },
});

export function modalityVisible(modality: Modality): boolean {
	const slot = state[modality];
	return modalityShown({ explicit: slot.explicit, hasData: slot.hasData ?? false });
}

/// The explicit choice alone. A first-run "log a lift" prompt reads this so a
/// runner who switched Gym off is not invited back into it.
export function modalityExplicit(modality: Modality): boolean | null {
	return state[modality].explicit;
}

export async function hydrateModalityVisibility(
	userId: string,
	settings: LoadedSettings,
): Promise<void> {
	if (state.userId !== userId) resetModalityVisibility(userId);
	for (const modality of MODALITIES) {
		state[modality].explicit = explicitModalityChoice(settings, modality);
	}
	await Promise.all(
		MODALITIES.map(async (modality) => {
			const slot = state[modality];
			if (slot.explicit !== null || slot.hasData !== null) return;
			let hasData: boolean;
			try {
				hasData = await fetchModalityHasData(userId, modality);
			} catch (e) {
				// Fail open: an outage must not take Gym away from someone who lifts.
				console.warn(`modality presence read failed (${modality})`, e);
				hasData = true;
			}
			if (state.userId === userId) state[modality].hasData = hasData;
		}),
	);
}

export function resetModalityVisibility(userId: string | null = null): void {
	state.userId = userId;
	for (const modality of MODALITIES) {
		state[modality] = { explicit: null, hasData: null };
	}
}

/// A lift or a meal was just logged, so the modality now has data.
export function noteModalityData(modality: Modality): void {
	state[modality].hasData = true;
}

/// Mirror a choice the settings page has already queued for writing.
export function setModalityChoice(modality: Modality, shown: boolean): void {
	state[modality].explicit = shown;
}

/// Asking to log a lift is asking for Gym: a Log action or a first-run link
/// for a hidden modality switches it on before the caller navigates, so the
/// runner is not left on a page the sidebar gives them no way back to. The
/// same rule mobile applies (decisions § 1739). A refused write rolls the
/// choice back and says so; the navigation goes ahead either way.
export async function revealModality(modality: Modality): Promise<void> {
	const userId = state.userId;
	if (!userId || modalityVisible(modality)) return;
	const previous = state[modality].explicit;
	state[modality].explicit = true;
	try {
		await updateUniversal(userId, { [MODALITY_VISIBILITY_KEYS[modality]]: true });
	} catch (e) {
		state[modality].explicit = previous;
		showToast(m('prefs.saveFailed', { error: (e as Error).message }), 'error');
	}
}

/// Click handler for a link into a modality's page: reveals the modality
/// first, then follows the link. A modified click (new tab, new window) is
/// left to the browser, and the reveal runs beside it.
export function revealOnNavigate(modality: Modality): (e: MouseEvent) => void {
	return (e) => {
		if (modalityVisible(modality)) return;
		const link = e.currentTarget as HTMLAnchorElement;
		if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) {
			void revealModality(modality);
			return;
		}
		e.preventDefault();
		void revealModality(modality).then(() => goto(link.pathname + link.search + link.hash));
	};
}

import { onMount, tick } from 'svelte';
import { beforeNavigate } from '$app/navigation';
import { auth } from '$lib/stores/auth.svelte';
import { m, currentLocale } from '$lib/i18n/store.svelte';
import { showToast } from '$lib/stores/toast.svelte';
import {
	loadSettings,
	updateUniversal,
	effective,
	effectivePreferredUnit,
	type LoadedSettings,
	type PrefsBag,
} from './settings';
import { PrefsSaveQueue, type PrefsSaveStatus } from './prefs_save_queue';

export type PrefsLoadPhase = 'loading' | 'ready' | 'failed';

export interface PrefsLoadContext {
	userId: string;
	settings: LoadedSettings;
	preferredUnit: 'km' | 'mi';
}

/// Load + auto-save for one preferences page. Call during component init.
///
/// A failed read must NOT fall back to showing form defaults: the runner
/// could then overwrite their real prefs (including the Art 9 consent-derived
/// fields on the body page) with defaults. So a throw from `load` leaves the
/// page in `failed`, where the shell renders an alert with Retry instead of the
/// form, and every persist path stays unreachable until a reload succeeds.
export function createPrefsPage(load: (ctx: PrefsLoadContext) => Promise<void>) {
	const state = $state({
		phase: 'loading' as PrefsLoadPhase,
		error: null as string | null,
		status: 'idle' as PrefsSaveStatus,
	});

	const queue = new PrefsSaveQueue({
		write: async (batch) => {
			const uid = auth.user?.id;
			if (uid) await updateUniversal(uid, batch);
		},
		onStatus: (status) => (state.status = status),
		onError: (e) => showToast(m('prefs.saveFailed', { error: e.message }), 'error'),
	});

	function save(changes: PrefsBag) {
		if (!auth.user) return;
		queue.enqueue(changes);
	}

	// A change made just before leaving would otherwise wait out the debounce
	// on a page that no longer exists; the write-through cache keeps it even
	// if the network leg is cut short by the navigation.
	beforeNavigate(() => {
		void queue.flush();
	});

	async function reload() {
		const user = auth.user;
		if (!user) return;
		state.phase = 'loading';
		state.error = null;
		try {
			const settings = await loadSettings(user.id);
			await load({
				userId: user.id,
				settings,
				preferredUnit: effectivePreferredUnit(settings, user.preferred_unit),
			});
			// The server localises email by this key (decisions § 120); write it
			// once for a runner who never opened the language picker.
			if (effective<string>(settings, 'locale') == null) save({ locale: currentLocale() });
			state.phase = 'ready';
		} catch (e) {
			console.warn('Settings load failed', e);
			state.error = (e as Error).message;
			state.phase = 'failed';
			return;
		}
		await tick();
		const anchor = location.hash.slice(1);
		if (anchor) document.getElementById(anchor)?.scrollIntoView();
	}

	onMount(async () => {
		await auth.ready();
		if (!auth.user) return;
		await reload();
	});

	return {
		get phase() {
			return state.phase;
		},
		get error() {
			return state.error;
		},
		get status() {
			return state.status;
		},
		/// Callers that set the status themselves (a direct column write
		/// before the bag write) report it through here.
		set status(next: PrefsSaveStatus) {
			state.status = next;
		},
		save,
		flush: () => queue.flush(),
		reload,
	};
}

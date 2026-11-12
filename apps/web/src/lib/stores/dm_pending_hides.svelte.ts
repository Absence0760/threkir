/**
 * Conversations deleted for the runner while their undo window is open. The
 * inbox list and the nav badge both leave them out until the window closes;
 * the server is told only then. Mirrors mobile's `DmPendingHides`.
 */
import { SvelteSet } from 'svelte/reactivity';

export const dmPendingHides = new SvelteSet<string>();

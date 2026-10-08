import type { LayoutLoad } from './$types';
import { loadRouteCatalogues } from '$lib/i18n/store.svelte';

// The message catalogues a route renders with, loaded BEFORE it renders.
// `m()` is synchronous, so an area catalogue (lib/i18n/areas.ts) that arrived
// after first render would show raw key names; SvelteKit resolves every load
// before it mounts the route's components, on the server for a prerendered
// page and in the browser for every navigation and cold deep link alike.
// Reading `route.id` re-runs this on every route change; the catalogue set
// caches, so a revisit costs nothing. Never rejects. decisions § 1802.
export const load: LayoutLoad = async ({ route }) => {
	await loadRouteCatalogues(route.id);
};

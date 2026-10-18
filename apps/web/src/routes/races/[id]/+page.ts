import type { PageLoad } from './$types';

// The signed-in race detail page. A plain client-rendered page like
// /fundraisers/[id]: the listing is read through the public view in the
// browser, so there is nothing per-id to prerender. The logged-out, crawlable
// page for the same race is /share/race/[id].
export const prerender = false;
export const ssr = false;

export const load: PageLoad = ({ params }) => {
	return { id: params.id };
};

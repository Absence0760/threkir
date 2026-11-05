/// Request-time PNG renderer for /og/route/<id>.png. Shared by the
/// production share-route Lambda (apps/web/lambda/share-route/src/
/// index.ts) and the SvelteKit endpoint (apps/web/src/routes/og/route/
/// [id].png/+server.ts) so the SVG card + the missing-route fallback
/// behave identically in dev and prod. Mirror of og_run_png.ts.
///
/// A route that doesn't resolve (private, deleted, or never existed)
/// renders a generic branded card rather than throwing — the caller
/// returns it with HTTP 200 so a social unfurl never shows a broken
/// image.

import { buildRouteOgSvg } from './og_route_image';
import { renderOgPng } from './og_png_render';
import {
	lookupSharedRoute,
	type SharedRouteLookupConfig,
} from './share_route_lookup';

export async function renderRouteOgPng(
	id: string,
	config: SharedRouteLookupConfig | null,
): Promise<Buffer> {
	const lookup = await lookupSharedRoute(id, config);
	return renderOgPng('route', () =>
		buildRouteOgSvg({
			name: lookup.route?.name,
			distance_m: lookup.route?.distance_m,
			official_distance_m: lookup.route?.official_distance_m,
			surface: lookup.route?.surface,
			track: lookup.track,
		}),
	);
}

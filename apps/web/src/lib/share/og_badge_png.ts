/// Request-time PNG renderer for /og/badge/<id>.png. Shared by the production
/// share-badge Lambda and the SvelteKit endpoint so the SVG card + the
/// missing-badge fallback behave identically in dev and prod.
///
/// A badge that doesn't resolve (private, deleted, never existed) renders a
/// generic branded card rather than throwing — the caller returns it with HTTP
/// 200 so a social unfurl never shows a broken image.

import { buildBadgeOgSvg } from './og_badge_image';
import { renderOgPng } from './og_png_render';
import { lookupSharedBadge, type SharedBadgeLookupConfig } from './share_badge_lookup';

export async function renderBadgeOgPng(
	id: string,
	config: SharedBadgeLookupConfig | null,
): Promise<Buffer> {
	const lookup = await lookupSharedBadge(id, config);
	return renderOgPng('badge', () =>
		buildBadgeOgSvg({
			badge_key: lookup.badge?.badge_key,
			tier: lookup.badge?.tier,
			earned_at: lookup.badge?.earned_at,
			displayName: lookup.displayName,
		}),
	);
}

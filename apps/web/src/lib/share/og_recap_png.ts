/// Request-time PNG renderer for /og/recap/<id>.png. Shared by the
/// production share-recap Lambda (apps/web/lambda/share-recap/src/index.ts)
/// and the SvelteKit endpoint (apps/web/src/routes/og/recap/[id].png/
/// +server.ts) so the SVG card + the missing-recap fallback behave
/// identically in dev and prod.
///
/// A recap that doesn't resolve (never published, revoked, or never existed)
/// renders a generic branded card rather than throwing — the caller returns
/// it with HTTP 200 so a social unfurl never shows a broken image.

import { buildRecapOgSvg } from './og_recap_image';
import { renderOgPng } from './og_png_render';
import {
	lookupSharedRecap,
	recapPeriodLabel,
	type SharedRecapLookupConfig,
} from './share_recap_lookup';

export async function renderRecapOgPng(
	id: string,
	config: SharedRecapLookupConfig | null,
): Promise<Buffer> {
	const { recap } = await lookupSharedRecap(id, config);
	return renderOgPng('recap', () => {
		const snap = recap?.snapshot ?? {};
		return buildRecapOgSvg({
			year: snap.year,
			month: snap.month,
			totalDistanceM: snap.totalDistanceM,
			runCount: snap.runCount,
			longestRunM: snap.longestRunM,
			bestStreakDays: snap.bestStreakDays,
			topWeekDistanceM: snap.topWeek?.distanceM ?? null,
			totalElevationM: snap.totalElevationM,
			displayName: recap?.displayName ?? null,
			periodLabel: recap ? recapPeriodLabel(recap.periodKind, recap.periodKey) : null,
		});
	});
}

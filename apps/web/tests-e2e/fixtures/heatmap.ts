import type { Page } from '@playwright/test';

/**
 * The only way an e2e spec moves the `/routes/heatmap` camera.
 *
 * The page frames itself once after load — a geolocation fix, or (in CI,
 * where geolocation is denied) a `fitBounds` over every discoverable route
 * that first awaits a fetch and then animates for 600 ms. A spec that sleeps
 * a fixed time and then calls `flyTo` races that framing. When the framing
 * lands second it interrupts the spec's flight, which fires `moveend` at
 * once; a spec that resolves on that `moveend` then reads the camera
 * mid-flight, at the framing's zoom (~4), where every Denver seed route is
 * one cluster. Issue #1196 was this in `heatmap-pins.spec.ts`; main run
 * 40385384518 was the same race in `heatmap-filters.spec.ts`, where the
 * cursor landed on the 12-route Denver cluster instead of the 3-route Wash
 * Park one. `heatmap_camera_guard.test.ts` keeps every spec on these helpers.
 */

export type HeatmapLayer =
	| 'heatmap-clubs-layer'
	| 'heatmap-route-pins-layer'
	| 'heatmap-route-pins-cluster';

type MapHandle = {
	jumpTo: (o: { center: [number, number]; zoom: number }) => void;
	project: (lngLat: [number, number]) => { x: number; y: number };
	getContainer: () => HTMLElement;
	loaded: () => boolean;
	isMoving: () => boolean;
	queryRenderedFeatures: (
		point: [number, number],
		opts?: { layers?: string[] },
	) => Array<{ properties?: { id?: string }; geometry: { coordinates: unknown } }>;
};
type HeatmapHooks = { __heatmapMap?: MapHandle; __heatmapPinsSettled?: () => boolean };

/** Wait until the page has framed itself and no pin refresh is still owed. */
export async function waitForHeatmapSettled(page: Page) {
	await page.waitForFunction(
		() => {
			const w = window as unknown as HeatmapHooks;
			const m = w.__heatmapMap;
			return !!m && !!w.__heatmapPinsSettled?.() && m.loaded() && !m.isMoving();
		},
		undefined,
		{ timeout: 15_000 },
	);
}

/**
 * Jump the camera to `center` once the page has finished framing itself,
 * then wait until that move's own pin refresh has landed and rendered.
 * `jumpTo`, not an animated move: there is nothing to watch, and an
 * animation is one more thing for the next action to race.
 */
export async function jumpAndSettle(page: Page, center: [number, number], zoom: number) {
	await waitForHeatmapSettled(page);
	await page.evaluate(
		([lng, lat, z]) => {
			(window as unknown as HeatmapHooks).__heatmapMap!.jumpTo({ center: [lng, lat], zoom: z });
		},
		[center[0], center[1], zoom] as const,
	);
	await waitForHeatmapSettled(page);
}

/**
 * Put the camera on `target` at `zoom` and return its viewport pixel once a
 * feature of `layer` is rendered exactly there, on the settled camera. The
 * caller drives a real pointer event at it — MapLibre's layer handlers only
 * fire under one. `single` additionally requires exactly one feature id under
 * the point, for a click the route-pin handler would otherwise hand to the
 * overlap list.
 */
export async function settleOnFeature(
	page: Page,
	target: [number, number],
	zoom: number,
	layer: HeatmapLayer,
	{ single = false }: { single?: boolean } = {},
) {
	await jumpAndSettle(page, target, zoom);
	const handle = await page.waitForFunction(
		({ lng, lat, layer, single }) => {
			const w = window as unknown as HeatmapHooks;
			const m = w.__heatmapMap;
			if (!m || !w.__heatmapPinsSettled?.() || !m.loaded() || m.isMoving()) return null;
			const pt = m.project([lng, lat]);
			const hits = m.queryRenderedFeatures([pt.x, pt.y], { layers: [layer] });
			const onTarget = hits.some((h) => {
				const [x, y] = h.geometry.coordinates as [number, number];
				return Math.abs(x - lng) < 1e-4 && Math.abs(y - lat) < 1e-4;
			});
			if (!onTarget) return null;
			if (single && new Set(hits.map((h) => h.properties?.id)).size !== 1) return null;
			const rect = m.getContainer().getBoundingClientRect();
			return { x: rect.left + pt.x, y: rect.top + pt.y };
		},
		{ lng: target[0], lat: target[1], layer, single },
		{ timeout: 15_000 },
	);
	return (await handle.jsonValue()) as { x: number; y: number };
}

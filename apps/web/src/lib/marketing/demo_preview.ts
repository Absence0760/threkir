import type { TrackPoint } from '$lib/types';

/// Static demo data for the public landing page's product preview.
///
/// The preview renders through the app's OWN components — `TrackPreview`
/// draws this polyline exactly as it draws a real run on /runs — so the
/// marketing page cannot drift away from what the product actually looks
/// like, the way a committed screenshot does the moment the UI moves. That
/// is the whole reason this is data and not a PNG.
///
/// The numbers are illustrative rather than one person's recorded result,
/// and the page labels them as a sample.

/// A closed park loop. Deterministic (an ellipse warped by two harmonics),
/// not a recording, so it carries no real person's location.
export const DEMO_TRACK: TrackPoint[] = [
	{ lat: 51.50740, lng: -0.12968 },
	{ lat: 51.50806, lng: -0.12950 },
	{ lat: 51.50871, lng: -0.12977 },
	{ lat: 51.50938, lng: -0.12990 },
	{ lat: 51.51006, lng: -0.13010 },
	{ lat: 51.51073, lng: -0.13045 },
	{ lat: 51.51142, lng: -0.13084 },
	{ lat: 51.51195, lng: -0.13171 },
	{ lat: 51.51239, lng: -0.13275 },
	{ lat: 51.51259, lng: -0.13410 },
	{ lat: 51.51267, lng: -0.13547 },
	{ lat: 51.51250, lng: -0.13694 },
	{ lat: 51.51207, lng: -0.13842 },
	{ lat: 51.51182, lng: -0.13951 },
	{ lat: 51.51164, lng: -0.14044 },
	{ lat: 51.51161, lng: -0.14123 },
	{ lat: 51.51171, lng: -0.14200 },
	{ lat: 51.51221, lng: -0.14288 },
	{ lat: 51.51276, lng: -0.14398 },
	{ lat: 51.51335, lng: -0.14535 },
	{ lat: 51.51385, lng: -0.14696 },
	{ lat: 51.51410, lng: -0.14864 },
	{ lat: 51.51405, lng: -0.15024 },
	{ lat: 51.51361, lng: -0.15145 },
	{ lat: 51.51295, lng: -0.15230 },
	{ lat: 51.51215, lng: -0.15274 },
	{ lat: 51.51132, lng: -0.15288 },
	{ lat: 51.51053, lng: -0.15287 },
	{ lat: 51.50974, lng: -0.15248 },
	{ lat: 51.50914, lng: -0.15264 },
	{ lat: 51.50851, lng: -0.15238 },
	{ lat: 51.50796, lng: -0.15256 },
	{ lat: 51.50740, lng: -0.15261 },
	{ lat: 51.50684, lng: -0.15245 },
	{ lat: 51.50628, lng: -0.15240 },
	{ lat: 51.50579, lng: -0.15186 },
	{ lat: 51.50531, lng: -0.15138 },
	{ lat: 51.50493, lng: -0.15056 },
	{ lat: 51.50456, lng: -0.14989 },
	{ lat: 51.50418, lng: -0.14927 },
	{ lat: 51.50368, lng: -0.14890 },
	{ lat: 51.50310, lng: -0.14854 },
	{ lat: 51.50236, lng: -0.14824 },
	{ lat: 51.50143, lng: -0.14792 },
	{ lat: 51.50058, lng: -0.14724 },
	{ lat: 51.49998, lng: -0.14618 },
	{ lat: 51.49935, lng: -0.14497 },
	{ lat: 51.49912, lng: -0.14351 },
	{ lat: 51.49929, lng: -0.14200 },
	{ lat: 51.49995, lng: -0.14064 },
	{ lat: 51.50064, lng: -0.13950 },
	{ lat: 51.50149, lng: -0.13867 },
	{ lat: 51.50241, lng: -0.13817 },
	{ lat: 51.50320, lng: -0.13783 },
	{ lat: 51.50370, lng: -0.13741 },
	{ lat: 51.50396, lng: -0.13676 },
	{ lat: 51.50423, lng: -0.13613 },
	{ lat: 51.50426, lng: -0.13490 },
	{ lat: 51.50447, lng: -0.13386 },
	{ lat: 51.50466, lng: -0.13249 },
	{ lat: 51.50500, lng: -0.13124 },
	{ lat: 51.50550, lng: -0.13038 },
	{ lat: 51.50612, lng: -0.13003 },
	{ lat: 51.50674, lng: -0.12966 },
	{ lat: 51.50740, lng: -0.12968 },
];

export type DemoSplit = {
	/// 1-indexed kilometre.
	km: number;
	/// Seconds taken for that kilometre.
	seconds: number;
};

/// Eight kilometre splits with a negative-split shape — a quick opener, a
/// settled middle, then a push. Drawn as a bar chart in the preview.
export const DEMO_SPLITS: DemoSplit[] = [
	{ km: 1, seconds: 311 },
	{ km: 2, seconds: 304 },
	{ km: 3, seconds: 298 },
	{ km: 4, seconds: 301 },
	{ km: 5, seconds: 295 },
	{ km: 6, seconds: 289 },
	{ km: 7, seconds: 284 },
	{ km: 8, seconds: 272 },
];

/// Share of time in each of the five heart-rate zones, as whole percentages.
export const DEMO_HR_ZONES: number[] = [8, 21, 38, 24, 9];

/// Heart rate through the run, one reading a minute across the 39:54, in bpm.
/// Generated, not recorded: a warm-up climb, a steady middle with a small
/// wander, and the late rise the negative split above implies. It lives apart
/// from DEMO_TRACK, whose points must never look like captured telemetry.
export const DEMO_HEART_RATE: number[] = [
	118, 130, 135, 140, 141, 140, 145, 146, 148, 150, 147, 147, 146, 145, 149, 150, 149, 150,
	146, 145, 148, 147, 150, 151, 148, 148, 146, 146, 149, 149, 150, 152, 150, 154, 156, 159,
	165, 167, 167, 170,
];

/// Elevation around the loop, one reading every quarter kilometre, in metres.
/// A gentle park profile; it starts and ends at the same height because the
/// route is a closed loop.
export const DEMO_ELEVATION: number[] = [
	33, 36, 36, 34, 30, 29, 29, 30, 30, 29, 28, 28, 29, 29, 27, 22, 16, 13, 12, 13, 14, 14, 15,
	17, 20, 23, 24, 22, 20, 19, 22, 25, 33,
];

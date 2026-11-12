import type { Climb } from '#lib/routes/course_climbs.ts';

/// Where the flyover video's overlays sit in its 1080x1920 frame, and what
/// they say. The text is formatted by the caller with the same formatters the
/// dialog uses (`formatDistance`, `formatElevation`, its climb label), so the
/// video never disagrees with the page; this module only places it.
///
/// The top and bottom bands a story viewer covers with its own UI hold
/// nothing load-bearing: the title sits below the top band, and the
/// attribution, which must stay in frame for the tile licences, sits above the
/// bottom one.

export interface TextSlot {
	x: number;
	y: number;
	size: number;
	maxWidth: number;
}

export interface VideoOverlayLayout {
	width: number;
	height: number;
	topScrim: number;
	bottomScrim: number;
	title: TextSlot;
	distance: TextSlot;
	distanceLabel: TextSlot;
	elevation: TextSlot;
	climb: TextSlot;
	strip: { x: number; y: number; w: number; h: number };
	attribution: TextSlot;
	mark: { x: number; y: number; size: number };
	end: { mark: { x: number; y: number; size: number }; wordmark: TextSlot; lines: TextSlot[]; url: TextSlot };
}

export const STORY_SAFE_TOP = 250;
export const STORY_SAFE_BOTTOM = 280;

export function videoOverlayLayout(width: number, height: number): VideoOverlayLayout {
	const pad = 64;
	const inner = width - pad * 2;
	const stripH = 140;
	const stripY = height - STORY_SAFE_BOTTOM - stripH - 72;
	const attributionY = height - STORY_SAFE_BOTTOM + 8;
	const statsY = stripY - 56;
	const centre = height / 2;
	return {
		width,
		height,
		topScrim: STORY_SAFE_TOP + 260,
		bottomScrim: height - (statsY - 150),
		title: { x: pad, y: STORY_SAFE_TOP + 64, size: 52, maxWidth: inner - 120 },
		mark: { x: width - pad - 88, y: STORY_SAFE_TOP + 8, size: 88 },
		distance: { x: pad, y: statsY, size: 112, maxWidth: inner * 0.62 },
		distanceLabel: { x: pad, y: statsY - 124, size: 34, maxWidth: inner * 0.62 },
		elevation: { x: width - pad, y: statsY, size: 64, maxWidth: inner * 0.36 },
		climb: { x: pad, y: STORY_SAFE_TOP + 140, size: 38, maxWidth: inner },
		strip: { x: pad, y: stripY, w: inner, h: stripH },
		attribution: { x: pad, y: attributionY, size: 24, maxWidth: inner },
		end: {
			mark: { x: (width - 220) / 2, y: centre - 420, size: 220 },
			wordmark: { x: width / 2, y: centre - 110, size: 96, maxWidth: inner },
			lines: [
				{ x: width / 2, y: centre + 40, size: 64, maxWidth: inner },
				{ x: width / 2, y: centre + 130, size: 44, maxWidth: inner },
			],
			url: { x: width / 2, y: centre + 300, size: 48, maxWidth: inner },
		},
	};
}

/// The climb the flight is on at `dM`, or -1 between climbs.
export function climbIndexAt(climbs: readonly Climb[], dM: number): number {
	return climbs.findIndex((c) => dM >= c.startM && dM <= c.endM);
}

const ENTITIES: Record<string, string> = {
	'&copy;': '©',
	'&amp;': '&',
	'&lt;': '<',
	'&gt;': '>',
	'&quot;': '"',
	'&#39;': "'",
	'&nbsp;': ' ',
};

/// A tile source's HTML attribution as the plain line a video frame can print:
/// tags dropped, the handful of entities the styles use decoded, whitespace
/// collapsed.
export function attributionText(html: string): string {
	return html
		.replace(/<[^>]*>/g, ' ')
		.replace(/&[a-z#0-9]+;/gi, (e) => ENTITIES[e.toLowerCase()] ?? ' ')
		.replace(/\s+/g, ' ')
		.trim();
}

/// Every credit the frame owes, each once and in the order given: the basemap
/// style's sources first, then the terrain's.
export function videoAttribution(htmlCredits: readonly (string | null | undefined)[]): string {
	const seen = new Set<string>();
	const out: string[] = [];
	for (const html of htmlCredits) {
		if (!html) continue;
		const line = attributionText(html);
		if (!line || seen.has(line)) continue;
		seen.add(line);
		out.push(line);
	}
	return out.join(' · ');
}

/// The end card's alpha over the last flight frame: a quick fade in, then held.
export function endCardAlpha(progress: number): number {
	const p = Number.isFinite(progress) ? progress : 1;
	return Math.min(1, Math.max(0, p / 0.25));
}

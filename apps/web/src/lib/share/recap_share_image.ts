/// Client-side year-in-running share-card SVG builder. Unlike
/// `og_run_image.ts` (a build-time / Lambda OG unfurl for PUBLIC run
/// pages) the recap is personal data with no public URL, so this card
/// is rendered in the browser and handed to the OS share sheet or a
/// download — never served as an og:image. Pure string concatenation
/// so unit tests can pin the wire shape without a renderer, and so the
/// page can rasterise it to PNG via an offscreen canvas.

import type { YearInRunningRecap } from '../runs/recap';
import { OG_CARD_DARK } from './og_card_palette';
import { escapeXml } from '../util/html_escape';
import { DEFAULT_SITE_URL } from '../core/site_url';
import { recapCardLayout, recapCellOrigin, type RecapCardAspect } from './recap_card_layout';

const SITE = new URL(DEFAULT_SITE_URL).host;

const BG = OG_CARD_DARK.bg;
const BRAND = OG_CARD_DARK.brand;
const HERO_FILL = OG_CARD_DARK.hero;
const LABEL_FILL = OG_CARD_DARK.label;
const STAT_FILL = OG_CARD_DARK.stat;

function fmtDistance(meters: number, unit: 'km' | 'mi'): string {
	if (unit === 'mi') return `${(meters / 1609.344).toFixed(0)} mi`;
	return `${(meters / 1000).toFixed(0)} km`;
}

function fmtDuration(seconds: number): string {
	const h = Math.floor(seconds / 3600);
	const m = Math.floor((seconds % 3600) / 60);
	if (h > 0) return `${h}h ${m}m`;
	return `${m}m`;
}

// The recap card is rendered in the viewer's own browser (offscreen
// canvas → PNG), never served as a shared og:image, so it should follow
// the runtime locale for grouped numbers rather than pinning en-US.
// `navigator.language` when available, `undefined` (host default) when
// running under the unit-test harness.
function localeNumber(n: number): string {
	const locale = typeof navigator !== 'undefined' ? navigator.language : undefined;
	return new Intl.NumberFormat(locale).format(n);
}

type StatCell = { label: string; value: string };

function statCells(recap: YearInRunningRecap, unit: 'km' | 'mi'): StatCell[] {
	const activeMonths = recap.monthly.filter((m) => m.runCount > 0).length;
	return [
		{ label: 'Longest run', value: fmtDistance(recap.longestRunM, unit) },
		{ label: 'On foot', value: fmtDuration(recap.totalDurationS) },
		{ label: 'Best streak', value: `${recap.bestStreakDays} days` },
		{
			label: 'Top week',
			value: fmtDistance(recap.topWeek?.distanceM ?? 0, unit),
		},
		{
			label: 'Climbed',
			value: `${localeNumber(Math.round(recap.totalElevationM))} m`,
		},
		{
			label: 'Active months',
			value: `${activeMonths} / 12`,
		},
	];
}

/// Build the share-card SVG for a year-in-running recap: a 1080x1080 square
/// by default, or a 1080x1920 story with `aspect: 'story'`. The page
/// rasterises it to PNG before sharing / downloading. Pass `periodLabel`
/// (e.g. "March 2026") to render a monthly card; omit it for the annual
/// card, which uses the year.
export function buildRecapShareSvg(
	recap: YearInRunningRecap,
	unit: 'km' | 'mi',
	periodLabel?: string,
	opts: { aspect?: RecapCardAspect } = {},
): string {
	const L = recapCardLayout(opts.aspect ?? 'square');
	const F = 'system-ui,-apple-system,Segoe UI,Roboto,sans-serif';
	const parts: string[] = [];
	parts.push(
		`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${L.width} ${L.height}" width="${L.width}" height="${L.height}">`,
	);
	parts.push(`<rect width="${L.width}" height="${L.height}" fill="${BG}"/>`);

	parts.push(
		`<text x="${L.pad}" y="${L.brandY}" font-family="${F}" font-size="40" font-weight="800" fill="${BRAND}">Threkir</text>`,
	);

	const kickerPeriod = (periodLabel ?? String(recap.year)).toUpperCase();
	parts.push(
		`<text x="${L.pad}" y="${L.kickerY}" font-family="${F}" font-size="34" font-weight="700" fill="${LABEL_FILL}" letter-spacing="3">MY ${escapeXml(kickerPeriod)} IN RUNNING</text>`,
	);

	parts.push(
		`<text x="${L.pad}" y="${L.heroY}" font-family="${F}" font-size="200" font-weight="900" fill="${HERO_FILL}">${escapeXml(fmtDistance(recap.totalDistanceM, unit))}</text>`,
	);

	const runWord = recap.runCount === 1 ? 'run' : 'runs';
	parts.push(
		`<text x="${L.pad}" y="${L.subheadY}" font-family="${F}" font-size="44" font-weight="600" fill="${STAT_FILL}">across ${recap.runCount} ${runWord}</text>`,
	);

	statCells(recap, unit).forEach((cell, i) => {
		const o = recapCellOrigin(L, i);
		parts.push(
			`<text x="${o.x}" y="${o.labelY}" font-family="${F}" font-size="28" font-weight="700" fill="${LABEL_FILL}" letter-spacing="2">${escapeXml(cell.label.toUpperCase())}</text>`,
		);
		parts.push(
			`<text x="${o.x}" y="${o.valueY}" font-family="${F}" font-size="64" font-weight="800" fill="${STAT_FILL}">${escapeXml(cell.value)}</text>`,
		);
	});

	if (L.footerY !== null) {
		parts.push(
			`<text x="${L.pad}" y="${L.footerY}" font-family="${F}" font-size="36" font-weight="700" fill="${BRAND}">${SITE}</text>`,
		);
	}

	parts.push('</svg>');
	return parts.join('');
}

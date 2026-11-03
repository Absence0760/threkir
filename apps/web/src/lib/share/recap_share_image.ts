/// Client-side year-in-running share-card SVG builder. Unlike
/// `og_run_image.ts` (a build-time / Lambda OG unfurl for PUBLIC run
/// pages) the recap is personal data with no public URL, so this card
/// is rendered in the browser and handed to the OS share sheet or a
/// download — never served as an og:image. Pure string concatenation
/// so unit tests can pin the wire shape without a renderer, and so the
/// page can rasterise it to PNG via an offscreen canvas.

import { OG_CARD_DARK } from './og_card_palette';
import { escapeXml } from '../util/html_escape';
import { recapCardLayout, recapCellOrigin, type RecapCardAspect } from './recap_card_layout';
import type { RecapCardText } from './recap_card_text';

const BG = OG_CARD_DARK.bg;
const BRAND = OG_CARD_DARK.brand;
const HERO_FILL = OG_CARD_DARK.hero;
const LABEL_FILL = OG_CARD_DARK.label;
const STAT_FILL = OG_CARD_DARK.stat;

/// Build the share-card SVG for a recap from its already-localised text
/// (`recapCardText`): a 1080x1080 square by default, or a 1080x1920 story with
/// `aspect: 'story'`. The page rasterises it to PNG before sharing /
/// downloading.
export function buildRecapShareSvg(text: RecapCardText, opts: { aspect?: RecapCardAspect } = {}): string {
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

	parts.push(
		`<text x="${L.pad}" y="${L.kickerY}" font-family="${F}" font-size="34" font-weight="700" fill="${LABEL_FILL}" letter-spacing="3">${escapeXml(text.kicker)}</text>`,
	);

	parts.push(
		`<text x="${L.pad}" y="${L.heroY}" font-family="${F}" font-size="200" font-weight="900" fill="${HERO_FILL}">${escapeXml(text.hero)}</text>`,
	);

	parts.push(
		`<text x="${L.pad}" y="${L.subheadY}" font-family="${F}" font-size="44" font-weight="600" fill="${STAT_FILL}">${escapeXml(text.subhead)}</text>`,
	);

	text.cells.forEach((cell, i) => {
		const o = recapCellOrigin(L, i);
		parts.push(
			`<text x="${o.x}" y="${o.labelY}" font-family="${F}" font-size="28" font-weight="700" fill="${LABEL_FILL}" letter-spacing="2">${escapeXml(cell.label.toLocaleUpperCase())}</text>`,
		);
		parts.push(
			`<text x="${o.x}" y="${o.valueY}" font-family="${F}" font-size="64" font-weight="800" fill="${STAT_FILL}">${escapeXml(cell.value)}</text>`,
		);
	});

	if (L.footerY !== null) {
		parts.push(
			`<text x="${L.pad}" y="${L.footerY}" font-family="${F}" font-size="36" font-weight="700" fill="${BRAND}">${escapeXml(text.footer)}</text>`,
		);
	}

	parts.push('</svg>');
	return parts.join('');
}

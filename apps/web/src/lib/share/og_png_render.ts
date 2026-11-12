/// The rasterising half every /og/<kind>/<id>.png renderer shares. An
/// og:image must be image bytes with HTTP 200 — a 5xx would unfurl as a
/// broken image — so a card that fails to build or rasterise (a malformed SVG,
/// a resvg failure) answers with a blank 1x1 PNG, and says so in the log, because a crawler caches whatever
/// it got and a silently blank card is otherwise invisible. Only the error's
/// message is logged: the card's inputs are a person's name and their run.

import { fileURLToPath } from 'node:url';

import { Resvg, type ResvgRenderOptions } from '@resvg/resvg-js';

import { thrownMessage } from '../core/supabase_error';
import { OG_FONT_DIR, OG_FONT_FAMILY, OG_FONT_FILES } from './og_card_font';

export const OG_FALLBACK_PNG = Buffer.from(
	'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
	'base64',
);

/// The only font configuration a share card is rasterised with. System fonts
/// stay off: the production Lambdas have none, so a card that leaned on them
/// would render with text locally and without it in prod. `OG_FONT_DIR` is
/// joined at run time rather than written as a `new URL` literal so no bundler
/// rewrites it into an emitted asset; esbuild leaves `import.meta.url` alone,
/// so in a share Lambda it is the bundle's own `index.mjs`.
export const OG_RESVG_FONT: NonNullable<ResvgRenderOptions['font']> = {
	loadSystemFonts: false,
	fontFiles: OG_FONT_FILES.map((name) => fileURLToPath(new URL(OG_FONT_DIR + name, import.meta.url))),
	defaultFontFamily: OG_FONT_FAMILY,
	sansSerifFamily: OG_FONT_FAMILY,
};

/// Everything resvg is constructed with for a card: the width every unfurl is
/// drawn at, and the bundled face.
export const OG_RESVG_OPTIONS: ResvgRenderOptions = {
	fitTo: { mode: 'width', value: 1200 },
	font: OG_RESVG_FONT,
};

export function renderOgPng(kind: string, buildSvg: () => string): Buffer {
	try {
		const resvg = new Resvg(buildSvg(), OG_RESVG_OPTIONS);
		return resvg.render().asPng();
	} catch (err) {
		console.error(`[og-${kind}] render failed`, thrownMessage(err));
		return OG_FALLBACK_PNG;
	}
}

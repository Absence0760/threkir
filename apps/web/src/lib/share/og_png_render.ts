/// The rasterising half every /og/<kind>/<id>.png renderer shares. An
/// og:image must be image bytes with HTTP 200 — a 5xx would unfurl as a
/// broken image — so a card that fails to build or rasterise (a malformed SVG,
/// a resvg failure) answers with a blank 1x1 PNG, and says so in the log, because a crawler caches whatever
/// it got and a silently blank card is otherwise invisible. Only the error's
/// message is logged: the card's inputs are a person's name and their run.

import { Resvg } from '@resvg/resvg-js';

import { thrownMessage } from '../core/supabase_error';

export const OG_FALLBACK_PNG = Buffer.from(
	'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
	'base64',
);

export function renderOgPng(kind: string, buildSvg: () => string): Buffer {
	try {
		const resvg = new Resvg(buildSvg(), {
			fitTo: { mode: 'width', value: 1200 },
			font: { loadSystemFonts: true },
		});
		return resvg.render().asPng();
	} catch (err) {
		console.error(`[og-${kind}] render failed`, thrownMessage(err));
		return OG_FALLBACK_PNG;
	}
}

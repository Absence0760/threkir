/// Request-time PNG renderer for /og/challenge/<id>.png. Shared by the
/// production share-entity Lambda and the SvelteKit endpoint so the card and
/// its missing-challenge fallback behave identically in dev and prod.
///
/// A challenge that does not resolve (private, deleted, never existed) renders
/// the generic branded card rather than throwing: an unfurl image must never
/// 404.

import { Resvg } from '@resvg/resvg-js';

import { buildChallengeOgSvg } from './og_challenge_image';
import {
	lookupSharedChallenge,
	type SharedChallengeLookupConfig,
} from './share_challenge_lookup';

const FALLBACK_PNG = Buffer.from(
	'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
	'base64',
);

export async function renderChallengeOgPng(
	id: string,
	config: SharedChallengeLookupConfig | null,
): Promise<Buffer> {
	const lookup = await lookupSharedChallenge(id, config);
	try {
		const svg = buildChallengeOgSvg({
			challenge: lookup.challenge,
			creatorName: lookup.creatorName,
		});
		const resvg = new Resvg(svg, {
			fitTo: { mode: 'width', value: 1200 },
			font: { loadSystemFonts: true },
		});
		return resvg.render().asPng();
	} catch (_) {
		return FALLBACK_PNG;
	}
}

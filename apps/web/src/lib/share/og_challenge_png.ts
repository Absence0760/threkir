/// Request-time PNG renderer for /og/challenge/<id>.png. Shared by the
/// production share-entity Lambda and the SvelteKit endpoint so the card and
/// its missing-challenge fallback behave identically in dev and prod.
///
/// A challenge that does not resolve (private, deleted, never existed) renders
/// the generic branded card rather than throwing: an unfurl image must never
/// 404.

import { buildChallengeOgSvg } from './og_challenge_image';
import { renderOgPng } from './og_png_render';
import {
	lookupSharedChallenge,
	type SharedChallengeLookupConfig,
} from './share_challenge_lookup';

export async function renderChallengeOgPng(
	id: string,
	config: SharedChallengeLookupConfig | null,
): Promise<Buffer> {
	const lookup = await lookupSharedChallenge(id, config);
	return renderOgPng('challenge', () =>
		buildChallengeOgSvg({
			challenge: lookup.challenge,
			creatorName: lookup.creatorName,
		}),
	);
}

/// Server-side challenge-share SVG builder for /og/challenge/[id].png. Pure
/// string concatenation so unit tests can pin the wire shape without the PNG
/// renderer.
///
/// The card carries the challenge's own fields, its participant count and the
/// creator's name as an anonymous reader may see it (null for a private
/// profile). The name gets its own line: on the date line it was always the
/// part the width clip cut. No participant name and nothing located: the board is one tap
/// away on the page, where the name rules apply per viewer.

import { escapeXml } from '../util/html_escape';
import { OG_CARD_LIGHT } from './og_card_palette';
import { OG_FONT_STACK } from './og_card_font';
import { clipToWidthPx } from './svg_text_width';
import { challengeGoalStable, challengeWindowStable } from './share_challenge_meta';
import type { SharedChallenge } from './share_challenge_lookup';
import { OG_GRISNIR_HEIGHT, grisnirBadgeSvg, grisnirBadgeWidth } from './grisnir_badge';

const W = 1200;
const H = 630;
const PAD = 56;
const FONT = OG_FONT_STACK;
/// Grisnir holds the bottom-right corner (the kicker has the top-right), so
/// the two attribution lines beside him stop short of him.
const GRISNIR_W = grisnirBadgeWidth(OG_GRISNIR_HEIGHT);
const FOOT_W = W - PAD * 2 - GRISNIR_W - 24;

export type ChallengeImageInput = {
	challenge: SharedChallenge | null;
	creatorName?: string | null;
};

export function buildChallengeOgSvg(input: ChallengeImageInput): string {
	const c = input.challenge;
	const parts: string[] = [];
	parts.push(
		`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}">`,
	);
	parts.push(`<rect width="${W}" height="${H}" fill="${OG_CARD_LIGHT.bg}"/>`);
	parts.push(`<rect width="${W}" height="12" fill="${OG_CARD_LIGHT.brand}"/>`);
	parts.push(
		`<text x="${PAD}" y="${PAD + 36}" font-family="${FONT}" font-size="30" font-weight="700" fill="${OG_CARD_LIGHT.brand}">Threkir</text>`,
	);
	parts.push(
		`<text x="${W - PAD}" y="${PAD + 36}" font-family="${FONT}" font-size="26" font-weight="600" fill="${OG_CARD_LIGHT.muted}" text-anchor="end">CHALLENGE</text>`,
	);

	const title = clipToWidthPx(c?.title?.trim() || 'Challenge', W - PAD * 2, 72);
	parts.push(
		`<text x="${PAD}" y="${H / 2 - 30}" font-family="${FONT}" font-size="72" font-weight="800" fill="${OG_CARD_LIGHT.ink}">${escapeXml(title)}</text>`,
	);

	const goal = c ? challengeGoalStable(c) : '';
	if (goal) {
		parts.push(
			`<text x="${PAD}" y="${H / 2 + 60}" font-family="${FONT}" font-size="56" font-weight="700" fill="${OG_CARD_LIGHT.brand}">${escapeXml(`Goal ${goal}`)}</text>`,
		);
	}

	const by = c && input.creatorName?.trim() ? `by ${input.creatorName.trim()}` : '';
	if (by) {
		parts.push(
			`<text x="${PAD}" y="${H - PAD - 48}" font-family="${FONT}" font-size="32" font-weight="600" fill="${OG_CARD_LIGHT.ink}">${escapeXml(clipToWidthPx(by, FOOT_W, 32))}</text>`,
		);
	}

	const sub = buildChallengeSubline(input);
	if (sub) {
		parts.push(
			`<text x="${PAD}" y="${H - PAD}" font-family="${FONT}" font-size="32" font-weight="500" fill="${OG_CARD_LIGHT.muted}">${escapeXml(clipToWidthPx(sub, FOOT_W, 32))}</text>`,
		);
	}
	parts.push(grisnirBadgeSvg(W - PAD - GRISNIR_W, H - PAD - OG_GRISNIR_HEIGHT + 8));
	parts.push('</svg>');
	return parts.join('');
}

export function buildChallengeSubline(input: ChallengeImageInput): string {
	const c = input.challenge;
	if (!c) return '';
	const joined =
		c.participant_count > 0
			? `${c.participant_count} ${c.participant_count === 1 ? 'runner' : 'runners'} in`
			: '';
	return [challengeWindowStable(c), joined].filter(Boolean).join(' · ');
}

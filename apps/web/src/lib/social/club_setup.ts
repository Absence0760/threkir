import { TEXT_LIMITS } from '../core/text_limits.ts';

export const CREATE_CLUB_GUIDE_ID = 'create-a-club';

export function prefilledClubName(raw: string | null | undefined): string {
	return Array.from((raw ?? '').trim()).slice(0, TEXT_LIMITS.clubName).join('').trim();
}

export function clubSetupHref(query: string | null | undefined): string {
	const name = prefilledClubName(query);
	return name ? `/clubs/new?name=${encodeURIComponent(name)}` : '/clubs/new';
}

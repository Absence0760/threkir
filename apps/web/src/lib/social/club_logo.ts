import { safeImageSrc } from '#lib/util/safe_image_src.ts';

/**
 * The `<img src>` for a club logo, or '' to fall back to the initial.
 *
 * Any https URL passes, as for every DB-sourced image. Beyond that, a URL is
 * accepted only when it is this project's own public club-logo path, which is
 * what lets the http-served local stack show the logos it stores: the scheme
 * then comes from the configured Supabase origin, not from the row.
 */
export function clubLogoSrc(
	url: string | null | undefined,
	supabaseOrigin: string | null | undefined,
): string {
	const safe = safeImageSrc(url);
	if (safe || !url || !supabaseOrigin) return safe;
	const origin = supabaseOrigin.trim().replace(/\/+$/, '');
	if (!/^https?:\/\/[^/]+$/i.test(origin)) return '';
	const trimmed = url.trim();
	return trimmed.startsWith(`${origin}/storage/v1/object/public/avatars/clubs/`) ? trimmed : '';
}

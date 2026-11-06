// The one place a platform's release status is written down. The landing
// page's platform strip and the note under it are both derived from this
// list, so flipping a platform to live (or adding its store listing) is a
// one-line change here rather than a hunt through copy.

import type { MessageKey } from '../i18n/messages';

export type PlatformStatus = 'live' | 'testing';

export interface Platform {
	readonly name: string;
	readonly status: PlatformStatus;
	/** Public store listing. Optional: a platform can be live before its URL is known. */
	readonly storeUrl?: string;
}

export type Translate = (key: MessageKey, params?: Record<string, string | number>) => string;

// iPhone and Apple Watch share one App Store listing (released 26 Oct 2026).
// Android and Wear OS stay in testing until Play grants production access (#1225).
export const PLATFORMS: readonly Platform[] = [
	{ name: 'Web', status: 'live' },
	{ name: 'Android', status: 'testing' },
	{ name: 'iOS', status: 'live', storeUrl: 'https://apps.apple.com/app/id6819364574' },
	{ name: 'Wear OS', status: 'testing' },
	{ name: 'Apple Watch', status: 'live', storeUrl: 'https://apps.apple.com/app/id6819364574' },
];

const STATUS_LABEL_KEY = {
	live: 'landing.platformLive',
	testing: 'landing.platformInTesting',
} as const satisfies Record<PlatformStatus, MessageKey>;

export function platformStatusLabelKey(platform: Platform): MessageKey {
	return STATUS_LABEL_KEY[platform.status];
}

export function isLive(platform: Platform): boolean {
	return platform.status === 'live';
}

/** The listing the status badge links to, or null when the badge is plain text. */
export function platformStoreHref(platform: Platform): string | null {
	return platform.storeUrl ?? null;
}

/**
 * The sentence under the strip naming every platform still in testing, or
 * null when none is — a fully released strip needs no caveat.
 */
export function platformsNote(
	platforms: readonly Platform[],
	locale: string,
	t: Translate,
): string | null {
	const testing = platforms.filter((p) => p.status === 'testing').map((p) => p.name);
	if (testing.length === 0) return null;
	const list = new Intl.ListFormat(locale, { style: 'long', type: 'conjunction' }).format(testing);
	return t('landing.platformsNote', { platforms: list, n: testing.length });
}

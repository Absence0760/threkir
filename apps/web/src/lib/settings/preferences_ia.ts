import type { MessageKey } from '../i18n/messages';

/// The preference pages `/settings/preferences` was split into (issue #905).
/// One list feeds the settings nav, the `/settings/preferences` landing page
/// and the reachability guard, so a page cannot be added to one and missed by
/// the others.
export interface PreferencesPage {
	href: string;
	icon: string;
	label: MessageKey;
	summary: MessageKey;
}

export const PREFERENCES_PAGES: readonly PreferencesPage[] = [
	{
		href: '/settings/display',
		icon: 'straighten',
		label: 'settingsLayout.tabDisplay',
		summary: 'prefsHub.displaySummary',
	},
	{
		href: '/settings/recording',
		icon: 'sprint',
		label: 'settingsLayout.tabRecording',
		summary: 'prefsHub.recordingSummary',
	},
	{
		href: '/settings/training',
		icon: 'monitor_heart',
		label: 'settingsLayout.tabTraining',
		summary: 'prefsHub.trainingSummary',
	},
	{
		href: '/settings/privacy',
		icon: 'lock',
		label: 'settingsLayout.tabPrivacy',
		summary: 'prefsHub.privacySummary',
	},
	{
		href: '/settings/notifications',
		icon: 'notifications',
		label: 'settingsLayout.tabNotifications',
		summary: 'prefsHub.notificationsSummary',
	},
];

/// Body metrics sits with the account under Profile rather than with the
/// preferences, but it was carved out of the same page, so the landing page
/// still offers it.
export const BODY_METRICS_PAGE: PreferencesPage = {
	href: '/settings/body',
	icon: 'weight',
	label: 'settingsLayout.tabBody',
	summary: 'prefsHub.bodySummary',
};

/// The section anchors the single page carried, and where each section lives
/// now. Emails, the coach chat, the dashboard and the nutrition pages all
/// deep-linked into them, and a link already sent cannot be edited.
export const LEGACY_PREFERENCES_ANCHORS: Readonly<Record<string, string>> = {
	'heart-rate-zones': '/settings/training#heart-rate-zones',
	'weekly-mileage-goal': '/settings/training#weekly-distance-goal',
	'body-metrics': '/settings/body#body-metrics',
};

/// Where an old `/settings/preferences#anchor` link should land, or null when
/// the hash names no section that moved.
export function legacyPreferencesTarget(hash: string): string | null {
	const anchor = hash.startsWith('#') ? hash.slice(1) : hash;
	return Object.hasOwn(LEGACY_PREFERENCES_ANCHORS, anchor)
		? LEGACY_PREFERENCES_ANCHORS[anchor]
		: null;
}

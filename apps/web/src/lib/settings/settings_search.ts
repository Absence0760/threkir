import type { MessageKey } from '../i18n/messages';
import { fold } from '../segments/catalogue_browse';

/// The settings search (issue #1374, decisions § 2494; the web twin of the
/// You tab's search on mobile). Each settings page and the titles of the rows
/// and sections it shows. A row result lands on the row itself, not the top of
/// its page: its href carries `#` + [settingRowId], the id the page puts on
/// that row, and `setting_focus.ts` scrolls it into view, focuses it and
/// highlights it. The pages render their own markup, so this index is kept
/// beside them by hand: `settings_search_index.test.ts` fails when a listed
/// title is no longer read by its page, when a listed row has no anchor on its
/// page, when a page heading is missing from it, or when a settings nav entry
/// has no index entry.
export interface SettingsSearchPage {
	href: string;
	/// The page's name in the settings nav; a result says which page it is on.
	label: MessageKey;
	rows: readonly MessageKey[];
}

export const SETTINGS_SEARCH_INDEX: readonly SettingsSearchPage[] = [
	{
		href: '/settings/account',
		label: 'settingsLayout.tabAccount',
		rows: [
			'settingsAccount.profileHeading',
			'settingsAccount.displayName',
			'settingsAccount.handleLabel',
			'settingsAccount.email',
			'settingsAccount.parkrunNumber',
			'settingsAccount.dateOfBirth',
			'settingsAccount.restingHr',
			'settingsAccount.maxHr',
			'settingsAccount.healthConsentLabel',
			'settingsAccount.cycleHeading',
			'settingsAccount.cycleMode',
			'settingsAccount.signinMethodsHeading',
			'settingsAccount.passwordHeading',
			'settingsAccount.safetyHeading',
			'settingsAccount.notificationsHeading',
			'settingsAccount.backupHeading',
			'settingsAccount.dataExportHeading',
			'settingsAccount.coachConsentHeading',
			'settingsAccount.signoutEverywhereHeading',
			'settingsAccount.deleteAccount',
		],
	},
	{
		href: '/settings/body',
		label: 'settingsLayout.tabBody',
		rows: [
			'prefs.demographicsHeading',
			'prefs.gender',
			'prefs.dateOfBirth',
			'prefs.heightCm',
			'prefs.weight',
			'prefs.nutritionTargetsHeading',
			'prefs.activityLevel',
			'prefs.weightGoal',
		],
	},
	{
		href: '/settings/safety',
		label: 'safety.navTab',
		rows: ['safety.addLabel', 'safety.overdueTitle', 'safety.offRouteTitle', 'safety.incomingTitle', 'safety.contactOfTitle'],
	},
	{
		href: '/settings/display',
		label: 'settingsLayout.tabDisplay',
		rows: [
			'prefs.languageThemeHeading',
			'prefs.language',
			'prefs.theme',
			'prefs.unitsHeading',
			'prefs.distanceUnit',
			'prefs.weightUnit',
			'prefs.paceFormat',
			'prefs.weekStartsOn',
			'prefs.mapsPagesHeading',
			'prefs.disclosureLevel',
			'prefs.mapStyle',
			'prefs.undoWindow',
			'prefs.showCalories',
			'prefs.showMascot',
			'prefs.messagesHeading',
			'prefs.coachInMessages',
			'prefs.modalitiesHeading',
			'prefs.showGym',
			'prefs.showNutrition',
			'prefs.homeCardsHeading',
		],
	},
	{
		href: '/settings/recording',
		label: 'settingsLayout.tabRecording',
		rows: [
			'prefs.startingRunHeading',
			'prefs.defaultActivity',
			'prefs.voiceFeedbackHeading',
			'prefs.spokenSplits',
			'prefs.cueDetail',
			'prefs.splitInterval',
			'prefs.splitPaceMode',
			'prefs.voiceCueTypes',
		],
	},
	{
		href: '/settings/training',
		label: 'settingsLayout.tabTraining',
		rows: [
			'prefs.weeklyGoalHeading',
			'prefs.weeklyDistanceGoal',
			'prefs.planRecoveryHeading',
			'prefs.extraRecovery',
			'prefs.heartRateZonesHeading',
			'prefs.restingHr',
			'prefs.maxHr',
			'prefs.hrMedicationAffected',
			'prefs.excludeGymFromReadiness',
			'prefs.raceFuelingHeading',
			'prefs.carbsPerHour',
			'prefs.fluidPerHour',
			'prefs.aiCoachHeading',
			'prefs.coachPersonality',
		],
	},
	{
		href: '/settings/privacy',
		label: 'settingsLayout.tabPrivacy',
		rows: [
			'prefs.yourRunsHeading',
			'prefs.defaultVisibility',
			'prefs.autoPushStrava',
			'prefs.beingFoundHeading',
			'prefs.privateProfile',
			'prefs.followRequestsLink',
			'prefs.showInSearch',
			'prefs.discoverableNearby',
			'prefs.nearbyAreaLabel',
			'prefs.messagesHeading',
			'prefs.readReceipts',
			'prefs.messageRequests',
			'prefs.privacyZonesHeading',
			'prefs.telemetryHeading',
			'prefs.telemetryConsent',
		],
	},
	{
		href: '/settings/notifications',
		label: 'settingsLayout.tabNotifications',
		rows: [
			'prefs.emailPushHeading',
			'prefs.emailNotifications',
			'prefs.pushNotifications',
			'prefs.notifyWorkoutReminder',
			'prefs.notifyRaceStartingSoon',
			'prefs.notifyMention',
			'prefs.notifyReaction',
			'prefs.notifyCommentLike',
			'prefs.notifyFollowRequest',
			'prefs.notifyEventRsvp',
			'prefs.notifyClubJoinRequest',
			'prefs.notifyClubJoinApproved',
			'prefs.notifyEventUpdated',
			'prefs.notifyCourseAlert',
			'prefs.notifyParkCourseMonth',
			'prefs.notifyDataExportReady',
			'prefs.optionalEmailsHeading',
			'prefs.emailNewDeviceAlerts',
			'prefs.emailWeeklyDigest',
			'prefs.emailLifecycleDrip',
		],
	},
	{
		href: '/settings/integrations',
		label: 'settingsLayout.tabIntegrations',
		rows: ['settingsIntegrations.availableHeading', 'settingsIntegrations.stravaBulkHeading', 'settingsIntegrations.garminBulkHeading'],
	},
	{
		href: '/settings/devices',
		label: 'settingsLayout.tabDevices',
		rows: ['settingsDevices.addOverride'],
	},
	{
		href: '/settings/gear',
		label: 'settingsLayout.tabGear',
		rows: ['settingsGear.tabShoes', 'settingsGear.tabBikes', 'settingsGear.retiredSection', 'settingsGear.rotationsHeading'],
	},
	{ href: '/settings/payouts', label: 'settingsLayout.tabPayouts', rows: ['payouts.earningsTitle'] },
	{ href: '/settings/shares', label: 'shares.tab', rows: [] },
	{ href: '/settings/upgrade', label: 'settingsLayout.tabProSupport', rows: ['upgrade.tierFree', 'upgrade.donateTitle'] },
	{ href: '/settings/licenses', label: 'settingsLayout.tabAbout', rows: [] },
];

/// The element id a page gives the row or section titled [key], and the
/// fragment a search result for it links to.
export function settingRowId(key: MessageKey): string {
	return `setting-${key.replace(/[^A-Za-z0-9_-]/g, '-')}`;
}

export interface SettingsSearchHit {
	title: string;
	/// The page the setting is on, by its nav name.
	where: string;
	/// The page, plus `#` and the row's [settingRowId] for a row result.
	href: string;
}

/// Titles that contain the query, accent- and case-folded: each page's own
/// name first (linking to the page), then its rows (linking to the row), in
/// index order. A title on one page is listed once. Only pages in `available`
/// are searched, so a page the nav hides is never offered. A blank query
/// matches nothing.
export function searchSettings(
	query: string,
	t: (key: MessageKey) => string,
	available: ReadonlySet<string>,
): SettingsSearchHit[] {
	const q = fold(query.trim());
	if (q === '') return [];
	const hits: SettingsSearchHit[] = [];
	for (const page of SETTINGS_SEARCH_INDEX) {
		if (!available.has(page.href)) continue;
		const where = t(page.label);
		const seen = new Set<string>();
		const entries = [
			{ title: where, href: page.href },
			...page.rows.map((k) => ({ title: t(k), href: `${page.href}#${settingRowId(k)}` })),
		];
		for (const { title, href } of entries) {
			if (seen.has(title) || !fold(title).includes(q)) continue;
			seen.add(title);
			hits.push({ title, where, href });
		}
	}
	return hits;
}

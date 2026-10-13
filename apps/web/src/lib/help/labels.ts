// The catalogue key for every value a guide's metadata can take, so the help
// pages' chrome is translated even while guide text is English-only.

import type { MessageKey } from '#lib/i18n/messages.ts';
import type { Audience, GuideCategory, GuideKind, Platform, Requirement } from './types';

export const CATEGORY_LABEL: Record<GuideCategory, MessageKey> = {
	running: 'help.categoryRunning',
	races: 'help.categoryRaces',
	clubs: 'help.categoryClubs',
	'paid-classes': 'help.categoryPaidClasses',
	instructors: 'help.categoryInstructors',
	account: 'help.categoryAccount',
};

export const KIND_LABEL: Record<GuideKind, MessageKey> = {
	start: 'help.kindStart',
	'how-to': 'help.kindHowTo',
	explainer: 'help.kindExplainer',
};

export const AUDIENCE_LABEL: Record<Audience, MessageKey> = {
	everyone: 'help.audienceEveryone',
	runner: 'help.audienceRunner',
	organiser: 'help.audienceOrganiser',
	participant: 'help.audienceParticipant',
	spectator: 'help.audienceSpectator',
	instructor: 'help.audienceInstructor',
	'club-admin': 'help.audienceClubAdmin',
};

export const PLATFORM_LABEL: Record<Platform, MessageKey> = {
	web: 'help.platformWeb',
	android: 'help.platformAndroid',
	ios: 'help.platformIos',
	wear: 'help.platformWear',
	'apple-watch': 'help.platformAppleWatch',
};

export const REQUIREMENT_LABEL: Record<Requirement, MessageKey> = {
	pro: 'help.requiresPro',
	'club-admin': 'help.requiresClubAdmin',
	'race-director': 'help.requiresRaceDirector',
	'stripe-connected': 'help.requiresStripeConnected',
	'paid-rail-live': 'help.requiresPaidRailLive',
};

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { en } from './locales/en';

// A count written into English as `{n} days` renders "1 days" for one, and
// every translation copies the same shape. The count belongs in an ICU
// plural (`{n, plural, one {# day} other {# days}}`), which interpolate()
// resolves with Intl.PluralRules for the reader's locale (decisions § 2497,
// § 2507). `plansPage.metaWeeks` pluralised the weeks and left "{days}
// days/week" outside the plural, and `settingsAccount.restoreResult` said
// "Restored 1 runs". This fails a placeholder standing before an English
// plural noun outside a plural block. The mobile twin is
// apps/mobile_android/test/count_noun_guard_test.dart.
//
// Not counts: a placeholder that holds a name, date, distance or other text,
// read from its name; a number used as a label ("Week {n} runs again", "Race
// {n} needs"); and a word ending in s that is not a plural noun.

const NOT_A_COUNT = /^(name|date|start|end|club|clubName|plan|plans|race|races|term|event|source|status|label|title|distance|amount|list|query|time|pace)$/;
const NOT_A_NOUN = new Set([
	'is', 'has', 'was', 'as', 'across', 'says', 'wants', 'sees', 'asks', 'falls', 'ends', 'becomes', 'needs', 'crowns', 'scores',
]);
const LABEL_BEFORE = /\b(Week|Race|Step|Lap|Loop|Stage|Day)\s*$/;

// A placeholder that can never hold 1: a fixed limit above 1, named with its
// constant. The list may only shrink.
const NEVER_ONE: Record<string, string> = {
	'login.errorPasswordTooShort min': 'PASSWORD_MIN_LENGTH, 8',
	'login.errorWeakPassword min': 'PASSWORD_MIN_LENGTH, 8',
	'settingsAccount.passwordTooShort min': 'PASSWORD_MIN_LENGTH, 8',
	'authReset.errorTooShort min': 'PASSWORD_MIN_LENGTH, 8',
	'authReset.hint min': 'PASSWORD_MIN_LENGTH, 8',
	'eventEditor.courseNameTooLong max': 'COURSE_NAME_MAX, 120',
	'coachShare.tooLong max': 'COACH_SHARE_MAX_CHARS, 4000',
	'planImport.raceNameTooLong max': 'RACE_NAME_MAX in plan_serialize.ts, 120',
	'runEditor.durationTooLong hours': 'MAX_RUN_DURATION_S / 3600, 240',
	'workoutEditor.raceGoalInvalid max': 'RACE_GOAL_MAX_HOURS, 999',
	'features.aiCoach.description free': 'TIER_LIMITS.free.dailyLimit, 2',
};

// Counts still written into English. Each is owed an ICU plural in all
// seven locales; the list may only shrink.
const OWED = new Set<string>([
	'coachChat.messagesRemaining total',
	'planDetail.raceInDays d',
	'planDetail.namedRaceInDays d',
	'planDetail.shiftDone n',
	'planDetail.shiftConfirmMessage n',
	'planNudge.underBody total',
	'planNudge.restBody total',
	'planDetail.sectionWeeksHint n',
	'plansPage.daysToGo d',
	'profile.lastDays days',
	'profile.feedNoMatchesText days',
	'profile.feedNoActivityText days',
	'runShare.splitsHeading count',
	'settingsAccount.exportPartialNotice total',
	'settingsIntegrations.stravaConnected imported',
	'settingsIntegrations.stravaConnectedPartial imported',
	'settingsIntegrations.stravaConnectedPartialRateLimited imported',
	'settingsIntegrations.stravaZipImportDroppedPhotos photos',
	'clubHome.routineExerciseCount n',
	'coaching.roster.runsCount count',
	'coachingAthlete.assignAfterMany count',
	'importRoute.metaPts n',
	'planEditor.nDays n',
	'planEditor.returnBody weeks',
	'planMeta.daysCount n',
	'recap.shareDistance n',
	'roadbook.saveTargetsDone count',
	'roadbook.carryHint gels',
	'socialFeed.windowHint n',
	'socialFeed.noMatchesText n',
	'socialFeed.noActivityText n',
	'races.whenHint days',
	'races.emptyRecent days',
	'races.addToSeasonHint days',
	'notificationsList.nameAndOthers count',
	'notificationsList.andOthers count',
	'raceDayPanel.daysToGoMany n',
	'routeBuilder.routedSegments total',
	'trainingLoad.hintTrimp n',
	'nutrition.targets.ageYears n',
	'nutrition.weekProtein total',
	'nutrition.platePhotoSavePartial total',
	'nutrition.templateLogged n',
	'nutrition.templateItems n',
	'nutrition.recipeMeta n',
	'nutrition.recipeMeta servings',
	'safety.overdueMinutesOption minutes',
	'session.stepReps reps',
	'gym.draft.body sets',
	'admin.reports.reportCount count',
	'admin.reports.reporterCount count',
	'admin.reports.resolvedReviewed count',
	'admin.reports.resolvedDismissed count',
	'checkpoint.publicFinishers n',
	'challenges.startsIn n',
	'challenges.unitDays n',
	'fundraiser.donorCount count',
	'intensityBalance.counts weeks',
	'comeback.layoff weeks',
	'admin.clubVerification.members n',
]);

// The span and variable of every plural / select block in `s`. Inside one,
// its own variable agrees with the branch; any other placeholder is still a
// bare count (`plansPage.metaWeeks` pluralised the weeks, not "{days} days").
function blocks(s: string): { arg: string; start: number; end: number }[] {
	const out: { arg: string; start: number; end: number }[] = [];
	const open = /\{(\w+),\s*(?:plural|select|selectordinal),/g;
	for (let m = open.exec(s); m; m = open.exec(s)) {
		let depth = 0;
		let j = m.index;
		do {
			if (s[j] === '{') depth++;
			else if (s[j] === '}') depth--;
			j++;
		} while (j < s.length && depth > 0);
		out.push({ arg: m[1], start: m.index, end: j });
	}
	return out;
}

// `key placeholder` for each count placeholder standing before a plural noun.
function countsBeforeNouns(key: string, message: string): string[] {
	const spans = blocks(message);
	const hits: string[] = [];
	const re = /\{(\w+)\}\s+([a-z]+s)\b/g;
	for (let m = re.exec(message); m; m = re.exec(message)) {
		const [, arg, word] = m;
		if (NOT_A_COUNT.test(arg)) continue;
		if (spans.some((b) => b.arg === arg && b.start < m.index && m.index < b.end)) continue;
		if (NOT_A_NOUN.has(word)) continue;
		if (LABEL_BEFORE.test(message.slice(0, m.index))) continue;
		hits.push(`${key} ${arg}`);
	}
	return hits;
}

test('the scan reads a count before a plural noun, outside plurals only', () => {
	assert.deepEqual(countsBeforeNouns('k', 'Restored {runs} runs'), ['k runs']);
	assert.deepEqual(countsBeforeNouns('k', '{total, plural, one {# week · {days} days/week} other {# weeks · {days} days/week}}'), ['k days', 'k days']);
	for (const ok of [
		'{n, plural, one {# day} other {# days}}',
		'{n, plural, one {{n} day} other {{n} days}}',
		'{name} is here',
		'Week {n} runs again from {start}.',
		'Race {n} needs a name',
		'{distance} across {n, plural, one {# run} other {# runs}}',
		'{count} km',
	])
		assert.deepEqual(countsBeforeNouns('k', ok), [], ok);
});

const found = new Set(
	Object.entries(en as Record<string, string>).flatMap(([key, message]) => countsBeforeNouns(key, message)),
);

test('no English message writes a count before a plural noun outside a plural', () => {
	const offenders = [...found].filter((h) => !OWED.has(h) && !(h in NEVER_ONE)).sort();
	assert.deepEqual(
		offenders,
		[],
		'a count belongs in an ICU plural ({n, plural, one {# day} other {# days}}) in all seven locales',
	);
});

test('every OWED and NEVER_ONE entry is still needed', () => {
	for (const h of OWED) assert.ok(found.has(h), `${h} is no longer a bare count; drop it from OWED`);
	for (const [h, why] of Object.entries(NEVER_ONE)) {
		assert.ok(why.trim().length > 0, `${h}: name the constant`);
		assert.ok(found.has(h), `${h} is no longer a bare count; drop it from NEVER_ONE`);
		assert.ok(!OWED.has(h), `${h} is listed twice`);
	}
});

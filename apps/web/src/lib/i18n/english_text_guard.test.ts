// A module that hands a reader a sentence hands it in the reader's language.
// The words live in the catalogues (`locales/*.ts`); a pure helper returns a
// kind, an id or a number and the screen picks the message
// (`recoveryAdviceKind`, `computeReadiness().dominant`, the recap badge ids,
// `racePlanDescribe`'s translator). This scan counts the English prose left
// in string literals across `src/lib` (`english_text_scan.ts`) and fails on
// any file not listed below, or listed with a different count.
//
// Two lists, both exact:
//   ENGLISH_BY_DESIGN — text no reader of the app sees in their own language,
//     each with the reason. The share heads and OG cards are English on
//     purpose: they are served from the CloudFront cache keyed on the path
//     alone, to crawlers that send no reader's language (Googlebot crawls
//     without Accept-Language; Slack, iMessage and WhatsApp unfurl with the
//     server's), and Google's guidance is one language per URL rather than a
//     locale-adaptive page. Localising them would mean a URL per language with
//     hreflang alternates and a CJK font in the OG Lambdas (decisions § 205).
//     The page body under that head is rendered in the reader's language.
//   NOT_YET_LOCALISED — reader-facing English still to move to the catalogues.
//     It may only shrink.
//
// The mobile twin is apps/mobile_android/test/english_text_guard_test.dart.
// Invocation: npx tsx --test src/lib/i18n/english_text_guard.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';

import { englishCounts } from './english_text_scan';

const ROOT = resolve(import.meta.dirname, '..', '..', '..');

const SHARE_HEAD =
	'crawler-facing share head / OG card: one language per cached URL (see the header)';
const MODEL_PROMPT = 'a prompt or tool schema read by the model, not shown to the reader';

const ENGLISH_BY_DESIGN: Record<string, { count: number; reason: string }> = {
	'src/lib/share/share_badge_meta.ts': { count: 2, reason: SHARE_HEAD },
	'src/lib/share/share_challenge_meta.ts': { count: 1, reason: SHARE_HEAD },
	'src/lib/share/share_club_meta.ts': { count: 1, reason: SHARE_HEAD },
	'src/lib/share/share_course_meta.ts': { count: 1, reason: SHARE_HEAD },
	'src/lib/share/share_event_meta.ts': { count: 1, reason: SHARE_HEAD },
	'src/lib/share/share_meta.ts': { count: 5, reason: SHARE_HEAD },
	'src/lib/share/share_plan_meta.ts': { count: 3, reason: SHARE_HEAD },
	'src/lib/share/share_profile_meta.ts': { count: 1, reason: SHARE_HEAD },
	'src/lib/share/share_race_meta.ts': { count: 1, reason: SHARE_HEAD },
	'src/lib/share/share_recap_meta.ts': { count: 1, reason: SHARE_HEAD },
	'src/lib/share/share_session_meta.ts': { count: 4, reason: SHARE_HEAD },
	'src/lib/share/share_workout_meta.ts': { count: 4, reason: SHARE_HEAD },
	'src/lib/share/site_meta.ts': { count: 1, reason: SHARE_HEAD },
	'src/lib/parks/route_guide.ts': {
		count: 11,
		reason: "the route guide's canonical English for JSON-LD and the meta description (decisions § 2448); the page body lists it in the reader's language",
	},
	'src/lib/coach/assist/context.ts': { count: 2, reason: MODEL_PROMPT },
	'src/lib/coach/assist/handler.ts': { count: 3, reason: MODEL_PROMPT },
	'src/lib/coach/context.ts': { count: 3, reason: MODEL_PROMPT },
	'src/lib/coach/providers.ts': { count: 10, reason: 'the priming turns sent to the model with every Coach conversation' },
	'src/lib/coach/system_prompt.ts': { count: 1, reason: MODEL_PROMPT },
	'src/lib/nutrition/plate_photo/handler.ts': { count: 5, reason: MODEL_PROMPT },
	'src/lib/routes/route_describe/handler.ts': { count: 7, reason: MODEL_PROMPT },
	'src/lib/routes/route_request/handler.ts': { count: 8, reason: MODEL_PROMPT },
	'src/lib/training/plan_edit/handler.ts': { count: 8, reason: MODEL_PROMPT },
	'src/lib/training/plan_request/handler.ts': { count: 14, reason: MODEL_PROMPT },
	'src/lib/training/season_request/handler.ts': { count: 9, reason: MODEL_PROMPT },
	'src/lib/routes/geocoding.ts': { count: 1, reason: 'a server log line (multi-line, so the log filter does not see it)' },
	'src/lib/coach/handler.ts': { count: 3, reason: 'a log line and the 403 body of /api/coach; CoachChat maps every status to catalogue copy and never shows the body' },
	'src/lib/settings/settings_write.ts': { count: 1, reason: 'an Error message, rendered through errorCopy' },
	'src/lib/billing/revenuecat_links.ts': { count: 2, reason: 'operator config validation, reported at build time' },
	'src/lib/billing/donate_link.ts': { count: 1, reason: 'operator config validation, reported at build time' },
	'src/lib/legal/operator.ts': { count: 1, reason: "the operator's legal identity, quoted verbatim on the legal pages" },
	'src/lib/parks/park_courses.ts': { count: 6, reason: "place names and the National Park Service's attribution line, quoted as licensed" },
	'src/lib/components/course_preview/course_layers.ts': { count: 2, reason: 'map font names' },
	'src/lib/runs/finisher_certificate.ts': { count: 1, reason: 'a CSS font stack' },
	'src/lib/integrations/strava-zip-header.ts': { count: 1, reason: "a column header in Strava's export, matched as written" },
	'src/lib/integrations/import_failures.ts': { count: 1, reason: 'the header row of a CSV file other tools parse' },
	'src/lib/core/mock-data.ts': { count: 3, reason: 'demo data for the signed-out preview build' },
	'src/lib/parks/course_run_fixture.ts': { count: 1, reason: 'a test fixture' },
};

/// Reader-facing English still owed to the catalogues. May only shrink.
const NOT_YET_LOCALISED: Record<string, number> = {
	'src/lib/backup/backup_reader.ts': 4,
	'src/lib/core/data.ts': 4,
	'src/lib/core/supabase_error.ts': 1,
	'src/lib/integrations/import.ts': 1,
	'src/lib/learn/learn_meta.ts': 2,
	'src/lib/runs/event_results_csv.ts': 5,
	'src/lib/runs/race_day.ts': 5,
	'src/lib/segments/segments.ts': 1,
	'src/lib/settings/compare_features.ts': 11,
	'src/lib/training/plan_serialize.ts': 3,
	'src/lib/util/exif_strip.ts': 1,
	'src/lib/video/encode_video.ts': 1,
};

test('every module carrying English prose is accounted for, at its exact count', () => {
	const found = englishCounts(ROOT, resolve(ROOT, 'src/lib'));
	const problems: string[] = [];
	for (const [file, n] of found) {
		const want = ENGLISH_BY_DESIGN[file]?.count ?? NOT_YET_LOCALISED[file];
		if (want == null) problems.push(`${file}: ${n} English string(s) a reader would see — move them to the catalogues`);
		else if (n > want) problems.push(`${file}: ${n} English strings, ${want} allowed — move the new one(s) to the catalogues`);
		else if (n < want) problems.push(`${file}: ${n} English strings, ${want} listed — lower the count here`);
	}
	for (const file of [...Object.keys(ENGLISH_BY_DESIGN), ...Object.keys(NOT_YET_LOCALISED)]) {
		if (!found.has(file)) problems.push(`${file}: no English left — remove its entry`);
	}
	assert.deepEqual(problems, []);
});

test('the localised helpers stay free of English', () => {
	const found = englishCounts(ROOT, resolve(ROOT, 'src/lib'));
	for (const file of [
		'src/lib/runs/recap.ts',
		'src/lib/share/recap_card_text.ts',
		'src/lib/training/race_plan_prefill.ts',
		'src/lib/training/fitness.ts',
		'src/lib/training/readiness.ts',
		'src/lib/social/recurrence.ts',
	]) {
		assert.equal(found.get(file) ?? 0, 0, file);
	}
});

test('no file is both by design and owed', () => {
	const both = Object.keys(ENGLISH_BY_DESIGN).filter((f) => f in NOT_YET_LOCALISED);
	assert.deepEqual(both, []);
});

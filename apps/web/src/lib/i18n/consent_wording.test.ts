import { test } from 'node:test';
import assert from 'node:assert/strict';
import { messages as de } from './locales/de';

// In German, consent is Einwilligung / einwilligen and never zustimmen
// (decisions § 2527). The AI dialog's sentence once said „Indem du annimmst“
// against a button that read „Ich stimme zu“, because the rule was applied to
// one string and not its neighbours. Twin of the de case in
// apps/mobile_android/test/health_consent_wording_test.dart.

const GERMAN_AGREEING = /\bzustimm|\bstimm(?:e|st) zu\b|\bZustimmung|\bzugestimmt/i;

test('the German scan reads agreeing, not tailoring', () => {
	assert.match('Ich stimme zu', GERMAN_AGREEING);
	assert.match('Lies sie und stimme zu.', GERMAN_AGREEING);
	assert.match('Mit deiner Zustimmung', GERMAN_AGREEING);
	assert.match('noch nicht zugestimmt', GERMAN_AGREEING);
	assert.doesNotMatch('Ich willige ein', GERMAN_AGREEING);
	assert.doesNotMatch('auf dich abzustimmen', GERMAN_AGREEING);
});

test('no German consent message says zustimmen', () => {
	const offenders = Object.entries(de)
		.filter(([key, text]) => key.includes('onsent') && GERMAN_AGREEING.test(text))
		.map(([key]) => key);
	assert.deepEqual(offenders, [], 'de consent is Einwilligung / einwilligen, never zustimmen');
});

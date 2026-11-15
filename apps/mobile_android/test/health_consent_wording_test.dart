// Health data is kept only with GDPR Art 9(2)(a) consent (decisions § 2514).
// The setup wizard called giving that consent "sharing health data", which
// reads as publishing it and is not what the reader agrees to. Consent is
// called consent: "if you give health-data consent".
//
// In German, consent is Einwilligung / einwilligen and never zustimmen
// (decisions § 2527). The AI dialog's sentence once said „Indem du annimmst“
// against a button that read „Ich stimme zu“, because the rule was applied to
// one string and not its neighbours.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _germanAgreeing =
    RegExp(r'\bzustimm|\bstimm(?:e|st) zu\b|\bZustimmung|\bzugestimmt',
        caseSensitive: false);

final _sharingHealthData =
    RegExp(r'\bshar(?:e|es|ed|ing)\b(?:\s+\w+){0,2}\s+health[- ]data\b',
        caseSensitive: false);

void main() {
  test('the scan reads sharing health data, not sharing beside it', () {
    expect(_sharingHealthData.hasMatch('if you share health data'), isTrue);
    expect(_sharingHealthData.hasMatch('You choose whether to share your health data'), isTrue);
    expect(_sharingHealthData.hasMatch('if you give health-data consent'), isFalse);
    expect(_sharingHealthData.hasMatch('Share run · health data stays private'), isFalse);
  });

  test('no English message calls health-data consent sharing', () {
    final arb = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
        as Map<String, dynamic>;
    final offenders = [
      for (final e in arb.entries)
        if (!e.key.startsWith('@') &&
            e.value is String &&
            _sharingHealthData.hasMatch(e.value as String))
          e.key,
    ];
    expect(offenders, isEmpty,
        reason: 'say "give health-data consent", not "share health data"');
  });

  test('the German scan reads agreeing, not tailoring', () {
    expect(_germanAgreeing.hasMatch('Ich stimme zu'), isTrue);
    expect(_germanAgreeing.hasMatch('Lies sie und stimme zu.'), isTrue);
    expect(_germanAgreeing.hasMatch('Mit deiner Zustimmung'), isTrue);
    expect(_germanAgreeing.hasMatch('noch nicht zugestimmt'), isTrue);
    expect(_germanAgreeing.hasMatch('Ich willige ein'), isFalse);
    expect(_germanAgreeing.hasMatch('auf dich abzustimmen'), isFalse);
  });

  test('no German consent message says zustimmen', () {
    final arb = jsonDecode(File('lib/l10n/app_de.arb').readAsStringSync())
        as Map<String, dynamic>;
    final offenders = [
      for (final e in arb.entries)
        if (!e.key.startsWith('@') &&
            e.key.contains('onsent') &&
            e.value is String &&
            _germanAgreeing.hasMatch(e.value as String))
          e.key,
    ];
    expect(offenders, isEmpty,
        reason: 'de consent is Einwilligung / einwilligen, never zustimmen');
  });
}

// Health data is kept only with GDPR Art 9(2)(a) consent (decisions § 2514).
// The setup wizard called giving that consent "sharing health data", which
// reads as publishing it and is not what the reader agrees to. Consent is
// called consent: "if you give health-data consent".

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
}

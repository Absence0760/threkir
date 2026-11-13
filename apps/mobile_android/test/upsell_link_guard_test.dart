// Every upsell opens Pro (issue #1374 finding 11). The prompts used to say
// "upgrade in Settings" as plain text, so a runner who wanted to pay was told
// to go and find the page. `ProUpsellLink` draws the reason with a link that
// opens the Pro screen; these keep a new prompt from going back to prose.
//
// Three rules:
//   1. No English string sends the reader to Settings to upgrade.
//   2. Every English string outside the Pro screen's own `pro*` keys that
//      names Pro is either an upsell (listed in `_upsells`, and every file
//      that reads it builds a `ProUpsellLink`) or exempt with a reason.
//   3. Both lists only shrink: an entry that no longer matches fails.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _upsells = {
  'coachLimitReachedFree',
  'routeDetailEnhanceUpgradeHint',
  'platePhotoErrorPro',
};

const _exempt = {
  'billingRenewalFailed':
      'a billing notice on the Pro screen\'s own subject, not a prompt to buy',
  'helpRequiresPro': 'a tag on a help guide, beside which nothing is sold',
};

final _namesPro = RegExp(r'\bPro\b');
final _deadEnd = RegExp(
  r'\b(upgrade|subscribe|go pro|get pro)\b[^.]*\b(in|from|under|via)\s+'
  r'(the\s+)?Settings\b',
  caseSensitive: false,
);

Map<String, String> _english() {
  final raw = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
      as Map<String, dynamic>;
  return {
    for (final e in raw.entries)
      if (!e.key.startsWith('@') && e.value is String)
        e.key: e.value as String,
  };
}

Iterable<File> _sources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) =>
        f.path.endsWith('.dart') && !f.path.contains('/l10n/gen/'));

void main() {
  final en = _english();

  test('no English string sends the reader to Settings to upgrade', () {
    final offenders = [
      for (final e in en.entries)
        if (_deadEnd.hasMatch(e.value)) '${e.key}: ${e.value}',
    ];
    expect(offenders, isEmpty,
        reason: 'Show the reason with ProUpsellLink, which opens Pro; '
            'the string itself gives no directions.');
  });

  test('every string that names Pro is a registered upsell or exempt', () {
    final unclassified = [
      for (final e in en.entries)
        if (!e.key.startsWith('pro') &&
            _namesPro.hasMatch(e.value) &&
            !_upsells.contains(e.key) &&
            !_exempt.containsKey(e.key))
          '${e.key}: ${e.value}',
    ];
    expect(unclassified, isEmpty,
        reason: 'A new string that names Pro is an upsell: add it to '
            '_upsells and draw it with ProUpsellLink, or exempt it here '
            'with the reason it sells nothing.');
  });

  test('every file that reads an upsell builds a ProUpsellLink', () {
    final offenders = <String>[];
    final readers = <String, int>{for (final k in _upsells) k: 0};
    for (final f in _sources()) {
      final src = f.readAsStringSync();
      for (final key in _upsells) {
        if (!RegExp('\\.$key\\b').hasMatch(src)) continue;
        readers[key] = readers[key]! + 1;
        if (!src.contains('ProUpsellLink(')) offenders.add('${f.path}: $key');
      }
    }
    expect(offenders, isEmpty,
        reason: 'An upsell drawn as plain text is a dead end.');
    expect(
      [for (final e in readers.entries) if (e.value == 0) e.key],
      isEmpty,
      reason: 'An upsell no file reads any more: drop it from _upsells.',
    );
  });

  test('the registry and exemptions only name live strings that name Pro', () {
    final stale = [
      for (final k in {..._upsells, ..._exempt.keys})
        if (!en.containsKey(k) || !_namesPro.hasMatch(en[k]!)) k,
    ];
    expect(stale, isEmpty);
  });
}

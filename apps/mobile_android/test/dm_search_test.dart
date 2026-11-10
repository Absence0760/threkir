// ignore_for_file: avoid_relative_lib_imports
// Mirrors apps/web/src/lib/social/dm_search.test.ts case-for-case.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/dm_search.dart';

void main() {
  test('the query bounds are the ones search_direct_messages enforces', () {
    final file = Directory('../backend/supabase/migrations')
        .listSync()
        .whereType<File>()
        .firstWhere((f) => f.path.endsWith('_dm_search.sql'));
    final m = RegExp(r'char_length\(q\.t\) between (\d+) and (\d+)')
        .firstMatch(file.readAsStringSync());
    expect(m, isNotNull);
    expect(kDmSearchMinChars, int.parse(m!.group(1)!));
    expect(kDmSearchMaxChars, int.parse(m.group(2)!));
  });

  test('a query is trimmed and bounded by characters, not UTF-16 units', () {
    expect(normalizeDmSearchQuery('  tempo  '), 'tempo');
    expect(normalizeDmSearchQuery('a'), isNull);
    expect(normalizeDmSearchQuery('   '), isNull);
    expect(normalizeDmSearchQuery('x' * 100), 'x' * 100);
    expect(normalizeDmSearchQuery('x' * 101), isNull);
    final runner = String.fromCharCode(0x1f3c3);
    expect(normalizeDmSearchQuery(runner * 2), runner * 2);
    expect(normalizeDmSearchQuery(runner), isNull);
  });

  test('the snippet centres the first match, case-insensitively', () {
    expect(
      dmSearchSnippet('Meet at the TRACK at six', 'track', radius: 5),
      const DmSearchSnippet(before: '… the ', match: 'TRACK', after: ' at s…'),
    );
    expect(
      dmSearchSnippet('track day', 'track'),
      const DmSearchSnippet(before: '', match: 'track', after: ' day'),
    );
  });

  test('a body without a match is shown from its start', () {
    expect(
      dmSearchSnippet('abcdef', 'zz', radius: 2),
      const DmSearchSnippet(before: '', match: '', after: 'abcd…'),
    );
    expect(
      dmSearchSnippet('ab', 'zz', radius: 2),
      const DmSearchSnippet(before: '', match: '', after: 'ab'),
    );
  });
}

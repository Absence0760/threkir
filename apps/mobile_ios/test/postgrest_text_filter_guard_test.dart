import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pins how user-typed search text reaches a PostgREST filter from the app's
/// own services (the `ApiClient` half is pinned by api_client's
/// `keyset_readers_source_test.dart`).
///
/// Inside an `or=` / `and=` tree PostgREST reads an unquoted value up to the
/// next `,` or `)`, so `name.ilike.%$term%` let a typed `,` start a new,
/// malformed filter and a `)` close the tree. The term must go through
/// core_models' `literalSubstringTerm`, which escapes it for `imatch` and
/// double-quotes it. A source guard because the regression is static; the
/// quoting itself is pinned against a model of PostgREST's parser by
/// core_models' `keyset_page_test.dart`.
void main() {
  /// Every Dart file under lib/, with whole-line `//` comments dropped so
  /// prose describing the banned shape is not read as an instance of it.
  Map<String, String> sources() => {
        for (final f in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')))
          f.path: f
              .readAsLinesSync()
              .where((l) => !l.trimLeft().startsWith('//'))
              .join('\n'),
      };

  test('SocialService.browseClubs quotes its search term inside the or= tree',
      () {
    final src = sources()['lib/social_service.dart']!;
    final start = src.indexOf('Future<List<ClubView>> browseClubs(');
    expect(start, greaterThanOrEqualTo(0), reason: 'browseClubs moved');
    final fn = src.substring(start, src.indexOf('\n  /// ', start));
    expect(fn, contains("literalSubstringTerm('name', term)"));
    expect(fn, contains("literalSubstringTerm('location_label', term)"));
    expect(fn, isNot(contains('ilike')),
        reason: 'an ilike pattern reads * % _ \\ as wildcards');
  });

  test('no filter tree interpolates text into a pattern operator unquoted', () {
    final pattern =
        RegExp(r'\.(i?like|i?match|fts|plfts|phfts|wfts)\.[%*]?\$');
    final offenders = [
      for (final e in sources().entries)
        if (pattern.hasMatch(e.value)) e.key,
    ];
    expect(offenders, isEmpty);
  });
}

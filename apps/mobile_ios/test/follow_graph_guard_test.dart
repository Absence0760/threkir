// A picker that filters the viewer's follow graph on the client must read it
// whole. New message, Send route and the group people picker read one
// 500-row page of each direction, and the feed's author filter one 200-row
// page, so everyone past the cap was missing from the list and from its
// search with nothing on screen to say so (decisions § 2507; web's twin is
// `core/keyset_readers.test.ts`). `ApiClient.fetchFollowGraph` and
// `fetchAllFollowing` walk to the end and throw when a walk cannot finish.
//
// `fetchFollowers` / `fetchFollowing` read ONE keyset page. They stay for a
// list that pages with load-more, and only the files in `_pagedReaders` may
// call them; that set may only shrink.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files that read the follow graph one page at a time on purpose, because
/// they show it as a load-more list. May only shrink.
const _pagedReaders = <String, String>{
  'lib/screens/profile_screen.dart':
      'the Followers and Following tabs page with load-more',
};

String _code(File f) =>
    f.readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join('\n');

void main() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart') && !f.path.contains('/l10n/'))
      .toList();
  final pageRead = RegExp(r'\.fetchFollow(ers|ing)\(');

  test('only a load-more list reads one page of the follow graph', () {
    final offenders = [
      for (final f in files)
        if (pageRead.hasMatch(_code(f))) f.path,
    ]..sort();
    expect(
      offenders,
      _pagedReaders.keys.toList()..sort(),
      reason:
          'read the whole graph with fetchFollowGraph or '
          'fetchAllFollowing; a single page hides everyone past it',
    );
  });

  test('a paged reader really pages: it passes the next cursor', () {
    for (final path in _pagedReaders.keys) {
      final code = _code(File(path));
      expect(
        RegExp(r'\.fetchFollow(ers|ing)\([^)]*after: after').hasMatch(code),
        isTrue,
        reason: '$path calls a one-page reader without a load-more',
      );
    }
  });

  test('every follow-graph picker reads the whole graph', () {
    final pickers = [
      for (final f in files)
        if (_code(f).contains('dmRecipientCandidates(') &&
            !_code(f).contains('List<DmRecipient> dmRecipientCandidates('))
          f,
    ];
    expect(
      pickers.length,
      greaterThanOrEqualTo(3),
      reason:
          'expected New message, Send route and the group picker, '
          'found ${pickers.map((f) => f.path)}',
    );
    for (final f in pickers) {
      expect(
        _code(f).contains('.fetchFollowGraph('),
        isTrue,
        reason: '${f.path} must read the whole follow graph',
      );
    }
    expect(
      _code(
        File('lib/screens/feed_screen.dart'),
      ).contains('.fetchAllFollowing('),
      isTrue,
      reason: "the feed's author filter lists everyone you follow",
    );
  });
}

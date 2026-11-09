// ignore_for_file: avoid_relative_lib_imports
// Mirrors apps/web/src/lib/social/messages_inbox.test.ts case-for-case.
import 'package:flutter_test/flutter_test.dart';

import '../lib/messages_inbox.dart';

typedef _T = ({String id, DateTime lastAt});

_T _thread(String id, String lastAt) => (id: id, lastAt: DateTime.parse(lastAt));

List<String> _ids(List<InboxEntry<_T>> entries) => [
      for (final e in entries)
        switch (e) {
          CoachInboxEntry() => 'coach',
          DmInboxEntry(:final thread) => thread.id,
        },
    ];

List<InboxEntry<_T>> _entries(List<_T> threads, CoachInboxRow? coach) =>
    inboxEntries<_T>(threads, coach, lastAt: (t) => t.lastAt);

CoachInboxRow _row(CoachInboxPlacement p, [String? lastAt]) => CoachInboxRow(
      placement: p,
      lastAt: lastAt == null ? null : DateTime.parse(lastAt),
    );

void main() {
  final threads = [
    _thread('a', '2026-10-21T09:00:00+00:00'),
    _thread('b', '2026-10-20T09:00:00+00:00'),
    _thread('c', '2026-10-19T09:00:00+00:00'),
  ];

  test('the settings key is the one the registry names', () {
    expect(kMessagesCoachRowKey, 'messages_coach_row');
  });

  test('an absent or unknown placement reads as pinned', () {
    expect(parseCoachInboxPlacement(null), CoachInboxPlacement.pinned);
    expect(parseCoachInboxPlacement('Hidden'), CoachInboxPlacement.pinned);
    expect(parseCoachInboxPlacement(true), CoachInboxPlacement.pinned);
    expect(parseCoachInboxPlacement('pinned'), CoachInboxPlacement.pinned);
    expect(parseCoachInboxPlacement('listed'), CoachInboxPlacement.listed);
    expect(parseCoachInboxPlacement('hidden'), CoachInboxPlacement.hidden);
  });

  test('with no Coach row the inbox is the conversations in their order', () {
    expect(_ids(_entries(threads, null)), ['a', 'b', 'c']);
  });

  test('a hidden Coach is left out', () {
    expect(
      _ids(_entries(
          threads, _row(CoachInboxPlacement.hidden, '2026-10-22T00:00:00Z'))),
      ['a', 'b', 'c'],
    );
  });

  test(
      'a pinned Coach sits above every conversation, however old its last '
      'message', () {
    expect(
      _ids(_entries(
          threads, _row(CoachInboxPlacement.pinned, '2020-01-01T00:00:00Z'))),
      ['coach', 'a', 'b', 'c'],
    );
    expect(_ids(_entries(threads, _row(CoachInboxPlacement.pinned))),
        ['coach', 'a', 'b', 'c']);
  });

  test('a pinned Coach is the only row of an empty inbox', () {
    expect(_ids(_entries(const [], _row(CoachInboxPlacement.pinned))),
        ['coach']);
  });

  test('a listed Coach is filed by its latest message', () {
    expect(
      _ids(_entries(threads,
          _row(CoachInboxPlacement.listed, '2026-10-20T12:00:00+00:00'))),
      ['a', 'coach', 'b', 'c'],
    );
    expect(
      _ids(_entries(threads,
          _row(CoachInboxPlacement.listed, '2026-10-22T00:00:00+00:00'))),
      ['coach', 'a', 'b', 'c'],
    );
    expect(
      _ids(_entries(threads,
          _row(CoachInboxPlacement.listed, '2026-10-01T00:00:00+00:00'))),
      ['a', 'b', 'c', 'coach'],
    );
  });

  test('a listed Coach tied with a conversation goes after it', () {
    expect(
      _ids(_entries(
          threads, _row(CoachInboxPlacement.listed, '2026-10-20T09:00:00Z'))),
      ['a', 'b', 'coach', 'c'],
    );
    // The same millisecond is a tie, whatever the microseconds say.
    expect(
      _ids(_entries([_thread('x', '2026-10-20T09:00:00.123456Z')],
          _row(CoachInboxPlacement.listed, '2026-10-20T09:00:00.123900Z'))),
      ['x', 'coach'],
    );
  });

  test('a listed Coach with no message goes last', () {
    expect(_ids(_entries(threads, _row(CoachInboxPlacement.listed))),
        ['a', 'b', 'c', 'coach']);
  });

  test('the preview drops markdown and keeps the words', () {
    expect(
      coachInboxPreview('## Today\n\n- **Easy** 6 km at `5:40/km`\n'
          '- see [the plan](/plans/x)\n> rest'),
      'Today Easy 6 km at 5:40/km see the plan rest',
    );
    expect(coachInboxPreview('1. warm up\n2) strides'), 'warm up strides');
    expect(coachInboxPreview('```js\ncode()\n```'), 'code()');
    expect(coachInboxPreview('keep snake_case and 3*4'),
        'keep snake_case and 34');
    expect(coachInboxPreview('   \n\n  '), '');
    expect(coachInboxPreview('\u0085rest day\u0085'), 'rest day');
  });

  test('a long preview is cut on a code point with an ellipsis', () {
    final long = 'x' * (kCoachPreviewMax + 10);
    final out = coachInboxPreview(long);
    expect(out.runes.length, kCoachPreviewMax);
    expect(out.endsWith('…'), isTrue);
    final emoji = '\u{1F3C3}' * (kCoachPreviewMax + 1);
    final cut = coachInboxPreview(emoji);
    expect(cut.runes.length, kCoachPreviewMax);
    expect(String.fromCharCode(cut.runes.first), '\u{1F3C3}');
    expect(coachInboxPreview('x' * kCoachPreviewMax), 'x' * kCoachPreviewMax);
  });

  test('archived conversations leave the inbox for the Archived list, order kept',
      () {
    final threads = [('a', false), ('b', true), ('c', false), ('d', true)];
    final split =
        partitionArchived(threads, archived: (t) => t.$2, request: (_) => false);
    expect([for (final t in split.inbox) t.$1], ['a', 'c']);
    expect([for (final t in split.archived) t.$1], ['b', 'd']);
    expect(split.requests, isEmpty);
    final empty = partitionArchived(<(String, bool)>[],
        archived: (t) => t.$2, request: (_) => false);
    expect(empty.inbox, isEmpty);
    expect(empty.archived, isEmpty);
    expect(empty.requests, isEmpty);
  });

  test('a message request goes to Requests, even when it is also archived', () {
    final threads = [
      ('a', false, true),
      ('b', false, false),
      ('c', true, true),
      ('d', true, false),
    ];
    final split =
        partitionArchived(threads, archived: (t) => t.$2, request: (t) => t.$3);
    expect([for (final t in split.requests) t.$1], ['a', 'c']);
    expect([for (final t in split.inbox) t.$1], ['b']);
    expect([for (final t in split.archived) t.$1], ['d']);
  });

  test(
      'the badge counts unread only in conversations neither muted, archived nor a request',
      () {
    expect(
      unreadDmBadgeCount([
        (unread: 2, muted: false, archived: false, request: false),
        (unread: 5, muted: true, archived: false, request: false),
        (unread: 3, muted: false, archived: true, request: false),
        (unread: 4, muted: false, archived: false, request: true),
        (unread: 1, muted: false, archived: false, request: false),
      ]),
      3,
    );
    expect(
        unreadDmBadgeCount(
            [(unread: -4, muted: false, archived: false, request: false)]),
        0);
    expect(unreadDmBadgeCount(const []), 0);
  });
}

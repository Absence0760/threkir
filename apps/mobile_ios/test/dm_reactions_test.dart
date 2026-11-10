// ignore_for_file: avoid_relative_lib_imports
// Mirrors apps/web/src/lib/social/dm_reactions.test.ts case-for-case.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/dm_reactions.dart';

const _rows = [
  DmReactionRow(messageId: 'm1', userId: 'me', reaction: 'fire'),
  DmReactionRow(messageId: 'm1', userId: 'them', reaction: 'thumbs_up'),
  DmReactionRow(messageId: 'm2', userId: 'them', reaction: 'fire'),
  DmReactionRow(messageId: 'm1', userId: 'x', reaction: 'bogus'),
];

void main() {
  test('the keys are the ones the reactions CHECK admits, in its order', () {
    final file = Directory('../backend/supabase/migrations')
        .listSync()
        .whereType<File>()
        .firstWhere((f) => f.path.endsWith('_dm_reactions.sql'));
    final m = RegExp(r'check \(reaction in \(([^)]*)\)\)')
        .firstMatch(file.readAsStringSync());
    expect(m, isNotNull, reason: 'the reaction CHECK was not found');
    final keys = RegExp(r"'([a-z_]+)'")
        .allMatches(m!.group(1)!)
        .map((x) => x.group(1))
        .toList();
    expect(keys, kDmReactions);
  });

  test('every key draws from codepoints, never from a stored glyph', () {
    for (final key in kDmReactions) {
      expect(dmReactionGlyph(key).runes.toList(), kDmReactionCodepoints[key]);
    }
    expect(dmReactionGlyph('thumbs_up').runes.first, 0x1f44d);
  });

  test('parseDmReaction keeps only known keys', () {
    expect(parseDmReaction('heart'), 'heart');
    expect(parseDmReaction('poop'), isNull);
    expect(parseDmReaction(String.fromCharCode(0x1f44d)), isNull);
    expect(parseDmReaction(null), isNull);
  });

  test('the summary counts per key in set order and marks the viewer', () {
    expect(summarizeDmReactions(_rows, 'm1', 'me'), const [
      DmReactionSummary(reaction: 'thumbs_up', count: 1, mine: false),
      DmReactionSummary(reaction: 'fire', count: 1, mine: true),
    ]);
    expect(summarizeDmReactions(_rows, 'm1', null), const [
      DmReactionSummary(reaction: 'thumbs_up', count: 1, mine: false),
      DmReactionSummary(reaction: 'fire', count: 1, mine: false),
    ]);
    expect(summarizeDmReactions(_rows, 'none', 'me'), isEmpty);
    expect(
      summarizeDmReactions(const [
        DmReactionRow(messageId: 'm', userId: 'a', reaction: 'sad'),
        DmReactionRow(messageId: 'm', userId: 'b', reaction: 'sad'),
      ], 'm', 'b'),
      const [DmReactionSummary(reaction: 'sad', count: 2, mine: true)],
    );
  });

  test('the viewer has at most one reaction per message', () {
    expect(myDmReaction(_rows, 'm1', 'me'), 'fire');
    expect(myDmReaction(_rows, 'm2', 'me'), isNull);
    expect(myDmReaction(_rows, 'm1', null), isNull);
  });

  test('setting replaces the viewer row and clearing removes it', () {
    final set = withMyDmReaction(_rows, 'm1', 'me', 'heart');
    expect(myDmReaction(set, 'm1', 'me'), 'heart');
    expect(
      set.where((r) => r.messageId == 'm1' && r.userId == 'me').length,
      1,
    );
    final cleared = withMyDmReaction(set, 'm1', 'me', null);
    expect(myDmReaction(cleared, 'm1', 'me'), isNull);
    expect(cleared.length, _rows.length - 1);
  });
}

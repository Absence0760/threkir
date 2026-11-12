import 'package:flutter_test/flutter_test.dart';
import '../lib/run_reactions.dart';

void main() {
  test('reactionKeys is the five-key whitelist the CHECK carries', () {
    expect(reactionKeys, ['fire', 'strong', 'trophy', 'thumbs_up', 'wave']);
  });

  test('isReactionKey accepts only whitelisted strings', () {
    expect(isReactionKey('fire'), isTrue);
    expect(isReactionKey('heart_eyes'), isFalse);
    expect(isReactionKey(3), isFalse);
  });

  test('reactionTallies: one tally per key in whitelist order, zero when unused', () {
    final t = reactionTallies([
      {'reaction': 'wave', 'reaction_count': 2, 'viewer_reacted': true},
    ]);
    expect(t.map((x) => [x.key, x.count, x.viewerReacted]).toList(), [
      ['fire', 0, false],
      ['strong', 0, false],
      ['trophy', 0, false],
      ['thumbs_up', 0, false],
      ['wave', 2, true],
    ]);
  });

  test('reactionTallies: drops an unknown key and clamps a bad count', () {
    final t = reactionTallies([
      {'reaction': 'party', 'reaction_count': 9, 'viewer_reacted': true},
      {'reaction': 'fire', 'reaction_count': -3, 'viewer_reacted': false},
    ]);
    expect(t.length, 5);
    expect(t[0].count, 0);
  });

  test('applyReactionToggle: a real add bumps the count and sets the flag', () {
    final t = applyReactionToggle(reactionTallies(const []), 'fire', true, true);
    expect([t[0].count, t[0].viewerReacted], [1, true]);
  });

  test('applyReactionToggle: a no-op flips the flag without moving the count', () {
    final start = reactionTallies([
      {'reaction': 'fire', 'reaction_count': 1, 'viewer_reacted': false},
    ]);
    final t = applyReactionToggle(start, 'fire', true, false);
    expect([t[0].count, t[0].viewerReacted], [1, true]);
  });

  test('applyReactionToggle: a real remove never goes below zero', () {
    final t = applyReactionToggle(reactionTallies(const []), 'wave', false, true);
    expect([t[4].count, t[4].viewerReacted], [0, false]);
  });
}

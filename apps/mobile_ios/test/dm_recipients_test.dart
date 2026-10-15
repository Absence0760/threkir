// ignore_for_file: avoid_relative_lib_imports
import 'package:flutter_test/flutter_test.dart';

import '../lib/dm_recipients.dart';

/// Mirror of web `social/dm_recipients.test.ts`, case for case.
DmCandidateProfile profile(String id, [String? name]) =>
    DmCandidateProfile(id: id, displayName: name);

void main() {
  test('a follower who is not followed back is still a candidate', () {
    final out = dmRecipientCandidates([profile('a', 'Ana')], []);
    expect(out.map((r) => [r.id, r.relation]).toList(), [
      ['a', DmRelation.followsYou],
    ]);
  });

  test('someone the sender follows who does not follow back is a candidate',
      () {
    final out = dmRecipientCandidates([], [profile('b', 'Bo')]);
    expect(out.map((r) => [r.id, r.relation]).toList(), [
      ['b', DmRelation.youFollow],
    ]);
  });

  test('a person on both sides appears once, as mutual', () {
    final out =
        dmRecipientCandidates([profile('a', 'Ana')], [profile('a', 'Ana')]);
    expect(out.length, 1);
    expect(out.single.relation, DmRelation.mutual);
  });

  test('the sender is never offered as a recipient', () {
    final out = dmRecipientCandidates(
      [profile('me', 'Me')],
      [profile('me', 'Me')],
      selfId: 'me',
    );
    expect(out, isEmpty);
  });

  test('rows with no id are dropped rather than offered as an unsendable target',
      () {
    final out = dmRecipientCandidates([profile('', 'Nameless id')], []);
    expect(out, isEmpty);
  });

  test('candidates are ordered by display name, case- and accent-insensitively',
      () {
    final out = dmRecipientCandidates(
      [profile('3', 'zoe'), profile('1', 'Émile')],
      [profile('2', 'ana')],
    );
    expect(out.map((r) => r.displayName).toList(), ['ana', 'Émile', 'zoe']);
  });

  test(
      'the order is the folded order the web half computes, not a host collation',
      () {
    final out = dmRecipientCandidates(
      [profile('1', 'Zaragoza'), profile('2', 'Ørsted')],
      [profile('3', 'Åre')],
    );
    expect(
        out.map((r) => r.displayName).toList(), ['Åre', 'Zaragoza', 'Ørsted']);
  });

  test('unnamed candidates sort last, and ties break on id so the order is total',
      () {
    final out = dmRecipientCandidates(
      [profile('z-id'), profile('a-id'), profile('m', 'Mo')],
      [],
    );
    expect(out.map((r) => r.id).toList(), ['m', 'a-id', 'z-id']);
  });

  test('the merge order of the two fetches does not change the result', () {
    final followers = [profile('b', 'Bo'), profile('a', 'Ana')];
    final following = [profile('c', 'Cy'), profile('a', 'Ana')];
    List<Object?> ids(List<DmRecipient> rs) =>
        [for (final r in rs) '${r.id}:${r.relation.name}'];
    expect(
      ids(dmRecipientCandidates(followers, following)),
      ids(dmRecipientCandidates(followers, following)),
    );
    expect(
      dmRecipientCandidates(followers, following).map((r) => r.id).toList(),
      ['a', 'b', 'c'],
    );
  });

  test(
      'avatar and display name are carried through from whichever side supplied them',
      () {
    final out = dmRecipientCandidates([
      const DmCandidateProfile(
        id: 'a',
        displayName: 'Ana',
        avatarUrl: 'https://example.test/a.png',
      ),
    ], []);
    expect(out.first.displayName, 'Ana');
    expect(out.first.avatarUrl, 'https://example.test/a.png');
  });

  test('a blank query keeps every candidate', () {
    final all = dmRecipientCandidates([profile('a', 'Ana'), profile('b')], []);
    expect(filterDmRecipients(all, '').length, 2);
    expect(filterDmRecipients(all, '   ').length, 2);
  });

  test('filtering matches a substring, case- and accent-insensitively', () {
    final all = dmRecipientCandidates(
        [profile('a', 'Émile Zola'), profile('b', 'Bo')], []);
    expect(filterDmRecipients(all, 'emile').map((r) => r.id).toList(), ['a']);
    expect(filterDmRecipients(all, 'ZOL').map((r) => r.id).toList(), ['a']);
  });

  test('an unnamed candidate matches no non-blank query', () {
    final all = dmRecipientCandidates([profile('a')], []);
    expect(filterDmRecipients(all, 'a'), isEmpty);
  });

  test('filtering does not mutate the list it was given', () {
    final all =
        dmRecipientCandidates([profile('a', 'Ana'), profile('b', 'Bo')], []);
    filterDmRecipients(all, 'ana');
    expect(all.length, 2);
  });

  test('filterDmRecipients: the search is not sigma-sensitive', () {
    final list = [
      DmRecipient(
        id: 'a',
        displayName: 'ΟΔΟΣ',
        avatarUrl: null,
        relation: DmRelation.followsYou,
      ),
    ];
    expect(filterDmRecipients(list, 'οδοσ').length, 1);
    expect(filterDmRecipients(list, 'οδος').length, 1);
  });

  test('filterDmRecipients: the search folds accents, like every other search key',
      () {
    final list = [
      DmRecipient(
        id: 'a',
        displayName: 'Zoë Müller',
        avatarUrl: null,
        relation: DmRelation.youFollow,
      ),
    ];
    expect(filterDmRecipients(list, 'zoe muller').length, 1);
  });
}

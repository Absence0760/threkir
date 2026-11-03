import 'package:flutter_test/flutter_test.dart';
import '../lib/head_to_head.dart';

Map<String, Object?> row([Map<String, Object?> over = const {}]) => {
      'friend_id': 'f1',
      'friend_display_name': 'Sam',
      'friend_handle': 'sam',
      'friend_avatar_url': null,
      'target_name': 'River Loop',
      'my_run_id': 'r1',
      'my_seconds': 1900,
      'my_started_at': '2026-10-01T07:00:00Z',
      'friend_run_id': 'r2',
      'friend_seconds': 1950,
      'friend_started_at': '2026-10-02T07:00:00Z',
      ...over,
    };

void main() {
  test('the three kinds the RPC takes', () {
    expect(headToHeadKinds, ['route', 'segment', 'global_segment']);
  });

  test('a full row parses into both sides', () {
    expect(parseHeadToHeadRows([row()]), [
      const HeadToHeadRow(
        friendId: 'f1',
        friendDisplayName: 'Sam',
        friendHandle: 'sam',
        friendAvatarUrl: null,
        targetName: 'River Loop',
        myRunId: 'r1',
        mySeconds: 1900,
        friendRunId: 'r2',
        friendSeconds: 1950,
      ),
    ]);
  });

  test('a row missing a side or a time is dropped', () {
    final bad = [
      row({'friend_id': null}),
      row({'my_run_id': ''}),
      row({'friend_seconds': 0}),
      row({'my_seconds': double.nan}),
      row({'target_name': '  '}),
      null,
      'x',
    ];
    expect(parseHeadToHeadRows(bad), isEmpty);
  });

  test('anything that is not a list parses to nothing', () {
    expect(parseHeadToHeadRows(null), isEmpty);
    expect(parseHeadToHeadRows(<String, Object?>{}), isEmpty);
  });

  test('blank optional names come back null', () {
    final r = parseHeadToHeadRows(
        [row({'friend_handle': ' ', 'friend_display_name': ''})]).single;
    expect(r.friendHandle, isNull);
    expect(r.friendDisplayName, isNull);
  });

  test('the lower time wins, by the whole-second gap', () {
    expect(headToHeadOutcome(1900, 1950),
        const HeadToHeadOutcome(HeadToHeadWinner.me, 50));
    expect(headToHeadOutcome(2000, 1950),
        const HeadToHeadOutcome(HeadToHeadWinner.friend, 50));
  });

  test('times that round to the same second are a tie', () {
    expect(headToHeadOutcome(100.4, 99.6),
        const HeadToHeadOutcome(HeadToHeadWinner.tie, 0));
    expect(headToHeadOutcome(60, 60),
        const HeadToHeadOutcome(HeadToHeadWinner.tie, 0));
  });

  test('a time under an hour prints m:ss', () {
    expect(formatHeadToHeadTime(0), '0:00');
    expect(formatHeadToHeadTime(59.6), '1:00');
    expect(formatHeadToHeadTime(1950), '32:30');
  });

  test('an hour or more prints h:mm:ss', () {
    expect(formatHeadToHeadTime(3600), '1:00:00');
    expect(formatHeadToHeadTime(3725), '1:02:05');
  });

  test('a negative or non-finite time prints 0:00', () {
    expect(formatHeadToHeadTime(-5), '0:00');
    expect(formatHeadToHeadTime(double.infinity), '0:00');
  });

  test('a handle wins over the display name', () {
    expect(headToHeadName('sam', 'Sam Smith'), '@sam');
    expect(headToHeadName(' sam ', null), '@sam');
  });

  test('with no handle the display name, else null', () {
    expect(headToHeadName(null, ' Sam Smith '), 'Sam Smith');
    expect(headToHeadName('', ''), isNull);
    expect(headToHeadName(null, null), isNull);
  });
}

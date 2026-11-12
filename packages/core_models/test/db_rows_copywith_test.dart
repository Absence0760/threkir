import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

// The generated `copyWith` is what `NotificationView.markedRead` rebuilds a
// row through (decisions § 1836), so its two properties are pinned here:
// an empty call changes nothing, and `?? this.x` means a nullable column
// can be set but never cleared.

Map<String, dynamic> _notificationJson() => <String, dynamic>{
      'id': 'n1',
      'user_id': 'me',
      'actor_id': 'a1',
      'kind': 'club_post',
      'run_id': 'r1',
      'comment_id': 'c1',
      'read_at': null,
      'created_at': '2026-10-13T09:00:00.000Z',
      'event_id': 'e1',
      'plan_id': 'p1',
      'club_id': 'club1',
      'email_sent_at': '2026-10-13T10:00:00.000Z',
      'event_instance_start': '2026-10-20T07:00:00.000Z',
      'activity_kind': 'run',
      'activity_id': 'act1',
      'web_push_sent_at': '2026-10-13T11:00:00.000Z',
      'achievement_id': 'ach1',
      'challenge_id': 'ch1',
      'native_push_sent_at': '2026-10-13T12:00:00.000Z',
      'refunded': true,
    };

void main() {
  test('an empty copyWith round-trips every column', () {
    final row = NotificationRow.fromJson(_notificationJson());
    expect(row.copyWith().toJson(), row.toJson());
  });

  test('a copyWith changes the named column and only that one', () {
    final row = NotificationRow.fromJson(_notificationJson());
    final at = DateTime.utc(2026, 10, 14, 8);
    final expected = row.toJson()..['read_at'] = at.toIso8601String();
    expect(row.copyWith(readAt: at).toJson(), expected);
  });

  test('a nullable column cannot be cleared through copyWith', () {
    final row = NotificationRow.fromJson(
        _notificationJson()..['read_at'] = '2026-10-13T12:00:00.000Z');
    expect(row.copyWith(readAt: null).readAt, row.readAt,
        reason: 'null means "keep", so clearing needs a new row');
    expect(row.copyWith(eventId: null).eventId, 'e1');
  });
}

import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

NotificationView _view({DateTime? readAt}) => NotificationView(
      row: NotificationRow(
        id: 'n1',
        userId: 'me',
        actorId: 'a1',
        kind: 'event_waitlist_slot',
        readAt: readAt,
        createdAt: DateTime.utc(2026, 10, 13, 9),
        eventId: 'e1',
        eventInstanceStart: DateTime.utc(2026, 10, 20, 7),
        clubId: 'club1',
        refunded: false,
      ),
      actor: const PublicProfile(id: 'a1', displayName: 'Ana'),
      runDistanceM: 5000,
      commentExcerpt: 'see you there',
      eventTitle: 'Reformer',
      eventClubSlug: 'studio',
      clubName: 'Studio',
      clubSlug: 'studio',
    );

void main() {
  test('markedRead stamps read_at and carries every row column', () {
    final at = DateTime.utc(2026, 10, 14, 8);
    final before = _view();
    final after = before.markedRead(at);
    expect(after.row.readAt, at);
    expect(after.row.toJson(),
        before.row.toJson()..[NotificationRow.colReadAt] = at.toIso8601String());
  });

  test('markedRead carries every joined field of the view', () {
    final before = _view();
    final after = before.markedRead(DateTime.utc(2026, 10, 14));
    expect(after.actor, same(before.actor));
    expect(after.runDistanceM, 5000);
    expect(after.commentExcerpt, 'see you there');
    expect(after.eventTitle, 'Reformer');
    expect(after.eventClubSlug, 'studio');
    expect(after.clubName, 'Studio');
    expect(after.clubSlug, 'studio');
  });

  test('an already-read row keeps its first stamp', () {
    final first = DateTime.utc(2026, 10, 13, 12);
    final view = _view(readAt: first);
    expect(view.markedRead(DateTime.utc(2026, 10, 14)).row, same(view.row));
  });
}

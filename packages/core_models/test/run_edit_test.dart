import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

/// The pure half of the run edit compare-and-swap (decisions § 2120): which
/// fields an edit changed, how a pending edit is laid onto a newer server
/// row, and the UPDATE body that carries only those fields.
Run _run({
  Duration duration = const Duration(minutes: 30),
  double distance = 5000,
  String? routeId,
  Map<String, dynamic>? metadata,
  List<Waypoint> track = const [],
}) => Run(
  id: 'run-1',
  startedAt: DateTime.utc(2026, 9, 1, 7),
  duration: duration,
  distanceMetres: distance,
  track: track,
  routeId: routeId,
  source: RunSource.app,
  metadata: metadata,
);

void main() {
  group('changedRunFields', () {
    test('names each changed column and bag key, nothing else', () {
      final before = _run(metadata: {'title': 'Easy', 'notes': 'flat'});
      final after = _run(
        distance: 5100,
        metadata: {'title': 'Tempo', 'notes': 'flat'},
      );
      expect(changedRunFields(before, after), {
        RunEditField.distanceM,
        RunEditField.metadata('title'),
      });
    });

    test('a removed key and an added key both count', () {
      final before = _run(metadata: {'notes': 'flat'});
      final after = _run(metadata: {'title': 'Tempo'});
      expect(changedRunFields(before, after), {
        RunEditField.metadata('notes'),
        RunEditField.metadata('title'),
      });
    });

    test('stashes and the device write clock are never an edit', () {
      final before = _run(
        metadata: {
          'title': 'Easy',
          MetadataKeys.serverUpdatedAt: '2026-09-01T07:00:00.000001+00:00',
          MetadataKeys.lastModifiedAt: '2026-09-01T07:00:00.000Z',
          MetadataKeys.trackUrl: 'u/run-1.json.gz',
        },
      );
      final after = _run(
        metadata: {
          'title': 'Easy',
          MetadataKeys.serverUpdatedAt: '2026-09-02T07:00:00+00:00',
          MetadataKeys.lastModifiedAt: '2026-09-03T07:00:00.000Z',
        },
      );
      expect(changedRunFields(before, after), isEmpty);
    });

    test('nested bag values compare by content', () {
      final before = _run(
        metadata: {
          'laps': [
            {'n': 1, 'm': 1000},
          ],
        },
      );
      final after = _run(
        metadata: {
          'laps': [
            {'n': 1, 'm': 1000},
          ],
        },
      );
      expect(changedRunFields(before, after), isEmpty);
    });
  });

  group('applyRunEditFields', () {
    test('keeps the server change to another field and the local edit', () {
      final local = _run(metadata: {'title': 'Phone title', 'notes': 'old'});
      final server = _run(
        distance: 5200,
        metadata: {
          'title': 'Old title',
          'notes': 'Web notes',
          MetadataKeys.serverUpdatedAt: '2026-09-02T08:00:00.123456+00:00',
        },
      );
      final merged = applyRunEditFields(
        local: local,
        server: server,
        fields: {RunEditField.metadata('title')},
      );
      expect(merged.metadata?['title'], 'Phone title');
      expect(
        merged.metadata?['notes'],
        'Web notes',
        reason: 'a field the local edit did not touch is the server\'s',
      );
      expect(merged.distanceMetres, 5200);
      expect(
        serverUpdatedAtOf(merged),
        '2026-09-02T08:00:00.123456+00:00',
        reason: 'the merged copy is based on the server row it came from',
      );
    });

    test('a key the local edit removed is removed from the server row', () {
      final merged = applyRunEditFields(
        local: _run(metadata: {'title': 'T'}),
        server: _run(metadata: {'title': 'T', 'notes': 'server notes'}),
        fields: {RunEditField.metadata('notes')},
      );
      expect(merged.metadata?.containsKey('notes'), isFalse);
    });

    test('a column edit wins over the server value for that column', () {
      final merged = applyRunEditFields(
        local: _run(duration: const Duration(minutes: 41)),
        server: _run(duration: const Duration(minutes: 30), distance: 7000),
        fields: {RunEditField.durationS},
      );
      expect(merged.duration, const Duration(minutes: 41));
      expect(merged.distanceMetres, 7000);
    });

    test('the local track survives a pulled row that carries none', () {
      const wp = Waypoint(lat: 1, lng: 2);
      final merged = applyRunEditFields(
        local: _run(track: const [wp, wp]),
        server: _run(),
        fields: {RunEditField.distanceM},
      );
      expect(merged.track, hasLength(2));
    });
  });

  group('runEditPatch', () {
    test('a bag key sends the persisted bag, without the stashes', () {
      final run = _run(
        metadata: {
          'title': 'Tempo',
          MetadataKeys.serverUpdatedAt: '2026-09-02T08:00:00+00:00',
          MetadataKeys.lastModifiedAt: '2026-09-02T08:00:00.000Z',
        },
      );
      final patch = runEditPatch(run, {
        RunEditField.metadata('title'),
      }, userId: 'user-1');
      expect(patch.keys, [RunRow.colMetadata]);
      expect(patch[RunRow.colMetadata], {'title': 'Tempo'});
    });

    test('a promoted key sends its column as well', () {
      final run = _run(metadata: {'title': 'Tempo', MetadataKeys.isDnf: true});
      final patch = runEditPatch(run, {
        RunEditField.metadata(MetadataKeys.isDnf),
      }, userId: 'user-1');
      expect(patch[RunRow.colIsDnf], true);
      expect(patch.containsKey(RunRow.colMetadata), isTrue);
    });

    test('a column edit sends only that column', () {
      final patch = runEditPatch(_run(distance: 5100), {
        RunEditField.distanceM,
      }, userId: 'user-1');
      expect(patch, {RunRow.colDistanceM: 5100.0});
    });
  });

  group('PendingRunEdit', () {
    test('round-trips through its sidecar form, base string untouched', () {
      final edit = PendingRunEdit(
        fields: {RunEditField.metadata('title'), RunEditField.distanceM},
        baseUpdatedAt: '2026-09-02T08:00:00.123456+00:00',
      );
      final back = PendingRunEdit.fromJson(edit.toJson())!;
      expect(back.fields, edit.fields);
      expect(back.baseUpdatedAt, '2026-09-02T08:00:00.123456+00:00');
    });

    test('a malformed entry reads as no pending edit', () {
      expect(PendingRunEdit.fromJson(null), isNull);
      expect(PendingRunEdit.fromJson({'fields': 'title'}), isNull);
      expect(PendingRunEdit.fromJson({'fields': <String>[]}), isNull);
    });
  });

  test('runMetadataForRow never persists the client-only keys', () {
    final bag = runMetadataForRow({
      'title': 'Tempo',
      MetadataKeys.serverUpdatedAt: '2026-09-02T08:00:00+00:00',
      MetadataKeys.lastModifiedAt: '2026-09-02T08:00:00.000Z',
    });
    expect(bag, {'title': 'Tempo'});
  });
}

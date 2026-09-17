import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/gym_compose_draft.dart';

GymComposeDraft _draft({
  String title = 'Leg day',
  List<GymComposeDraftExercise> exercises = const [],
}) =>
    GymComposeDraft(
      title: title,
      isPublic: false,
      savedAt: DateTime.utc(2026, 9, 17, 10, 30),
      exercises: exercises,
    );

void main() {
  late Directory dir;
  late GymComposeDraftStore store;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('gym_compose_draft_');
    store = GymComposeDraftStore();
    await store.init(overrideDirectory: dir);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('a half-typed composer round-trips through disk verbatim', () async {
    await store.write(_draft(
      exercises: [
        const GymComposeDraftExercise(
          name: 'Squat',
          sets: [
            // Mid-edit text a parser would reject: what comes back has to be
            // what was on screen, not a number someone re-rendered.
            GymComposeDraftSet(reps: '5', weight: '140.', rpe: '', setType: 'working'),
            GymComposeDraftSet(reps: '', weight: '', setType: 'dropset'),
          ],
        ),
        // An exercise with no name yet — the case a gym_workouts row could
        // never carry, because `_buildSets` drops it.
        const GymComposeDraftExercise(
          name: '',
          sets: [GymComposeDraftSet(reps: '8')],
        ),
      ],
    ));

    final back = await store.read();
    expect(back, isNotNull);
    expect(back!.title, 'Leg day');
    expect(back.isPublic, isFalse);
    expect(back.exercises, hasLength(2));
    expect(back.exercises[0].name, 'Squat');
    expect(back.exercises[0].sets[0].weight, '140.');
    expect(back.exercises[0].sets[1].setType, 'dropset');
    expect(back.exercises[1].name, '');
    expect(back.exercises[1].sets.single.reps, '8');
  });

  test('clear removes the draft', () async {
    await store.write(_draft());
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('a corrupt record answers null and is cleared, not re-read forever',
      () async {
    File('${dir.path}/draft.json').writeAsStringSync('{not json');
    expect(await store.read(), isNull);
    expect(File('${dir.path}/draft.json').existsSync(), isFalse);
  });

  test('a record with no saved_at is unreadable, so it is cleared', () async {
    File('${dir.path}/draft.json')
        .writeAsStringSync(jsonEncode({'title': 'x', 'exercises': []}));
    expect(await store.read(), isNull);
    expect(File('${dir.path}/draft.json').existsSync(), isFalse);
  });

  test('an untouched composer is not content worth offering back', () {
    expect(_draft(title: '').hasContent, isFalse);
    expect(
      _draft(title: '', exercises: [
        const GymComposeDraftExercise(sets: [GymComposeDraftSet()]),
      ]).hasContent,
      isFalse,
    );
    expect(
      _draft(title: '', exercises: [
        const GymComposeDraftExercise(sets: [GymComposeDraftSet(reps: '5')]),
      ]).hasContent,
      isTrue,
    );
    expect(_draft().hasContent, isTrue);
  });

  test('an uninitialised store degrades to inert rather than throwing',
      () async {
    // No platform channel under a plain test, so path_provider fails and the
    // store never resolves a directory. Every entry point must still answer.
    final inert = GymComposeDraftStore();
    expect(await inert.read(), isNull);
    await inert.write(_draft());
    await inert.clear();
  });
}

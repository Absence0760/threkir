// The home-screen widget's week snapshot: the builder held to the shared
// fixture both widgets read (`fixtures/today_widget_snapshot.json`), each day
// state, the seven-day window, units, and the bridge's diff and sign-out.

import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale, ChangeNotifier;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/today_widget.dart';
import '../lib/training_service.dart';

final Map<String, dynamic> _fixture =
    jsonDecode(
          File('../../fixtures/today_widget_snapshot.json').readAsStringSync(),
        )
        as Map<String, dynamic>;

const _planId = '6f1c2a3b-0000-4000-8000-000000000001';

String _wid(int n) =>
    '6f1c2a3b-0000-4000-8000-${n.toString().padLeft(12, '0')}';

final _en = lookupAppLocalizations(const Locale('en'));

PlanWorkoutRow _workout(
  int n, {
  required DateTime date,
  String kind = 'easy',
  double? distanceM,
  int? durationS,
  int? paceSecPerKm,
  String? completedRunId,
  bool manuallyCompleted = false,
  DateTime? skippedAt,
  String? raceName,
}) => PlanWorkoutRow(
  id: _wid(n),
  weekId: 'wk-1',
  scheduledDate: date,
  kind: kind,
  targetDistanceM: distanceM,
  targetDurationSeconds: durationS,
  targetPaceSecPerKm: paceSecPerKm,
  completedRunId: completedRunId,
  manuallyCompleted: manuallyCompleted,
  skippedAt: skippedAt,
  raceName: raceName,
);

ActivePlanOverview _overview(List<PlanWorkoutRow> workouts) =>
    ActivePlanOverview(
      plan: TrainingPlanRow(
        id: _planId,
        userId: 'u1',
        name: 'Autumn 10k',
        goalEvent: '10k',
        goalDistanceM: 10000,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 10, 24),
        daysPerWeek: 5,
        status: 'active',
        source: 'app',
        isTemplate: false,
        isPublicTemplate: false,
      ),
      weeks: const [],
      workouts: workouts,
      todayWorkout: null,
      completionPct: 0,
      currentWeekIndex: 0,
    );

/// The week the fixture's `typical` snapshot was written from: one of each
/// day state, plus rows either side of the window that must not appear.
ActivePlanOverview _typicalWeek() => _overview([
  _workout(1, date: DateTime(2026, 10, 17), kind: 'tempo', distanceM: 5000),
  _workout(
    2,
    date: DateTime(2026, 10, 18),
    kind: 'tempo',
    distanceM: 8000,
    paceSecPerKm: 285,
  ),
  _workout(3, date: DateTime(2026, 10, 19), kind: 'rest'),
  _workout(
    4,
    date: DateTime(2026, 10, 20),
    kind: 'easy',
    distanceM: 6000,
    completedRunId: 'run-1',
  ),
  _workout(
    5,
    date: DateTime(2026, 10, 21),
    kind: 'recovery',
    durationS: 2700,
    skippedAt: DateTime(2026, 10, 21, 7),
  ),
  _workout(
    6,
    date: DateTime(2026, 10, 23),
    kind: 'long',
    distanceM: 16000,
    paceSecPerKm: 330,
  ),
  _workout(
    7,
    date: DateTime(2026, 10, 24),
    kind: 'race',
    distanceM: 10000,
    raceName: 'Autumn 10k',
  ),
  _workout(8, date: DateTime(2026, 10, 25), kind: 'easy', distanceM: 5000),
]);

final _now = DateTime(2026, 10, 18, 9, 30);

Map<String, dynamic> _wire(Map<String, Object> m) =>
    jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

Map<String, dynamic> _withoutStamp(Map<String, dynamic> m) =>
    Map.of(m)..remove('written_at_ms');

List<Map<String, dynamic>> _days(Map<String, Object> snapshot) =>
    (_wire(snapshot)['days'] as List).cast<Map<String, dynamic>>();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildTodayWidgetSnapshot', () {
    test('the typical week is the fixture both widgets read', () {
      final built = buildTodayWidgetSnapshot(
        _typicalWeek(),
        now: _now,
        l10n: _en,
        unit: DistanceUnit.km,
      );
      final snapshots = _fixture['snapshots'] as Map<String, dynamic>;
      expect(
        _withoutStamp(_wire(built)),
        _withoutStamp(snapshots['typical'] as Map<String, dynamic>),
      );
    });

    test('no plan is the fixture no-plan snapshot', () {
      final built = buildTodayWidgetSnapshot(
        null,
        now: _now,
        l10n: _en,
        unit: DistanceUnit.km,
      );
      final snapshots = _fixture['snapshots'] as Map<String, dynamic>;
      expect(
        _withoutStamp(_wire(built)),
        _withoutStamp(snapshots['no_plan'] as Map<String, dynamic>),
      );
    });

    test('version, stamp and plan id', () {
      final built = _wire(
        buildTodayWidgetSnapshot(
          _typicalWeek(),
          now: _now,
          l10n: _en,
          unit: DistanceUnit.km,
        ),
      );
      expect(built['v'], kTodayWidgetSnapshotVersion);
      expect(built['written_at_ms'], _now.millisecondsSinceEpoch);
      expect(built['plan_id'], _planId);
    });

    test('seven ascending local days from the write day', () {
      final days = _days(
        buildTodayWidgetSnapshot(
          _typicalWeek(),
          now: _now,
          l10n: _en,
          unit: DistanceUnit.km,
        ),
      );
      expect(days.map((d) => d['date']), [
        '2026-10-18',
        '2026-10-19',
        '2026-10-20',
        '2026-10-21',
        '2026-10-22',
        '2026-10-23',
        '2026-10-24',
      ]);
    });

    test('each day state, and the ids only a session carries', () {
      final days = _days(
        buildTodayWidgetSnapshot(
          _typicalWeek(),
          now: _now,
          l10n: _en,
          unit: DistanceUnit.km,
        ),
      );
      expect(days.map((d) => d['state']), [
        'workout',
        'rest',
        'done',
        'skipped',
        'none',
        'workout',
        'workout',
      ]);
      expect(days[0]['plan_workout_id'], _wid(2));
      expect(days[1].containsKey('plan_workout_id'), isFalse);
      expect(days[2]['plan_workout_id'], _wid(4));
      expect(days[3]['plan_workout_id'], _wid(5));
      expect(days[4].containsKey('plan_workout_id'), isFalse);
      expect(days[1]['title'], 'Rest day');
      expect(days[4]['title'], '');
      expect(days[6]['title'], 'Autumn 10k');
    });

    test('a window across a DST change keeps one entry per date', () {
      // Europe and North America both change clocks inside this week; the
      // dates must stay consecutive whatever zone the test runs in.
      final days = _days(
        buildTodayWidgetSnapshot(
          null,
          now: DateTime(2026, 10, 30, 23, 59),
          l10n: _en,
          unit: DistanceUnit.km,
        ),
      );
      expect(days.map((d) => d['date']), [
        '2026-10-30',
        '2026-10-31',
        '2026-11-01',
        '2026-11-02',
        '2026-11-03',
        '2026-11-04',
        '2026-11-05',
      ]);
    });

    test('a session still to do outranks a done one on the same day', () {
      final day = DateTime(2026, 10, 18);
      final days = _days(
        buildTodayWidgetSnapshot(
          _overview([
            _workout(
              1,
              date: day,
              kind: 'easy',
              distanceM: 5000,
              manuallyCompleted: true,
            ),
            _workout(2, date: day, kind: 'tempo', distanceM: 8000),
          ]),
          now: _now,
          l10n: _en,
          unit: DistanceUnit.km,
        ),
      );
      expect(days.first['state'], 'workout');
      expect(days.first['plan_workout_id'], _wid(2));
    });

    test('a hand-marked session is done', () {
      final days = _days(
        buildTodayWidgetSnapshot(
          _overview([
            _workout(
              1,
              date: DateTime(2026, 10, 18),
              distanceM: 5000,
              manuallyCompleted: true,
            ),
          ]),
          now: _now,
          l10n: _en,
          unit: DistanceUnit.km,
        ),
      );
      expect(days.first['state'], 'done');
    });

    test('miles convert the distance and the pace', () {
      final days = _days(
        buildTodayWidgetSnapshot(
          _typicalWeek(),
          now: _now,
          l10n: _en,
          unit: DistanceUnit.mi,
        ),
      );
      // 8000 m = 4.97 mi; 285 s/km = 458.66 s/mi = 7:39.
      expect(days.first['detail'], '4.97 mi · 7:39 /mi');
      final km = _days(
        buildTodayWidgetSnapshot(
          _typicalWeek(),
          now: _now,
          l10n: _en,
          unit: DistanceUnit.km,
        ),
      );
      expect(km.first['detail'], '8.00 km · 4:45 /km');
    });

    test('a timed session with no distance shows its minutes', () {
      expect(
        todayWidgetDetail(
          _workout(1, date: _now, kind: 'recovery', durationS: 2700),
          _en,
          DistanceUnit.km,
        ),
        '45 min',
      );
    });

    test('labels are the catalogue strings of the given locale', () {
      final de = lookupAppLocalizations(const Locale('de'));
      final labels =
          _wire(
                buildTodayWidgetSnapshot(
                  null,
                  now: _now,
                  l10n: de,
                  unit: DistanceUnit.km,
                ),
              )['labels']
              as Map;
      expect(labels['header'], de.phoneSurfaceWidgetHeader);
      expect(labels['rest_day'], de.phoneSurfaceWidgetRestDay);
      expect(labels.keys, {
        'header',
        'no_plan',
        'no_plan_action',
        'nothing_scheduled',
        'stale',
        'rest_day',
        'done',
        'skipped',
      });
    });
  });

  group('TodayWidgetBridge', () {
    final calls = <MethodCall>[];
    late Object? Function(MethodCall) reply;

    setUp(() {
      calls.clear();
      reply = (_) => null;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      TodayWidgetBridge().resetForTest();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(TodayWidgetBridge.channelName),
            (call) async {
              calls.add(call);
              return reply(call);
            },
          );
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(TodayWidgetBridge.channelName),
            null,
          );
    });

    test('update carries the snapshot json', () async {
      await TodayWidgetBridge().publish(_typicalWeek(), now: _now);
      expect(calls.single.method, 'update');
      final json = (calls.single.arguments as Map)['snapshot_json'] as String;
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['plan_id'], _planId);
      expect(decoded['written_at_ms'], _now.millisecondsSinceEpoch);
    });

    test('an identical week is not rewritten, even a minute later', () async {
      await TodayWidgetBridge().publish(_typicalWeek(), now: _now);
      await TodayWidgetBridge().publish(
        _typicalWeek(),
        now: _now.add(const Duration(minutes: 1)),
      );
      expect(calls, hasLength(1));
    });

    test('a changed week or a new day is rewritten', () async {
      await TodayWidgetBridge().publish(_typicalWeek(), now: _now);
      await TodayWidgetBridge().publish(null, now: _now);
      await TodayWidgetBridge().publish(
        null,
        now: _now.add(const Duration(days: 1)),
      );
      expect(calls, hasLength(3));
    });

    test('a refused write is retried on the next publish', () async {
      reply = (_) => throw PlatformException(code: 'boom');
      await TodayWidgetBridge().publish(_typicalWeek(), now: _now);
      reply = (_) => null;
      await TodayWidgetBridge().publish(_typicalWeek(), now: _now);
      expect(calls, hasLength(2));
    });

    test('a missing native side does not throw', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(TodayWidgetBridge.channelName),
            null,
          );
      await TodayWidgetBridge().publish(_typicalWeek(), now: _now);
    });

    test('clear drops the snapshot and the week it was built from', () async {
      await TodayWidgetBridge().publish(_typicalWeek(), now: _now);
      await TodayWidgetBridge().clear();
      await TodayWidgetBridge().refresh();
      expect(calls.map((c) => c.method), ['update', 'clear']);
    });

    test('a refresh with nothing changed writes nothing', () async {
      TodayWidgetBridge().clock = () => _now;
      await TodayWidgetBridge().publish(_typicalWeek());
      await TodayWidgetBridge().refresh();
      expect(calls, hasLength(1));
    });

    test(
      'refreshOn re-publishes the last week when its source notifies',
      () async {
        final source = ChangeNotifier();
        TodayWidgetBridge().refreshOn(source);
        TodayWidgetBridge().clock = () => _now;
        await TodayWidgetBridge().publish(_typicalWeek());
        TodayWidgetBridge().clock = () => _now.add(const Duration(days: 1));
        source.notifyListeners();
        await Future<void>.delayed(Duration.zero);
        expect(calls, hasLength(2));
        final json = (calls.last.arguments as Map)['snapshot_json'] as String;
        final decoded = jsonDecode(json) as Map<String, dynamic>;
        expect(decoded['plan_id'], _planId);
        expect((decoded['days'] as List).first['date'], '2026-10-19');
        source.dispose();
      },
    );

    test('a platform without a widget writes nothing', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await TodayWidgetBridge().publish(_typicalWeek(), now: _now);
      await TodayWidgetBridge().clear();
      expect(calls, isEmpty);
    });
  });
}

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/local_gym_store.dart';
import '../lib/offline_sync_store.dart' show SyncState;
import '../lib/preferences.dart';
import '../lib/settings_sync.dart';
import '../lib/training_service.dart' show ActivePlanOverview;
import '../lib/training_load_inputs.dart';

/// Answers [effective] from a fixed map and never touches Supabase.
class _FakeSettingsService extends SettingsService {
  _FakeSettingsService(this._values)
      : super(deviceId: 'test-device', platform: 'android');

  final Map<String, dynamic> _values;

  @override
  T? effective<T>(String key, {T? fallback}) =>
      _values.containsKey(key) ? _values[key] as T? : fallback;
}

class _FakeSettingsSync extends SettingsSyncService {
  _FakeSettingsSync(this._service) : super(preferences: Preferences());

  final SettingsService? _service;

  @override
  SettingsService? get service => _service;
}

SettingsSyncService _sync(Map<String, dynamic> values) =>
    _FakeSettingsSync(_FakeSettingsService(values));

StoredGymWorkout _workout(
  String id, {
  String? startedAt,
  List<Map<String, dynamic>> sets = const [],
  SyncState state = SyncState.synced,
}) =>
    StoredGymWorkout(
      row: {'id': id, 'started_at': startedAt},
      sets: sets,
      syncState: state,
    );

LocalGymStore _store(List<StoredGymWorkout> workouts) {
  final store = LocalGymStore();
  for (final w in workouts) {
    store.rowsById[w.id] = w;
  }
  return store;
}

void main() {
  group('excludesGymFromReadiness', () {
    test('is false with no settings service', () {
      expect(excludesGymFromReadiness(null), isFalse);
      expect(excludesGymFromReadiness(_FakeSettingsSync(null)), isFalse);
    });

    test('is false when the key is unset or false', () {
      expect(excludesGymFromReadiness(_sync({})), isFalse);
      expect(
        excludesGymFromReadiness(
            _sync({SettingsKeys.excludeGymFromReadiness: false})),
        isFalse,
      );
    });

    test('is true only when the runner opted out', () {
      expect(
        excludesGymFromReadiness(
            _sync({SettingsKeys.excludeGymFromReadiness: true})),
        isTrue,
      );
    });
  });

  group('hrPrefsOf', () {
    test('is an empty model with no settings', () {
      final prefs = hrPrefsOf(null);
      expect(prefs.restingHrBpm, isNull);
      expect(prefs.maxHrBpm, isNull);
    });

    test('reads resting and max HR from the bag', () {
      final prefs = hrPrefsOf(_sync({
        SettingsKeys.restingHrBpm: 48,
        SettingsKeys.maxHrBpm: 186,
      }));
      expect(prefs.restingHrBpm, 48);
      expect(prefs.maxHrBpm, 186);
    });
  });

  group('weekStartDayOf', () {
    test('defaults to monday with no settings or no key', () {
      expect(weekStartDayOf(null), 'monday');
      expect(weekStartDayOf(_FakeSettingsSync(null)), 'monday');
      expect(weekStartDayOf(_sync({})), 'monday');
    });

    for (final day in const [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ]) {
      test('returns the configured $day', () {
        expect(weekStartDayOf(_sync({SettingsKeys.weekStartDay: day})), day);
      });
    }
  });

  group('liftsForLoad', () {
    test('is empty for an empty store', () {
      expect(liftsForLoad(LocalGymStore()), isEmpty);
    });

    test('keeps one lift per dated live workout with its sets', () {
      final store = _store([
        _workout('a', startedAt: '2026-11-10T07:00:00Z', sets: [
          {'reps': 5, 'weight_kg': 100, 'rpe': 8},
          {'reps': 5, 'weight_kg': 102.5},
        ]),
        _workout('b', startedAt: '2026-11-11T18:30:00Z', sets: [
          {'reps': 12},
        ]),
        _workout('no-date', sets: [
          {'reps': 8, 'weight_kg': 40},
        ]),
        _workout('deleted',
            startedAt: '2026-11-09T07:00:00Z',
            state: SyncState.pendingDelete,
            sets: [
              {'reps': 3, 'weight_kg': 140},
            ]),
        _workout('no-sets', startedAt: '2026-11-08T07:00:00Z'),
      ]);

      final lifts = liftsForLoad(store);
      final byDay = {
        for (final l in lifts) l.startedAt.toUtc().toIso8601String(): l,
      };

      expect(lifts, hasLength(2),
          reason: 'undated, tombstoned and set-less workouts carry no load');
      final a = byDay['2026-11-10T07:00:00.000Z']!;
      expect(a.sets, hasLength(2));
      expect(a.sets.first.reps, 5);
      expect(a.sets.first.weightKg, 100);
      expect(a.sets.first.rpe, 8);
      expect(a.sets.last.weightKg, 102.5);
      expect(a.sets.last.rpe, isNull);
      final b = byDay['2026-11-11T18:30:00.000Z']!;
      expect(b.sets.single.reps, 12);
      expect(b.sets.single.weightKg, isNull);
    });
  });

  group('leadPlanWorkoutsOf', () {
    test('is null without an active plan', () {
      expect(leadPlanWorkoutsOf(null), isNull);
    });

    test('maps each plan workout to the week-lead shape', () {
      final skipped = DateTime.utc(2026, 11, 11, 9);
      final plan = ActivePlanOverview(
        plan: TrainingPlanRow(
          id: 'plan-1',
          userId: 'u1',
          name: 'Spring Half',
          goalEvent: 'distance_half',
          goalDistanceM: 21097.5,
          startDate: DateTime(2026, 11, 2),
          endDate: DateTime(2026, 12, 20),
          daysPerWeek: 4,
          status: 'active',
          source: 'generated',
          isTemplate: false,
          isPublicTemplate: false,
        ),
        weeks: [
          PlanWeekRow(
            id: 'wk-1',
            planId: 'plan-1',
            weekIndex: 1,
            phase: 'build',
            targetVolumeM: 30000,
          ),
        ],
        workouts: [
          PlanWorkoutRow(
            id: 'w1',
            weekId: 'wk-1',
            scheduledDate: DateTime(2026, 11, 10),
            kind: 'easy',
            targetDistanceM: 6000,
            manuallyCompleted: true,
          ),
          PlanWorkoutRow(
            id: 'w2',
            weekId: 'wk-1',
            scheduledDate: DateTime(2026, 11, 11),
            kind: 'tempo',
            targetDistanceM: 8000,
            manuallyCompleted: false,
            skippedAt: skipped,
          ),
        ],
        todayWorkout: null,
        completionPct: 0,
        currentWeekIndex: 1,
      );

      final lead = leadPlanWorkoutsOf(plan)!;
      expect(lead, hasLength(2));
      expect(lead[0].id, 'w1');
      expect(lead[0].scheduledDate, '2026-11-10');
      expect(lead[0].kind, 'easy');
      expect(lead[0].targetDistanceM, 6000);
      expect(lead[0].manuallyCompleted, isTrue);
      expect(lead[0].skippedAt, isNull);
      expect(lead[1].scheduledDate, '2026-11-11');
      expect(lead[1].skippedAt, skipped.toIso8601String());
    });
  });
}

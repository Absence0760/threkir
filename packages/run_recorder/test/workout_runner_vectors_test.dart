// The step-runner vectors the watch ports are held to
// (`fixtures/watch_workout_payload.json` § runner_vectors). This runner is the
// reference: the Kotlin port (Wear OS `WorkoutRunnerTest.kt`) and the Swift
// port (watchOS `WatchWorkoutRunnerTests.swift`) replay the same totals and
// must produce the same transitions, end-of-step warnings and results. If a
// vector here fails, the reference moved and every port is now wrong.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:run_recorder/run_recorder.dart';

const _kinds = {
  'warmup': WorkoutStepKind.warmup,
  'rep': WorkoutStepKind.rep,
  'recovery': WorkoutStepKind.recovery,
  'walk': WorkoutStepKind.walk,
  'steady': WorkoutStepKind.steady,
  'cooldown': WorkoutStepKind.cooldown,
};

WorkoutStep _step(Map<String, dynamic> j) => WorkoutStep(
      kind: _kinds[j['kind']]!,
      repIndex: j['rep_index'] as int?,
      repTotal: j['rep_total'] as int?,
      targetDistanceMetres: (j['distance_m'] as num?)?.toDouble() ?? 0,
      targetDurationSec: j['duration_s'] as int?,
      targetPaceSecPerKm: j['pace_s_per_km'] as int,
      toleranceSecPerKm: j['tolerance_s_per_km'] as int,
      label: j['kind'] as String,
    );

/// The events the vectors pin. Halfway and pace drift are left out on
/// purpose: neither watch port fires them (§354's reasoning for the halfway
/// cue; drift is clock-rate-limited and asserted per port).
String? _token(WorkoutExecEvent e) => switch (e) {
      StepTransitionEvent(:final currentIndex) => 'transition:$currentIndex',
      StepProgressEvent(kind: StepProgressKind.lastFiftyMetres) ||
      StepProgressEvent(kind: StepProgressKind.lastTenSeconds) =>
        'warning',
      WorkoutCompleteEvent() => 'complete',
      _ => null,
    };

void main() {
  final fixture = jsonDecode(
    File('../../fixtures/watch_workout_payload.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  for (final v in (fixture['runner_vectors'] as List).cast<Map<String, dynamic>>()) {
    test(v['name'], () async {
      final runner = WorkoutRunner(
        steps: [
          for (final s in (v['steps'] as List).cast<Map<String, dynamic>>())
            _step(s),
        ],
      );
      final seen = <String>[];
      final sub = runner.events.listen((e) {
        final t = _token(e);
        if (t != null) seen.add(t);
      });

      for (final t in (v['ticks'] as List).cast<Map<String, dynamic>>()) {
        seen.clear();
        runner.onSnapshot(RunSnapshot(
          elapsed: Duration(seconds: t['elapsed_s'] as int),
          distanceMetres: (t['distance_m'] as num).toDouble(),
        ));
        if (t['skip'] == true) runner.skipStep();
        await Future<void>.delayed(Duration.zero);
        expect(seen, t['events'], reason: 'tick $t');
        expect(runner.currentStepIndex, t['index_after'], reason: 'tick $t');
      }

      final results = runner.snapshotResults();
      final want = (v['results'] as List).cast<Map<String, dynamic>>();
      expect(results, hasLength(want.length));
      for (var i = 0; i < want.length; i++) {
        final got = results[i].toJson();
        for (final key in [
          'step_index',
          'kind',
          'status',
          'duration_s',
          'actual_pace_sec_per_km',
        ]) {
          expect(got[key], want[i][key], reason: 'result $i $key');
        }
        expect(
          got['actual_distance_m'] as double,
          closeTo((want[i]['actual_distance_m'] as num).toDouble(), 1e-6),
          reason: 'result $i actual_distance_m',
        );
      }
      expect(runner.adherence().name, v['adherence']);
      await sub.cancel();
      runner.dispose();
    });
  }
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/launch_trace.dart';

/// The launch trace gives an iOS watchdog termination (Sentry
/// THREKIR-CLIENT-B, which arrives with no stack) the launch it followed:
/// how long each store took and how much the run store left in memory.
void main() {
  test('time records the phase also when the body throws, and rethrows',
      () async {
    final trace = LaunchTrace();
    expect(await trace.time('ok', () async => 7), 7);
    await expectLater(
      trace.time<void>('boom', () async => throw StateError('x')),
      throwsStateError,
    );
    trace.mark('runs.loaded', {'resident': 3});

    expect(trace.marks.map((m) => m.phase), ['ok', 'boom', 'runs.loaded']);
    for (final m in trace.marks.take(2)) {
      expect(m.data['took_ms'], isA<int>());
      expect(m.data['took_ms']! as int, greaterThanOrEqualTo(0));
    }
    expect(trace.marks.last.breadcrumbData,
        {'at_ms': trace.marks.last.atMs, 'resident': 3});
  });

  test('flush hands every mark over once', () {
    final trace = LaunchTrace()
      ..mark('env')
      ..mark('run_app');
    final seen = <String>[];
    trace.flush((m) => seen.add(m.phase));
    trace.flush((m) => seen.add(m.phase));
    expect(seen, ['env', 'run_app']);
  });

  test('main flushes the trace to Sentry only inside the consent gate', () {
    // Error reporting is opt-out and release-only (`shouldUseSentry`); the
    // trace must follow the same gate rather than start Sentry or queue
    // breadcrumbs for an opted-out launch.
    final src = File('lib/main.dart').readAsStringSync();
    final gate = src.indexOf('if (shouldUseSentry) {');
    final init = src.indexOf('await SentryFlutter.init(', gate);
    final flush = src.indexOf('launchTrace.flush(');
    final orElse = src.indexOf('} else {', init);
    expect(gate, greaterThan(0));
    expect(flush, greaterThan(init));
    expect(flush, lessThan(orElse));
    expect('launchTrace.flush('.allMatches(src), hasLength(1));
  });
}

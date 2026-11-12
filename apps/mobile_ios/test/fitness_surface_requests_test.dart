// Tests for FitnessSurfaceRequests (decisions § 2437): a link elsewhere in
// the app parks a Fitness hub tab for the shell to drain, and where no shell
// is listening openFitnessSurface pushes the caller's fallback screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/fitness_surface_requests.dart';

void main() {
  group('FitnessSurfaceRequests', () {
    test('with nobody listening a request is refused and nothing is parked',
        () {
      final requests = FitnessSurfaceRequests();
      expect(requests.request(FitnessTab.plans), isFalse);
      expect(requests.take(), isNull);
    });

    test('a listener is told, and take hands over the tab once', () {
      final requests = FitnessSurfaceRequests();
      final drained = <FitnessTab?>[];
      requests.addListener(() => drained.add(requests.take()));
      expect(requests.request(FitnessTab.routes), isTrue);
      expect(drained, [FitnessTab.routes]);
      expect(requests.take(), isNull);
    });

    test('the same tab can be asked for twice in a row', () {
      final requests = FitnessSurfaceRequests();
      final drained = <FitnessTab?>[];
      requests.addListener(() => drained.add(requests.take()));
      requests.request(FitnessTab.segments);
      requests.request(FitnessTab.segments);
      expect(drained, [FitnessTab.segments, FitnessTab.segments]);
    });

    test('an undrained request is replaced by the newest one', () {
      final requests = FitnessSurfaceRequests();
      var told = 0;
      requests.addListener(() => told++);
      requests.request(FitnessTab.plans);
      requests.request(FitnessTab.races);
      expect(told, 2);
      expect(requests.take(), FitnessTab.races);
    });
  });

  group('openFitnessSurface', () {
    Future<void> mountAndOpen(WidgetTester tester, FitnessTab tab) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => openFitnessSurface(
                  context,
                  tab,
                  fallback: () => const Scaffold(body: Text('fallback')),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('with a shell listening the tab goes to it and nothing is '
        'pushed', (tester) async {
      final drained = <FitnessTab?>[];
      void listener() => drained.add(fitnessSurfaceRequests.take());
      fitnessSurfaceRequests.addListener(listener);
      addTearDown(() => fitnessSurfaceRequests.removeListener(listener));

      await mountAndOpen(tester, FitnessTab.plans);
      expect(drained, [FitnessTab.plans]);
      expect(find.text('fallback'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('with no shell the fallback screen is pushed', (tester) async {
      await mountAndOpen(tester, FitnessTab.routes);
      expect(find.text('fallback'), findsOneWidget);
      expect(fitnessSurfaceRequests.take(), isNull);
    });
  });
}

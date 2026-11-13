import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: child)),
    );

Widget _view({
  bool loading = false,
  Object? error,
  List<String>? data,
  RefreshCallback? onRefresh,
}) =>
    AsyncView<List<String>>(
      loading: loading,
      error: error,
      data: data,
      isEmpty: (d) => d.isEmpty,
      builder: (_, d) => ListView(children: [for (final s in d) Text(s)]),
      empty: const EmptyState(icon: Icons.inbox, title: 'empty'),
      errorBuilder: (_, e) =>
          ErrorState(message: 'failed', retryLabel: 'retry', onRetry: () {}),
      loadingState: const LoadingState.list(label: 'loading'),
      onRefresh: onRefresh,
    );

void main() {
  testWidgets('content wins, even while refreshing or after a failure',
      (tester) async {
    await _pump(tester, _view(data: ['a'], loading: true, error: 'x'));
    expect(find.text('a'), findsOneWidget);
    expect(find.byType(ListSkeleton), findsNothing);
    expect(find.byType(ErrorState), findsNothing);
  });

  testWidgets('loading with nothing to show is the skeleton', (tester) async {
    await _pump(tester, _view(loading: true, data: const []));
    expect(find.byType(ListSkeleton), findsOneWidget);
    expect(find.bySemanticsLabel('loading'), findsOneWidget);
  });

  testWidgets('a failed read with nothing to show is an error, never empty',
      (tester) async {
    await _pump(tester, _view(error: 'x', data: const []));
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('empty'), findsNothing);
  });

  testWidgets('a loaded empty list is the empty state', (tester) async {
    await _pump(tester, _view(data: const []));
    expect(find.text('empty'), findsOneWidget);
  });

  testWidgets('before the first read it shows the skeleton', (tester) async {
    await _pump(tester, _view());
    expect(find.byType(ListSkeleton), findsOneWidget);
  });

  testWidgets('LoadingState.section takes only its rows\' height',
      (tester) async {
    await _pump(
      tester,
      const SingleChildScrollView(
        child: LoadingState.section(label: 'loading', rows: 2),
      ),
    );
    expect(find.byType(ListSkeleton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('onRefresh', () {
    Future<void> pull(WidgetTester tester, Widget view, Finder target) async {
      await _pump(tester, view);
      await tester.fling(target, const Offset(0, 400), 1000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }

    // Issue #1374 FS-3: an empty or failed list that could not be pulled was a
    // dead end until the person left the screen.
    for (final (name, data, error, target) in [
      ('the empty state', const <String>[], null, find.text('empty')),
      ('the error state', const <String>[], 'x', find.text('failed')),
      ('the rows', const ['a'], null, find.text('a')),
    ]) {
      testWidgets('$name can be pulled to refresh', (tester) async {
        var calls = 0;
        await pull(
          tester,
          _view(
            data: data,
            error: error,
            onRefresh: () async => calls++,
          ),
          target,
        );
        expect(calls, 1);
      });
    }

    testWidgets('the loading skeleton cannot be pulled', (tester) async {
      var calls = 0;
      await _pump(
        tester,
        _view(loading: true, onRefresh: () async => calls++),
      );
      expect(
        tester.widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .notificationPredicate(ScrollUpdateNotification(
          metrics: FixedScrollMetrics(
            minScrollExtent: 0,
            maxScrollExtent: 0,
            pixels: 0,
            viewportDimension: 100,
            axisDirection: AxisDirection.down,
            devicePixelRatio: 1,
          ),
          context: tester.element(find.byType(ListSkeleton)),
        )),
        isFalse,
      );
      expect(calls, 0);
    });

    testWidgets('without onRefresh there is no RefreshIndicator',
        (tester) async {
      await _pump(tester, _view(data: const []));
      expect(find.byType(RefreshIndicator), findsNothing);
    });
  });
}

import 'package:core_models/core_models.dart' as cm;
import 'package:core_models/core_models.dart' show DistanceUnit;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/route_picker_sheet.dart';
import 'three_button_nav_bar.dart';
import 'worst_case_layout.dart';

cm.Route _route(
  String id,
  String name, {
  bool starred = false,
  double distanceM = 5000,
}) => cm.Route(
  id: id,
  userId: 'test-user',
  name: name,
  waypoints: const [
    cm.Waypoint(lat: 51.5, lng: -0.12),
    cm.Waypoint(lat: 51.51, lng: -0.13),
  ],
  distanceMetres: distanceM,
  elevationGainMetres: 50,
  isStarred: starred,
);

/// What [pickRoute] resolved to, once it has.
class _Result {
  bool resolved = false;
  RoutePick? pick;
}

Future<_Result> _open(
  WidgetTester tester,
  List<cm.Route> routes, {
  cm.Route? selected,
  bool offerNoRoute = true,
  Size size = kSheetTestPhone,
  double textScale = 1,
}) async {
  final result = _Result();
  await openSheetOverNavBar(
    tester,
    (context) async {
      result.pick = await pickRoute(
        context,
        routes: routes,
        unit: DistanceUnit.km,
        selected: selected,
        offerNoRoute: offerNoRoute,
      );
      result.resolved = true;
    },
    size: size,
    textScale: textScale,
  );
  return result;
}

/// The value the sheet marks as chosen.
String? _marked(WidgetTester tester) => tester
    .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
    .groupValue;

List<String> _rowTitles(WidgetTester tester) => tester
    .widgetList<RadioListTile<String>>(find.byType(RadioListTile<String>))
    .map((t) => (t.title! as Text).data!)
    .toList();

Rect _sheet(WidgetTester tester) =>
    tester.getRect(find.byType(DraggableScrollableSheet));

void main() {
  group('the route picker sheet', () {
    testWidgets('opens as a bottom sheet with a title and "No route", not a '
        'pushed page', (tester) async {
      await _open(tester, [_route('a', 'Alpha')]);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Choose route'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('route-picker-no-route')),
          matching: find.text('No route'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('opens at about 70% of the screen, not the whole of it', (
      tester,
    ) async {
      await _open(tester, [
        for (var i = 0; i < 30; i++) _route('r$i', 'Route $i'),
      ]);
      final height = kSheetTestPhone.height - kThreeButtonNavBar;
      expect(_sheet(tester).height, lessThan(height * 0.75));
      expect(_sheet(tester).height, greaterThan(height * 0.6));
    });

    testWidgets('focusing the search snaps it to the full height', (
      tester,
    ) async {
      await _open(tester, [
        for (var i = 0; i < 30; i++) _route('r$i', 'Route $i'),
      ]);
      final opened = _sheet(tester).height;
      await tester.tap(find.byKey(const ValueKey('route-picker-search')));
      await tester.pumpAndSettle();
      expect(opened, lessThan(kSheetTestPhone.height * 0.75));
      expect(_sheet(tester).height,
          closeTo(kSheetTestPhone.height - kMinInteractiveDimension, 1));
      expect(
        find.text('Choose route').hitTestable(),
        findsOneWidget,
        reason: 'the title stays on screen above the search',
      );
    });

    testWidgets('scrolling a long library takes the whole screen, with the '
        'search still pinned', (tester) async {
      await _open(tester, [
        for (var i = 0; i < 30; i++) _route('r$i', 'Route ${i + 10}'),
      ]);
      await tester.drag(find.text('Route 12'), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.drag(find.text('Route 15'), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(_sheet(tester).bottom, kSheetTestPhone.height);
      expect(
        find.text('Route 10').hitTestable(),
        findsNothing,
        reason: 'the list scrolled',
      );
      expect(
        find.byKey(const ValueKey('route-picker-search')).hitTestable(),
        findsOneWidget,
      );
    });

    testWidgets('marks the route being followed, the way Guided run marks '
        'its choice', (tester) async {
      final bravo = _route('b', 'Bravo');
      await _open(tester, [_route('a', 'Alpha'), bravo], selected: bravo);
      expect(_marked(tester), 'b');
    });

    testWidgets('with no route followed, "No route" is the marked row', (
      tester,
    ) async {
      await _open(tester, [_route('a', 'Alpha')]);
      expect(_marked(tester), '');
    });

    testWidgets('leaves "No route" out where there is nothing to clear', (
      tester,
    ) async {
      await _open(tester, [_route('a', 'Alpha')], offerNoRoute: false);
      expect(find.byKey(const ValueKey('route-picker-no-route')), findsNothing);
      expect(_marked(tester), isNull);
    });

    testWidgets('starred routes come first, under STARRED then ALL ROUTES', (
      tester,
    ) async {
      await _open(tester, [
        _route('a', 'Alpha'),
        _route('b', 'Bravo', starred: true),
        _route('c', 'Charlie'),
        _route('d', 'Delta', starred: true),
      ]);
      expect(find.text('STARRED'), findsOneWidget);
      expect(find.text('ALL ROUTES'), findsOneWidget);
      expect(_rowTitles(tester), [
        'No route',
        'Bravo',
        'Delta',
        'Alpha',
        'Charlie',
      ]);
    });

    testWidgets('no section headers when nothing is starred', (tester) async {
      await _open(tester, [_route('a', 'Alpha'), _route('b', 'Bravo')]);
      expect(find.text('STARRED'), findsNothing);
      expect(find.text('ALL ROUTES'), findsNothing);
    });

    testWidgets('search filters by a case-insensitive name substring, and '
        'clearing it brings the list back', (tester) async {
      await _open(tester, [
        _route('a', 'River Loop'),
        _route('b', 'Park Trail'),
        _route('c', 'Bridge to Bridge'),
      ]);
      await tester.enterText(
        find.byKey(const ValueKey('route-picker-search')),
        'bridge',
      );
      await tester.pumpAndSettle();
      expect(find.text('Bridge to Bridge'), findsOneWidget);
      expect(find.text('River Loop'), findsNothing);
      expect(find.text('Park Trail'), findsNothing);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('River Loop'), findsOneWidget);
      expect(find.text('Park Trail'), findsOneWidget);
    });

    testWidgets('says so when the search matches nothing', (tester) async {
      await _open(tester, [_route('a', 'Alpha')]);
      await tester.enterText(
        find.byKey(const ValueKey('route-picker-search')),
        'zzzz',
      );
      await tester.pumpAndSettle();
      expect(find.text('No routes match "zzzz"'), findsOneWidget);
    });

    testWidgets('says so when there are no routes at all', (tester) async {
      await _open(tester, const []);
      expect(find.text('No routes saved yet'), findsOneWidget);
    });

    testWidgets('"No route" resolves NoRoutePicked, not a cancel', (
      tester,
    ) async {
      final result = await _open(tester, [
        _route('a', 'Alpha'),
      ], selected: _route('a', 'Alpha'));
      await tester.tap(find.byKey(const ValueKey('route-picker-no-route')));
      await tester.pumpAndSettle();
      expect(result.pick, isA<NoRoutePicked>());
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('a route row resolves that route', (tester) async {
      final result = await _open(tester, [
        _route('a', 'Alpha'),
        _route('b', 'Bravo'),
      ]);
      await tester.tap(find.text('Bravo'));
      await tester.pumpAndSettle();
      final picked = result.pick! as RoutePicked;
      expect(picked.route.id, 'b');
    });

    testWidgets('closing it resolves null, which no caller reads as '
        '"No route"', (tester) async {
      final result = await _open(tester, [_route('a', 'Alpha')]);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(result.resolved, isTrue);
      expect(result.pick, isNull);
    });

    testWidgets('the last row clears the 3-button nav bar at 320 dp and 2x', (
      tester,
    ) async {
      await _open(
        tester,
        [for (var i = 0; i < 12; i++) _route('r$i', 'Route $i')],
        size: kNarrowPhone,
        textScale: 2,
      );
      // Low on the screen, so each drag lands on the list whatever it holds.
      const listPoint = Offset(160, 600);
      await tester.dragFrom(listPoint, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(
        _sheet(tester).bottom,
        kNarrowPhone.height,
        reason: 'the first drag grows the sheet to the full height',
      );
      // A lazy list learns its true end as it builds rows, so the first fling
      // stops at the estimate; the second reaches the real end.
      await tester.dragFrom(listPoint, const Offset(0, -5000));
      await tester.pumpAndSettle();
      await tester.dragFrom(listPoint, const Offset(0, -5000));
      await tester.pumpAndSettle();
      expectAboveNavBar(
        tester,
        find.byKey(const ValueKey('route-picker-route-r9')),
      );
    });
  });

  worstCaseTestWidgets('the route picker sheet', (tester, locale) async {
    await tester.pumpWidget(
      worstCaseApp(
        locale: locale,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => pickRoute(
                  context,
                  routes: [
                    _route(
                      'a',
                      'Riverside loop past the old mill and back',
                      starred: true,
                    ),
                    _route('b', 'Hill repeats', distanceM: 21100),
                  ],
                  unit: DistanceUnit.km,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await walkScrollable(
      tester,
      find
          .descendant(
            of: find.byType(DraggableScrollableSheet),
            matching: find.byType(Scrollable),
          )
          .first,
      'Route picker sheet',
    );
  });
}

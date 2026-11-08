// Home's Today block shows the runner's next `going` club event when it starts
// within 48 hours (decisions § 2388, which reverses § 2285's week; issue
// #1187). The window itself is the server read's; this suite pins that Home
// asks for 48 hours, where the card sits, and that a failed read leaves the
// rest of Home standing.

import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/dashboard_screen.dart';
import '../lib/social_service.dart';
import '../lib/widgets/upcoming_event_card.dart';
import 'pump_until.dart';

class _FakeSocial extends SocialService {
  final EventView? event;
  final bool fails;
  final windows = <Duration>[];
  _FakeSocial({this.event, this.fails = false});

  @override
  Future<EventView?> fetchNextRsvpedEvent(
      {Duration window = const Duration(hours: 48)}) async {
    windows.add(window);
    if (fails) throw StateError('offline');
    return event;
  }
}

EventView _event(DateTime startsAt) => EventView(
      row: EventRow(
        id: 'e1',
        clubId: 'club-1',
        title: 'Saturday Long Run',
        meetLabel: 'Riverside Park',
        startsAt: startsAt,
        durationMin: 60,
        authorId: 'host',
        category: 'run',
        timezone: 'UTC',
        isPublic: true,
      ),
      byday: null,
      attendeeCount: 3,
      viewerRsvp: 'going',
      nextInstanceStart: startsAt,
    );

final _card = find.byKey(const Key('dashboardUpcomingEvent'));
final _lead = find.byKey(const Key('dashboardWeekLead'));

Future<void> _mount(WidgetTester tester, SocialService social,
    {required Finder until}) async {
  tester.view.physicalSize = const Size(400, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  late Directory dir;
  await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    dir = Directory.systemTemp.createTempSync('dashboard_event_');
    final seed = LocalRunStore();
    await seed.init(overrideDirectory: dir);
    await seed.save(Run(
      id: 'r1',
      startedAt: DateTime.now().subtract(const Duration(days: 1)),
      duration: const Duration(minutes: 30),
      distanceMetres: 5000,
      source: RunSource.app,
    ));
    final runStore = LocalRunStore();
    await runStore.init(overrideDirectory: dir);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: DashboardScreen(
        runStore: runStore,
        routeStore: LocalRouteStore(),
        gymStore: LocalGymStore(),
        foodStore: LocalFoodStore(),
        preferences: prefs,
        social: social,
      ),
    ));
  });
  addTearDown(() => dir.deleteSync(recursive: true));
  await pumpUntil(tester, () => until.evaluate().isNotEmpty,
      describe: 'Home to render what the test reads');
}

void main() {
  testWidgets('an event within 48 hours sits in the Today block, asked for '
      'with a 48-hour window', (tester) async {
    final social =
        _FakeSocial(event: _event(DateTime.now().add(const Duration(hours: 20))));
    await _mount(tester, social, until: _card);

    expect(social.windows, isNotEmpty);
    expect(social.windows.every((w) => w == kHomeEventWindow), isTrue);
    expect(kHomeEventWindow, const Duration(hours: 48));
    expect(find.descendant(of: _card, matching: find.text('Saturday Long Run')),
        findsOneWidget);
    double top(Finder f) => tester.getTopLeft(f).dy;
    expect(top(_card), greaterThan(top(_lead)));
    expect(top(_card), lessThan(top(find.text('Trends'))));
  });

  testWidgets('no event in the window, no card', (tester) async {
    await _mount(tester, _FakeSocial(), until: _lead);
    expect(_card, findsNothing);
  });

  testWidgets('a failed read hides only the card', (tester) async {
    final social = _FakeSocial(fails: true);
    await _mount(tester, social, until: _lead);
    await pumpUntil(tester, () => social.windows.isNotEmpty,
        describe: 'the event read to run');
    await tester.pump();
    expect(_card, findsNothing);
    expect(_lead, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

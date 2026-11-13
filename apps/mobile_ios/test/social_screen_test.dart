// ignore_for_file: avoid_relative_lib_imports
// Widget tests for SocialScreen, the Social bottom-nav hub. Pins the hub's
// contract: the five tabs in the order `Feed · Clubs · Events · Challenges ·
// People` (issue #1374, owner decision "Social tabs"), the one app bar with
// the title, Messages (and its unread count) and the bell, the one FAB the
// active tab hands it, and the tab selection a host or a link drives.
//
// Each tab's content is exercised by its own suite (feed_screen_test,
// clubs_screen_test, discover_screen_test, challenges_screen_test,
// people_screen_test); the worst-case layout walk is
// social_hub_tab_bodies_test.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/screens/messages_screen.dart';
import '../lib/screens/social_screen.dart';
import '../lib/social_surface_requests.dart';
import '../lib/training_service.dart';
import 'social_hub_fakes.dart';

late Directory _tmpDir;

Future<SocialScreen> _socialScreen({
  SocialTab initialTab = SocialTab.feed,
  ValueNotifier<SocialTab>? selectedTab,
  int unread = 0,
}) async {
  _tmpDir = Directory.systemTemp.createTempSync('social_screen_test_');
  final store = LocalRouteStore();
  await store.init(overrideDirectory: _tmpDir);
  return SocialScreen(
    api: SocialHubFakeApi(),
    social: SocialHubFakeService(),
    training: TrainingService(),
    routeStore: store,
    initialTab: initialTab,
    selectedTab: selectedTab,
    unreadMessages: FixedUnreadMessages(unread),
  );
}

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

int _index(WidgetTester tester) =>
    tester.widget<TabBar>(find.byType(TabBar)).controller!.index;

Finder _tab(String label) =>
    find.descendant(of: find.byType(TabBar), matching: find.text(label));

void main() {
  setUpAll(() async {
    await ensureSocialTestSupabase();
    await initializeDateFormatting();
    // The Clubs tab reads dotenv['MAPTILER_KEY'] on load.
    dotenv.loadFromString(isOptional: true);
  });

  tearDown(() {
    if (_tmpDir.existsSync()) _tmpDir.deleteSync(recursive: true);
  });

  testWidgets('the strip is Feed · Clubs · Events · Challenges · People',
      (tester) async {
    await tester.pumpWidget(_wrap(await _socialScreen()));
    await tester.pump();

    final labels = [
      for (final t in tester.widgetList<Text>(find.descendant(
          of: find.byType(TabBar), matching: find.byType(Text))))
        t.data,
    ];
    expect(labels, ['Feed', 'Clubs', 'Events', 'Challenges', 'People']);
    // Discover was renamed; Routes moved to Fitness long ago.
    expect(_tab('Discover'), findsNothing);
    expect(_tab('Routes'), findsNothing);
  });

  testWidgets('every SocialTab opens its own tab, and the strip is exactly as '
      'long as the enum', (tester) async {
    for (final tab in SocialTab.values) {
      // Unmount first: pumping another SocialScreen straight over the
      // previous one reuses the element, so the TabController built in
      // initState survives and the next value reads as the last one's tab.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_wrap(await _socialScreen(initialTab: tab)));
      await tester.pump();
      expect(_index(tester), tab.index, reason: '$tab did not open its own tab');
      expect(tester.widget<TabBar>(find.byType(TabBar)).tabs.length,
          SocialTab.values.length);
      if (_tmpDir.existsSync()) _tmpDir.deleteSync(recursive: true);
    }
    expect(SocialTab.values.length, greaterThan(1));
  });

  testWidgets('the one app bar carries the title, Messages and the bell',
      (tester) async {
    await tester.pumpWidget(_wrap(await _socialScreen()));
    await _settle(tester);

    expect(find.byType(AppBar), findsOneWidget);
    expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('Social')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('social-messages')), findsOneWidget);
    expect(find.byTooltip('Messages'), findsOneWidget);
    expect(find.byTooltip('Notifications'), findsOneWidget);
  });

  testWidgets('Messages shows the unread count and says it to a screen reader',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(await _socialScreen(unread: 4)));
    await _settle(tester);

    final badge = tester.widget<Badge>(find.descendant(
        of: find.byKey(const ValueKey('social-messages')),
        matching: find.byType(Badge)));
    expect(badge.isLabelVisible, isTrue);
    // One merged node: the count is read as the button's value, not as a
    // separate node after it.
    final data = tester
        .getSemantics(find.byKey(const ValueKey('social-messages')))
        .getSemanticsData();
    expect(data.tooltip, 'Messages');
    expect(data.value, '4 unread messages');
    expect(data.flagsCollection.isButton, isTrue);
    handle.dispose();
  });

  testWidgets('no unread messages, no badge', (tester) async {
    await tester.pumpWidget(_wrap(await _socialScreen()));
    await _settle(tester);
    final badge = tester.widget<Badge>(find.descendant(
        of: find.byKey(const ValueKey('social-messages')),
        matching: find.byType(Badge)));
    expect(badge.isLabelVisible, isFalse);
  });

  testWidgets('Messages opens the inbox', (tester) async {
    await tester.pumpWidget(_wrap(await _socialScreen()));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('social-messages')));
    await _settle(tester);
    expect(find.byType(MessagesScreen), findsOneWidget);
  });

  testWidgets('the hub shows the active tab\'s primary action as its one FAB',
      (tester) async {
    await tester.pumpWidget(_wrap(await _socialScreen()));
    await _settle(tester);
    expect(find.byType(FloatingActionButton), findsNothing, reason: 'Feed');

    for (final (label, fab) in [
      ('Clubs', 'New club'),
      ('Events', null),
      ('Challenges', 'Create challenge'),
      ('People', null),
      ('Feed', null),
    ]) {
      await tester.ensureVisible(_tab(label));
      await tester.tap(_tab(label));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      if (fab == null) {
        expect(find.byType(FloatingActionButton), findsNothing, reason: label);
      } else {
        expect(find.byType(FloatingActionButton), findsOneWidget,
            reason: label);
        expect(find.widgetWithText(FloatingActionButton, fab), findsOneWidget);
      }
    }
  });

  testWidgets('a host notifier selects the tab, and a tap writes it back',
      (tester) async {
    final selected = ValueNotifier(SocialTab.feed);
    addTearDown(selected.dispose);
    await tester.pumpWidget(
        _wrap(await _socialScreen(selectedTab: selected)));
    await _settle(tester);

    selected.value = SocialTab.challenges;
    await _settle(tester);
    expect(_index(tester), SocialTab.challenges.index);

    await tester.ensureVisible(_tab('Clubs'));
    await tester.tap(_tab('Clubs'));
    await _settle(tester);
    expect(selected.value, SocialTab.clubs);
  });

  testWidgets('a tab keeps its state across a swipe away and back (NS-4)',
      (tester) async {
    await tester.pumpWidget(_wrap(await _socialScreen(
        initialTab: SocialTab.events)));
    await _settle(tester);
    await tester.enterText(find.byType(TextField).first, 'pilates');
    await _settle(tester);

    await tester.tap(_tab('Feed'));
    await _settle(tester);
    await tester.tap(_tab('Events'));
    await _settle(tester);
    expect(find.text('pilates'), findsOneWidget);
  });

  group('openSocialSurface', () {
    testWidgets('with a shell listening, it parks the tab and pushes nothing',
        (tester) async {
      SocialTab? drained;
      void drain() => drained = socialSurfaceRequests.take();
      socialSurfaceRequests.addListener(drain);
      addTearDown(() => socialSurfaceRequests.removeListener(drain));

      final observer = _PushCounter();
      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => openSocialSurface(context, SocialTab.challenges,
                fallback: () => const Text('fallback copy')),
            child: const Text('link'),
          ),
        ),
      ));
      final before = observer.pushes;
      await tester.tap(find.text('link'));
      await tester.pumpAndSettle();

      expect(drained, SocialTab.challenges);
      expect(observer.pushes, before, reason: 'a copy was pushed');
      expect(find.text('fallback copy'), findsNothing);
    });

    testWidgets('with no shell, it pushes the fallback', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => openSocialSurface(context, SocialTab.clubs,
                fallback: () => const Text('fallback copy')),
            child: const Text('link'),
          ),
        ),
      ));
      await tester.tap(find.text('link'));
      await tester.pumpAndSettle();
      expect(find.text('fallback copy'), findsOneWidget);
    });

    test('take() clears the request, so the same tab can be asked twice', () {
      void noop() {}
      socialSurfaceRequests.addListener(noop);
      addTearDown(() => socialSurfaceRequests.removeListener(noop));
      expect(socialSurfaceRequests.request(SocialTab.people), isTrue);
      expect(socialSurfaceRequests.take(), SocialTab.people);
      expect(socialSurfaceRequests.take(), isNull);
    });
  });
}

class _PushCounter extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushes++;
}

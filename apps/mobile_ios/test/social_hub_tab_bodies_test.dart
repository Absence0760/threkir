// ignore_for_file: avoid_relative_lib_imports
// Every Social tab at the worst case the issue #1374 rules name: a 320 dp
// phone, 2x text and Android's 3-button navigation bar. Each tab body is a
// HubTabBody, so the hub draws the one app bar (title, Messages, the bell and
// the strip) and the one FAB; this walks every tab with a row on each, fails
// on an overflow, and checks the hub's FAB sits clear of the nav bar wherever
// a tab has a primary action.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:ui_kit/ui_kit.dart'
    show
        AppSearchField,
        AppSpace,
        EmptyState,
        FilterBar,
        LoadingState,
        PageBarTitle,
        PageHeader;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/screens/challenges_screen.dart';
import '../lib/screens/clubs_screen.dart';
import '../lib/screens/discover_screen.dart';
import '../lib/screens/feed_screen.dart';
import '../lib/screens/people_screen.dart';
import '../lib/screens/social_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import '../lib/widgets/error_state.dart';
import 'social_hub_fakes.dart';
import 'three_button_nav_bar.dart' show kThreeButtonNavBar;
import 'worst_case_layout.dart';

const _phone = Size(320, 640);

void main() {
  setUpAll(() async {
    await ensureSocialTestSupabase();
    await initializeDateFormatting();
    // The Clubs tab reads dotenv['MAPTILER_KEY'] on load.
    dotenv.loadFromString(isOptional: true);
  });

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('social_tabs_'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> pumpHub(
    WidgetTester tester, {
    ApiClient? api,
    SocialService? social,
    double textScale = 2.0,
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: kThreeButtonNavBar);
    tester.view.padding = const FakeViewPadding(bottom: kThreeButtonNavBar);
    addTearDown(tester.view.reset);
    final routeStore = LocalRouteStore();
    await routeStore.init(overrideDirectory: tmp);
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: SocialScreen(
        api: api ?? SocialHubFakeApi(),
        social: social ?? SocialHubFakeService(),
        training: TrainingService(),
        routeStore: routeStore,
        selectedTab: ValueNotifier(SocialTab.feed),
        unreadMessages: FixedUnreadMessages(3),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    final tab =
        find.descendant(of: find.byType(TabBar), matching: find.text(label));
    await tester.ensureVisible(tab);
    await tester.tap(tab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  // The tabs with a primary action, by the label of the FAB the hub shows.
  const fabs = {
    'Clubs': 'New club',
    'Challenges': 'Create challenge',
  };

  testWidgets('every tab fits 320 dp at 2x, with no app bar of its own and '
      'the FAB clear of the 3-button bar', (tester) async {
    await pumpHub(tester);
    for (final label in ['Feed', 'Clubs', 'Events', 'Challenges', 'People']) {
      await openTab(tester, label);
      expect(tester.takeException(), isNull, reason: '$label overflowed');
      expect(find.byType(AppBar), findsOneWidget,
          reason: '$label drew an app bar under the strip');
      final fab = find.byType(FloatingActionButton);
      if (fabs[label] case final text?) {
        expect(find.widgetWithText(FloatingActionButton, text), findsOneWidget,
            reason: '$label\'s primary action is the hub\'s FAB');
        expect(tester.getRect(fab).bottom,
            lessThanOrEqualTo(_phone.height - kThreeButtonNavBar),
            reason: '$label\'s FAB reaches into the nav bar');
        expect(tester.getRect(fab).right, lessThanOrEqualTo(_phone.width));
      } else {
        expect(fab, findsNothing, reason: '$label has no primary action');
      }
    }
  });

  // The same walk in every shipped locale (issue #1374 TO-6), tab by
  // position so no label is spelled in English.
  // Owner finding 11: the hub's large title collapses into its slim bar as a
  // tab scrolls, the strip pinned under it; every tab is walked collapsed
  // too, and the hub's actions stay in reach.
  Future<void> collapse(WidgetTester tester) async {
    await tester.dragFrom(
        tester.getCenter(find.byType(TabBarView)), const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final fade = tester.widget<AnimatedOpacity>(find.descendant(
        of: find.byType(PageBarTitle), matching: find.byType(AnimatedOpacity)));
    expect(fade.opacity, 1, reason: 'collapsed, the bar says the hub name');
    expect(tester.getRect(find.byType(TabBar)).top,
        moreOrLessEquals(tester.getRect(find.byType(AppBar)).bottom),
        reason: 'the strip pins under the bar');
  }

  // Owner feedback (issue #1374, round 2): the title sat under an empty bar
  // row. At rest the large title, Messages and the bell share one row under
  // the status bar, centred on each other, and the strip follows that row.
  worstCaseTestWidgets('Social opens on one title row with Messages and the '
      'bell, the strip right under it', (tester, locale) async {
    await pumpHub(tester, locale: locale);
    final title = find.descendant(
        of: find.byType(PageHeader),
        matching: find.text(l10nFor(locale).navSocial));
    expect(title, findsOneWidget);
    final heading = tester.getRect(title);
    final header = tester.getRect(find.byType(PageHeader));
    expect(header.top, lessThanOrEqualTo(AppSpace.md),
        reason: 'no bar row above the title');
    for (final action in [
      find.byKey(const ValueKey('social-messages')),
      find.byTooltip(l10nFor(locale).notificationBellTooltip),
    ]) {
      expect(action.hitTestable(), findsOneWidget);
      final centre = tester.getCenter(action).dy;
      expect(centre, greaterThan(heading.top));
      expect(centre, lessThan(heading.bottom),
          reason: 'the action sits on the title row');
    }
    expect(find.byType(AppBar).hitTestable(), findsNothing,
        reason: 'no compact bar at rest');
    expect(tester.getRect(find.byType(TabBar)).top,
        greaterThanOrEqualTo(heading.bottom),
        reason: 'the strip follows the title row');
    expectNoOverflow(tester, 'Social at rest');
  });

  worstCaseTestWidgets('every Social tab with the title collapsed',
      (tester, locale) async {
    await pumpHub(tester, locale: locale);
    await collapse(tester);
      expect(find.byKey(const ValueKey('social-messages')).hitTestable(),
          findsOneWidget,
          reason: 'Messages stays in reach with the title collapsed');
      expect(
          find.byTooltip(l10nFor(locale).notificationBellTooltip).hitTestable(),
          findsOneWidget,
          reason: 'the bell stays in reach with the title collapsed');
    final tabs =
        find.descendant(of: find.byType(TabBar), matching: find.byType(Tab));
    for (var i = 0; i < tabs.evaluate().length; i++) {
      final tab = tabs.at(i);
      await tester.ensureVisible(tab);
      await tester.tap(tab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expectNoOverflow(tester, 'Social tab $i collapsed');
    }
  });

  worstCaseTestWidgets('every Social tab', (tester, locale) async {
    await pumpHub(tester, locale: locale);
    final tabs = find.descendant(of: find.byType(TabBar), matching: find.byType(Tab));
    final count = tabs.evaluate().length;
    expect(count, 5);
    for (var i = 0; i < count; i++) {
      final tab = tabs.at(i);
      await tester.ensureVisible(tab);
      await tester.tap(tab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expectNoOverflow(tester, 'Social tab $i');
    }
  });

  testWidgets('the list tabs\' controls are one FilterBar each', (tester) async {
    await pumpHub(tester);
    for (final (label, key) in [
      ('Feed', 'feed-filter-bar'),
      ('Clubs', 'clubs-filter-bar'),
      ('Events', 'events-filter-bar'),
      ('Challenges', 'challenges-filter-bar'),
      ('People', 'people-filter-bar'),
    ]) {
      await openTab(tester, label);
      expect(find.byKey(ValueKey(key)), findsOneWidget,
          reason: '$label\'s controls are not its FilterBar');
      // Every list here can grow, so every one but the feed has a search
      // (issue #1374: Clubs → My clubs had none).
      if (label != 'Feed') {
        expect(
            find.descendant(
                of: find.byKey(ValueKey(key)),
                matching: find.byType(AppSearchField)),
            findsOneWidget,
            reason: '$label has no search');
      }
    }
    await openTab(tester, 'Events');
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('events-filter-bar')),
            matching: find.byType(AppSearchField)),
        findsOneWidget);
    expect(find.byType(FilterBar), findsWidgets);
  });

  testWidgets('the hub\'s top bar fits Messages and the bell at 2x on 320 dp',
      (tester) async {
    await pumpHub(tester);
    expect(tester.takeException(), isNull);
    final messages = find.byKey(const ValueKey('social-messages'));
    expect(messages, findsOneWidget);
    expect(find.byTooltip('Notifications'), findsOneWidget);
    expect(tester.getRect(messages).right, lessThanOrEqualTo(_phone.width));
  });

  // Each tab's first read, held, answering nothing, or failing, and what the
  // tab must show for each. A failed read that drew the empty state would
  // tell the runner they have no clubs or no feed when the truth is that
  // nothing could be read (issue #1374 NS-4).
  final screens = <String, Type>{
    'Feed': FeedScreen,
    'Clubs': ClubsScreen,
    'Events': DiscoverScreen,
    'Challenges': ChallengesScreen,
    'People': PeopleScreen,
  };

  for (final read in _Read.values) {
    for (final MapEntry(key: label, value: screen) in screens.entries) {
      testWidgets('$label shows its ${read.name} state for ${read.cause}',
          (tester) async {
        final reads = _Reads(read);
        await pumpHub(
          tester,
          api: _StateApi(reads),
          social: _StateService(reads),
          textScale: 1.0,
        );
        await openTab(tester, label);
        Finder inTab(Type t) =>
            find.descendant(of: find.byType(screen), matching: find.byType(t));

        switch (read) {
          case _Read.loading:
            expect(inTab(LoadingState), findsWidgets,
                reason: '$label shows no loading state while its read runs');
            expect(inTab(EmptyState), findsNothing,
                reason: '$label called an unfinished read empty');
            expect(inTab(AppErrorState), findsNothing);
          case _Read.empty:
            expect(inTab(EmptyState), findsOneWidget,
                reason: '$label shows no empty state for an empty answer');
            expect(inTab(AppErrorState), findsNothing);
            expect(inTab(LoadingState), findsNothing);
          case _Read.error:
            expect(inTab(AppErrorState), findsOneWidget,
                reason: '$label hides a failed read');
            expect(inTab(EmptyState), findsNothing,
                reason: '$label showed a failed read as empty');
            expect(inTab(LoadingState), findsNothing);
        }

        reads.release();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      });
    }
  }
}

enum _Read {
  loading('a read in flight'),
  empty('an empty answer'),
  error('a failed read');

  const _Read(this.cause);

  final String cause;
}

/// Answers every tab's first read the one way [mode] names. A held read is
/// released with an empty answer at the end of the case, so no timer is left
/// pending.
class _Reads {
  _Reads(this.mode);

  final _Read mode;
  final _held = <void Function()>[];

  Future<T> answer<T>(T empty) {
    switch (mode) {
      case _Read.loading:
        final c = Completer<T>();
        _held.add(() {
          if (!c.isCompleted) c.complete(empty);
        });
        return c.future;
      case _Read.empty:
        return Future.value(empty);
      case _Read.error:
        return Future.error(Exception('read failed'));
    }
  }

  void release() {
    for (final r in _held) {
      r();
    }
  }
}

class _StateApi extends SocialHubFakeApi {
  _StateApi(this.reads);

  final _Reads reads;

  @override
  Future<List<ActivityFeedEntry>> fetchFollowingActivityFeed({
    int limit = 20,
    ({DateTime startedAt, String id})? cursor,
    String? authorId,
    String? activityType,
    int feedWindowDays = 14,
  }) =>
      reads.answer(const <ActivityFeedEntry>[]);

  @override
  Future<List<PublicEventResult>> searchPublicEvents({
    String? query,
    String? category,
    String? cadence,
    String? byday,
    String? paid,
    String? time,
    int limit = 60,
  }) =>
      reads.answer(const <PublicEventResult>[]);

  @override
  Future<List<PeopleSuggestion>> fetchSuggestedPeople({int limit = 12}) =>
      reads.answer(const <PeopleSuggestion>[]);
}

class _StateService extends SocialHubFakeService {
  _StateService(this.reads);

  final _Reads reads;

  @override
  Future<List<ClubView>> browseClubs({String? query}) =>
      reads.answer(const <ClubView>[]);

  @override
  Future<List<ClubView>> fetchMyClubs() => reads.answer(const <ClubView>[]);

  @override
  Future<List<ChallengeView>> fetchChallenges() =>
      reads.answer(const <ChallengeView>[]);
}

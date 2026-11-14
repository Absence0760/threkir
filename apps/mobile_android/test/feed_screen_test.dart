import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show AppInsets, ListSkeleton, PageHeading;
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/adaptive_width.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/engagement_cache.dart';
import '../lib/screens/feed_screen.dart';
import '../lib/screens/profile_screen.dart' show ProfileScreen, ProfileTab;
import '../lib/widgets/error_state.dart';
import 'supabase_test_init.dart';
import 'worst_case_layout.dart';

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await initializeTestSupabase();
  _supabaseReady = true;
}

PublicProfile _author({String id = 'u-1', String? name = 'Alex Runner'}) =>
    PublicProfile(id: id, displayName: name);

RunFeedEntry _runEntry({
  String id = 'run-1',
  double distanceM = 5000,
  int durationS = 1500,
  String authorId = 'u-1',
  String? authorName = 'Alex Runner',
  String? trackUrl,
}) =>
    RunFeedEntry(
      run: RunRow(safetyAudience: false, 
        id: id,
        userId: authorId,
        startedAt: DateTime.utc(2026, 6, 10, 7),
        durationS: durationS,
        distanceM: distanceM,
        source: 'manual',
        activityType: 'run',
        isDnf: false,
        followersOnly: false,
        isPublic: true,
        trackUrl: trackUrl,
      ),
      author: _author(id: authorId, name: authorName),
    );

UserProfileRow _profileRow(String id, String name) => UserProfileRow(profilePrivate: false, shadowHidden: false, 
      id: id,
      displayName: name,
    );

// Awards default to midday UTC so a run of them on one day stays on one
// local day in every time zone the suite might run in.
BadgeAwardEntry _badgeAward({
  String authorId = 'u-1',
  String? authorName = 'Alex Runner',
  String badgeKey = 'streak',
  String tier = 'gold',
  DateTime? earnedAt,
}) =>
    BadgeAwardEntry(
      badge: AchievementRow(
        id: '$badgeKey-$tier-$authorId',
        userId: authorId,
        badgeKey: badgeKey,
        tier: tier,
        sourceKind: 'streak',
        earnedAt: earnedAt ?? DateTime.utc(2026, 6, 9, 12),
        isPublic: true,
      ),
      authorId: authorId,
      authorName: authorName,
    );

/// Fake feed-backing ApiClient. Reports a signed-in user, returns canned
/// entries + followees + engagement, and records kudos give/rescind calls.
class _FakeApi extends ApiClient {
  _FakeApi({
    this.entries = const [],
    this.followees = const [],
    this.engagement = const {},
    this.badgeAwards = const [],
    this.signedIn = true,
  });
  List<ActivityFeedEntry> entries;
  List<UserProfileRow> followees;
  Map<String, ({int kudosCount, bool viewerHasKudos, int commentCount})>
      engagement;
  List<BadgeAwardEntry> badgeAwards;
  bool signedIn;
  int giveCalls = 0;
  int rescindCalls = 0;
  String? lastActivityType;
  String? lastAuthorId;

  @override
  String? get userId => signedIn ? 'me' : null;

  @override
  Future<List<ActivityFeedEntry>> fetchFollowingActivityFeed({
    int limit = 20,
    ({DateTime startedAt, String id})? cursor,
    String? authorId,
    String? activityType,
    int feedWindowDays = 14,
  }) async {
    lastActivityType = activityType;
    lastAuthorId = authorId;
    // Filtering happens server-side; the fake honours the author filter so
    // the "no matches" empty state can be exercised.
    if (cursor != null) return const [];
    return entries;
  }

  int followingCalls = 0;
  @override
  Future<List<UserProfileRow>> fetchAllFollowing(String userId) async {
    followingCalls++;
    return followees;
  }

  @override
  Future<Map<String, ({int kudosCount, bool viewerHasKudos, int commentCount})>>
      fetchEngagementSummaries(List<String> runIds) async => engagement;

  @override
  Future<bool> giveKudos(String runId) async {
    giveCalls++;
    return true;
  }

  @override
  Future<bool> rescindKudos(String runId) async {
    rescindCalls++;
    return true;
  }

  int badgeReads = 0;
  DateTime? lastBadgeSince;
  String? lastBadgeAuthorId;

  // One page: every award on the first read, nothing past a cursor.
  @override
  Future<List<BadgeAwardEntry>> fetchFollowingBadgeAwards({
    int limit = 20,
    ({DateTime earnedAt, String id})? cursor,
    DateTime? since,
    String? authorId,
  }) async {
    badgeReads++;
    lastBadgeSince = since;
    lastBadgeAuthorId = authorId;
    if (cursor != null) return const [];
    return [
      for (final a in badgeAwards)
        if (authorId == null || a.authorId == authorId) a,
    ];
  }
}

/// Fake whose initial feed load throws, to drive the error state.
class _ThrowingApi extends _FakeApi {
  @override
  Future<List<ActivityFeedEntry>> fetchFollowingActivityFeed({
    int limit = 20,
    ({DateTime startedAt, String id})? cursor,
    String? authorId,
    String? activityType,
    int feedWindowDays = 14,
  }) async =>
      throw Exception('feed down');
}

/// Fake whose badge-awards read fails on the first call and succeeds after,
/// so the strip's error and its retry are both reachable.
class _BadgeAwardsFailOnceApi extends _FakeApi {
  _BadgeAwardsFailOnceApi({super.entries, super.badgeAwards});
  int badgeCalls = 0;
  @override
  Future<List<BadgeAwardEntry>> fetchFollowingBadgeAwards({
    int limit = 20,
    ({DateTime earnedAt, String id})? cursor,
    DateTime? since,
    String? authorId,
  }) async {
    badgeCalls++;
    if (badgeCalls == 1) throw Exception('badges down');
    return cursor == null ? badgeAwards : const [];
  }
}

/// Fake whose author-dropdown fetch (fetchAllFollowing) throws — the feed
/// entries must still render (issue #506: a dropdown failure can't blank
/// the whole feed).
class _FollowingFailApi extends _FakeApi {
  _FollowingFailApi({super.entries, super.engagement});
  @override
  Future<List<UserProfileRow>> fetchAllFollowing(String userId) async =>
      throw Exception('followees down');
}

/// Fake whose engagement fetch throws — the feed entries must still
/// render, just without kudos/comment counts (issue #506).
class _EngagementFailApi extends _FakeApi {
  _EngagementFailApi({super.entries, super.followees});
  @override
  Future<Map<String, ({int kudosCount, bool viewerHasKudos, int commentCount})>>
      fetchEngagementSummaries(List<String> runIds) async =>
          throw Exception('engagement down');
}

/// Fake whose kudos write throws the ApiClient signed-out guard, to drive
/// the optimistic-rollback banner + the friendly-error classification.
class _KudosFailApi extends _FakeApi {
  _KudosFailApi({super.entries, super.engagement});
  @override
  Future<bool> giveKudos(String runId) async {
    giveCalls++;
    throw Exception('Not authenticated');
  }
}

Future<void> _pump(WidgetTester tester, ApiClient api,
    {double textScale = 1.0}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: FeedScreen(api: api),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(_ensureSupabase);
  // The cache is app-wide; each test starts from what its own feed loads.
  setUp(EngagementCache.instance.clear);

  group('FeedScreen — initial render', () {
    testWidgets('renders the Feed app-bar title', (tester) async {
      await _pump(tester, _FakeApi());
      await _settle(tester);
      expect(find.widgetWithText(PageHeading, 'Feed'), findsOneWidget);
    });

    testWidgets('first frame shows the list skeleton', (tester) async {
      await _pump(tester, _FakeApi());
      // Don't settle — assert the skeleton before the load resolves.
      expect(find.byType(ListSkeleton), findsOneWidget);
    });
  });

  group('FeedScreen — list rendering', () {
    testWidgets('a feed entry renders the author name + distance stat',
        (tester) async {
      await _pump(
        tester,
        _FakeApi(
          entries: [_runEntry(distanceM: 5000)],
          followees: [_profileRow('u-1', 'Alex Runner')],
          engagement: {
            'run-1': (kudosCount: 2, viewerHasKudos: false, commentCount: 1),
          },
        ),
      );
      await _settle(tester);
      expect(find.text('Alex Runner'), findsWidgets);
      // 5 km distance stat in the default (km) unit.
      expect(find.textContaining('5.00'), findsOneWidget);
    });

    // #1374 A11Y-12: the track thumbnail was a second, unnamed button that
    // opens the same run as the stats row under it.
    testWidgets('the track thumbnail is not a second unnamed button', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        _FakeApi(
          entries: [_runEntry(trackUrl: 'u-1/run-1.json.gz')],
          followees: [_profileRow('u-1', 'Alex Runner')],
        ),
      );
      await _settle(tester);
      final thumb = find.byKey(const Key('feedCardTrackThumb'));
      expect(thumb, findsOneWidget);
      expect(find.descendant(of: thumb, matching: find.byType(InkWell)), findsOneWidget,
          reason: 'the thumbnail still opens the run by touch');
      expect(tester.widget<ExcludeSemantics>(thumb).excluding, isTrue);
      tester.takeException();
      handle.dispose();
    });

    testWidgets('the kudos count from the engagement map renders',
        (tester) async {
      await _pump(
        tester,
        _FakeApi(
          entries: [_runEntry()],
          followees: [_profileRow('u-1', 'Alex Runner')],
          engagement: {
            'run-1': (kudosCount: 7, viewerHasKudos: true, commentCount: 3),
          },
        ),
      );
      await _settle(tester);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      // viewerHasKudos → filled heart.
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      // Icon-only kudos / comment buttons carry accessibility labels.
      expect(find.bySemanticsLabel('Remove kudos'), findsOneWidget);
      expect(find.bySemanticsLabel('View comments'), findsOneWidget);
    });

    testWidgets('a not-yet-kudoed card exposes the give-kudos label',
        (tester) async {
      await _pump(
        tester,
        _FakeApi(
          entries: [_runEntry()],
          followees: [_profileRow('u-1', 'Alex Runner')],
          engagement: {
            'run-1': (kudosCount: 0, viewerHasKudos: false, commentCount: 0),
          },
        ),
      );
      await _settle(tester);
      expect(find.bySemanticsLabel('Give kudos'), findsOneWidget);
      expect(find.bySemanticsLabel('Remove kudos'), findsNothing);
    });

    testWidgets('signed-out viewer still loads the feed but skips fetchAllFollowing',
        (tester) async {
      final api = _FakeApi(
        entries: [_runEntry(distanceM: 5000)],
        followees: [_profileRow('u-1', 'Alex Runner')],
        signedIn: false,
      );
      await _pump(tester, api);
      await _settle(tester);
      // The entry still renders (the null-userId load path works)...
      expect(find.textContaining('5.00'), findsOneWidget);
      // ...but the author-dropdown follow query is skipped when signed out.
      expect(api.followingCalls, 0);
    });
  });

  group('FeedScreen — empty states', () {
    testWidgets('no follows shows the follow-people empty state',
        (tester) async {
      await _pump(tester, _FakeApi(entries: const [], followees: const []));
      await _settle(tester);
      // The empty state renders with Grisnir in place of the groups glyph
      // (show_mascot is on unless set false) and no toolbar.
      expect(find.byKey(const Key('empty-state-grisnir')), findsOneWidget);
      expect(find.byIcon(Icons.groups_outlined), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('follows but no activity shows the toolbar + empty body',
        (tester) async {
      await _pump(
        tester,
        _FakeApi(
          entries: const [],
          followees: [_profileRow('u-1', 'Alex Runner')],
        ),
      );
      await _settle(tester);
      // Toolbar shows because there ARE follows.
      expect(find.byType(ChoiceChip), findsWidgets);
      expect(find.byIcon(Icons.groups_outlined), findsOneWidget);
    });
  });

  group('FeedScreen — error state', () {
    testWidgets('a failed initial load shows ErrorState with Retry',
        (tester) async {
      await _pump(tester, _ThrowingApi());
      await _settle(tester);
      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('a failed author-dropdown fetch still renders the feed',
        (tester) async {
      await _pump(
        tester,
        _FollowingFailApi(
          entries: [_runEntry(distanceM: 5000)],
          engagement: {
            'run-1': (kudosCount: 2, viewerHasKudos: false, commentCount: 1),
          },
        ),
      );
      await _settle(tester);
      // No ErrorState — the feed entry renders despite the dropdown failure.
      expect(find.byType(ErrorState), findsNothing);
      expect(find.textContaining('5.00'), findsOneWidget);
      // Engagement still loaded, so the counts show.
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('a failed engagement fetch still renders the feed',
        (tester) async {
      await _pump(
        tester,
        _EngagementFailApi(
          entries: [_runEntry(distanceM: 5000)],
          followees: [_profileRow('u-1', 'Alex Runner')],
        ),
      );
      await _settle(tester);
      // No ErrorState — the entry renders; the footer just shows zero counts.
      expect(find.byType(ErrorState), findsNothing);
      expect(find.textContaining('5.00'), findsOneWidget);
      expect(find.bySemanticsLabel('Give kudos'), findsOneWidget);
    });
  });

  group('FeedScreen — kudos toggle', () {
    testWidgets('tapping the kudos button optimistically increments + calls give',
        (tester) async {
      final api = _FakeApi(
        entries: [_runEntry()],
        followees: [_profileRow('u-1', 'Alex Runner')],
        engagement: {
          'run-1': (kudosCount: 4, viewerHasKudos: false, commentCount: 0),
        },
      );
      await _pump(tester, api);
      await _settle(tester);
      expect(find.text('4'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pump();
      // Optimistic: count goes to 5 and the heart fills.
      expect(find.text('5'), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      await _settle(tester);
      expect(api.giveCalls, 1);
    });

    // Issue #1374 NS-9: kudos and a comment given on the run's own page did
    // not reach its feed card, and the card's kudos then re-gave one.
    testWidgets('a change made on the run\'s page shows on its card',
        (tester) async {
      final api = _FakeApi(
        entries: [_runEntry()],
        followees: [_profileRow('u-1', 'Alex Runner')],
        engagement: {
          'run-1': (kudosCount: 4, viewerHasKudos: false, commentCount: 0),
        },
      );
      await _pump(tester, api);
      await _settle(tester);
      expect(find.text('4'), findsOneWidget);

      // What RunSocialSection publishes after a kudos and a comment.
      EngagementCache.instance.put('me', 'run-1',
          const EngagementSummary(kudosCount: 5, viewerHasKudos: true, commentCount: 1));
      await tester.pump();
      expect(find.text('5'), findsOneWidget);
      expect(find.bySemanticsLabel('Remove kudos'), findsOneWidget);
    });

    testWidgets('a failed kudos write rolls back the count + surfaces a banner',
        (tester) async {
      final api = _KudosFailApi(
        entries: [_runEntry()],
        engagement: {
          'run-1': (kudosCount: 4, viewerHasKudos: false, commentCount: 0),
        },
      );
      await _pump(tester, api);
      await _settle(tester);

      await tester.tap(find.byIcon(Icons.favorite_border));
      await _settle(tester);

      // Rollback: after the failed write the count returns to 4 and the
      // heart un-fills (the transient optimistic 5 is asserted by the
      // success test; here only the rolled-back end state is stable).
      expect(find.text('4'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(api.giveCalls, 1);
      // The failure is surfaced, not swallowed — and classified: the
      // banner carries the friendly sign-in message, never the raw
      // "Exception: Not authenticated" (issue #240).
      expect(find.textContaining('Could not update kudos'), findsOneWidget);
      expect(find.textContaining('signed in'), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
      await tester.pump(const Duration(seconds: 4)); // drain banner timer
    });
  });

  group('FeedScreen — badge highlights', () {
    Finder highlightRows() => find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key as ValueKey<String>).value.startsWith('feed-highlight-'));

    testWidgets('a badge award is a row of the feed, placed by time',
        (tester) async {
      tester.view.physicalSize = const Size(411, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _FakeApi(
        entries: [_runEntry()], // 2026-06-10 07:00 UTC
        badgeAwards: [
          _badgeAward(
              authorId: 'u-2',
              authorName: 'Morgan Lee',
              earnedAt: DateTime.utc(2026, 6, 11, 12)),
          _badgeAward(authorName: 'Alex Runner'), // 2026-06-09 12:00 UTC
        ],
      );
      await _pump(tester, api);
      await _settle(tester);

      final newer = find.textContaining('Morgan Lee earned the');
      final run = find.textContaining('5.00');
      final older = find.textContaining('Alex Runner earned the');
      expect(newer, findsOneWidget);
      expect(older, findsOneWidget);
      expect(tester.getTopLeft(newer).dy,
          lessThan(tester.getTopLeft(run.first).dy));
      expect(tester.getTopLeft(older).dy,
          greaterThan(tester.getTopLeft(run.first).dy));
      // Nothing scrolls sideways: no strip, and every highlight sits in the
      // feed's own vertical list.
      expect(find.byKey(const ValueKey('feed-badge-strip')), findsNothing);
      expect(find.byType(ActionChip), findsNothing);
      for (final row in highlightRows().evaluate()) {
        final scrollable =
            Scrollable.of(row).axisDirection;
        expect(scrollable, AxisDirection.down);
      }
      // The read is bounded to the feed's window.
      expect(api.lastBadgeSince, isNotNull);
      expect(api.lastBadgeAuthorId, isNull);
    });

    testWidgets('one person, several badges in a day, is one row',
        (tester) async {
      final api = _FakeApi(
        entries: [_runEntry()],
        badgeAwards: [
          _badgeAward(badgeKey: 'streak', earnedAt: DateTime.utc(2026, 6, 9, 12)),
          _badgeAward(
              badgeKey: 'park_courses',
              tier: 'bronze',
              earnedAt: DateTime.utc(2026, 6, 9, 12, 10)),
          _badgeAward(
              badgeKey: 'streak',
              tier: 'silver',
              earnedAt: DateTime.utc(2026, 6, 9, 12, 20)),
        ],
      );
      await _pump(tester, api);
      await _settle(tester);
      expect(highlightRows(), findsOneWidget);
      expect(find.text('Alex Runner earned 3 badges'), findsOneWidget);
      expect(find.textContaining(' · '), findsOneWidget,
          reason: 'the badge names follow on one line under it');
    });

    testWidgets('a highlight is one 48 dp tap target that opens the badges',
        (tester) async {
      final observer = _PushObserver();
      final api = _FakeApi(
        entries: [_runEntry()],
        badgeAwards: [_badgeAward(authorId: 'u-7', authorName: 'Sam Park')],
      );
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorObservers: [observer],
        home: FeedScreen(api: api),
      ));
      await _settle(tester);
      final row = highlightRows();
      expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
      await tester.tap(row);
      final route = observer.pushed.last as MaterialPageRoute;
      final page =
          route.builder(tester.element(find.byType(FeedScreen))) as ProfileScreen;
      expect(page.userId, 'u-7');
      expect(page.initialTab, ProfileTab.badges);
    });

    testWidgets('an empty feed still shows the highlights, not the empty state',
        (tester) async {
      final api = _FakeApi(
        followees: [_profileRow('u-1', 'Alex Runner')],
        badgeAwards: [_badgeAward()],
      );
      await _pump(tester, api);
      await _settle(tester);
      expect(highlightRows(), findsOneWidget);
      expect(find.text('No recent activity'), findsNothing);
    });

    testWidgets('no highlights leaves the feed as it was', (tester) async {
      final api = _FakeApi(entries: [_runEntry()], badgeAwards: const []);
      await _pump(tester, api);
      await _settle(tester);
      expect(highlightRows(), findsNothing);
      expect(find.textContaining('5.00'), findsOneWidget);
    });

    testWidgets('an activity chip hides the highlights; All brings them back',
        (tester) async {
      final api = _FakeApi(
        entries: [_runEntry()],
        followees: [_profileRow('u-1', 'Alex Runner')],
        badgeAwards: [_badgeAward()],
      );
      await _pump(tester, api);
      await _settle(tester);
      expect(highlightRows(), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Run'));
      await _settle(tester);
      expect(highlightRows(), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await _settle(tester);
      expect(highlightRows(), findsOneWidget);
    });

    testWidgets('the author filter narrows the highlights to that person',
        (tester) async {
      final api = _FakeApi(
        entries: [_runEntry()],
        followees: [
          _profileRow('u-1', 'Alex Runner'),
          _profileRow('u-2', 'Morgan Lee'),
        ],
        badgeAwards: [
          _badgeAward(),
          _badgeAward(authorId: 'u-2', authorName: 'Morgan Lee'),
        ],
      );
      await _pump(tester, api);
      await _settle(tester);
      expect(highlightRows(), findsNWidgets(2));

      await tester.tap(find.byKey(const Key('filter-bar-filters')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Morgan Lee'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(api.lastBadgeAuthorId, 'u-2');
      expect(highlightRows(), findsOneWidget);
      expect(find.textContaining('Morgan Lee earned the'), findsOneWidget);
    });

    testWidgets(
        'a failed read says so with a retry, never "no badges" (§ 2501)',
        (tester) async {
      final api = _BadgeAwardsFailOnceApi(
        entries: [_runEntry()],
        badgeAwards: [_badgeAward(authorName: 'Alex Runner')],
      );
      await _pump(tester, api);
      await _settle(tester);
      expect(
        find.text("Couldn't load the latest badges from people you follow."),
        findsOneWidget,
      );
      expect(highlightRows(), findsNothing);
      // The core feed is untouched by the adornment's failure.
      expect(find.byType(Card), findsWidgets);

      await tester.tap(find.text('Retry'));
      await _settle(tester);
      expect(api.badgeCalls, 2);
      expect(
        find.text("Couldn't load the latest badges from people you follow."),
        findsNothing,
      );
      expect(
        find.textContaining('Alex Runner earned the Century streak badge'),
        findsOneWidget,
      );
    });
  });

  // Issue #1374 owner finding 6: the feed's cards looked to run past the
  // right edge in a device screenshot. Every card, highlight rows included,
  // sits inside the 16 dp gutter on both sides.
  final feedWithBadges = _FakeApi(
    entries: [
      _runEntry(),
      _runEntry(id: 'run-2', authorId: 'u-2', authorName: 'Morgan Lee'),
      _runEntry(id: 'run-3', distanceM: 386243, durationS: 376331),
    ],
    followees: [_profileRow('u-1', 'Alex Runner')],
    badgeAwards: [
      _badgeAward(badgeKey: 'park_courses', tier: 'bronze'),
      _badgeAward(authorId: 'u-2', authorName: 'Morgan Lee'),
      _badgeAward(authorId: 'u-3', authorName: 'Alexandra Longname-Runner'),
      _badgeAward(
          authorId: 'u-3',
          authorName: 'Alexandra Longname-Runner',
          badgeKey: 'distance_lifetime',
          earnedAt: DateTime.utc(2026, 6, 9, 12, 30)),
    ],
  );

  void expectInsideGutter(WidgetTester tester, double width, String where) {
    final cards = find.byType(Card);
    expect(cards, findsWidgets);
    for (final card in cards.evaluate()) {
      final rect = tester.getRect(find.byWidget(card.widget));
      expect(rect.left, greaterThanOrEqualTo(AppInsets.gutter - 0.01),
          reason: '$where: a card starts at ${rect.left}');
      expect(rect.right, lessThanOrEqualTo(width - AppInsets.gutter + 0.01),
          reason: '$where: a card ends at ${rect.right} of $width');
    }
  }

  testWidgets('at 411 dp every card and highlight keeps the gutter',
      (tester) async {
    tester.view.physicalSize = const Size(411, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, feedWithBadges);
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expectInsideGutter(tester, 411, '411 dp');
  });

  worstCaseTestWidgets('the feed with cards and highlights',
      (tester, locale) async {
    await tester.pumpWidget(worstCaseApp(
      locale: locale,
      home: FeedScreen(api: feedWithBadges),
    ));
    await _settle(tester);
    expectNoOverflow(tester, 'feed');
    expectInsideGutter(tester, kWorstCasePhone.width, 'feed [$locale]');
  });

  worstCaseTestWidgets('the feed badge failure line', (tester, locale) async {
    await tester.pumpWidget(worstCaseApp(
      locale: locale,
      home: FeedScreen(
        api: _BadgeAwardsFailOnceApi(entries: [_runEntry()]),
      ),
    ));
    await _settle(tester);
    expect(find.byType(ErrorState), findsOneWidget);
  });

  group('FeedScreen — stat row at a narrow width', () {
    testWidgets('an ultra-length distance/time/pace does not overflow the card',
        (tester) async {
      final view = tester.view;
      view.physicalSize = const Size(720, 1280);
      view.devicePixelRatio = 2.0;
      addTearDown(view.reset);

      // A 100-hour, 240-mile ultra: the widest the stat cells ever get.
      final api = _FakeApi(
        entries: [_runEntry(distanceM: 386243, durationS: 376331)],
      );
      await _pump(tester, api);
      await _settle(tester);

      expect(tester.takeException(), isNull);
    });
  });

  group('FeedScreen — adaptive width', () {
    testWidgets('expanded surface caps the feed column at kContentMaxWidth',
        (tester) async {
      tester.view.physicalSize = const Size(2560, 1440);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        _FakeApi(
          entries: [_runEntry()],
          followees: [_profileRow('u-1', 'Alex Runner')],
        ),
      );
      await _settle(tester);
      // 1280dp surface, 720dp column, minus the list's 16dp page gutter.
      expect(tester.getSize(find.byType(Card).first).width,
          kContentMaxWidth - 2 * AppInsets.gutter);
    });

    testWidgets('compact surface keeps the feed card full width',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        _FakeApi(
          entries: [_runEntry()],
          followees: [_profileRow('u-1', 'Alex Runner')],
        ),
      );
      await _settle(tester);
      // 400dp surface minus the list's 16dp page gutter.
      expect(tester.getSize(find.byType(Card).first).width,
          400 - 2 * AppInsets.gutter);
    });
  });
}

class _PushObserver extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.add(route);
}

// ignore_for_file: avoid_relative_lib_imports
// Signed-in fakes with one row on every Social tab, for the tests that mount
// the whole hub: each tab then shows its rows rather than an error, and a
// layout fault in a row shows up.
import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/social_service.dart';
import '../lib/unread_messages.dart';
import 'supabase_test_init.dart';

bool _supabaseReady = false;

/// The tab bodies reach `Supabase.instance` in places a fake does not cover
/// (the strava clubs gate, the challenge form); a local fake keeps those from
/// throwing on a missing instance.
Future<void> ensureSocialTestSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await initializeTestSupabase();
  _supabaseReady = true;
}

class SocialHubFakeApi extends ApiClient {
  SocialHubFakeApi({this.unreadDms = 0});

  int unreadDms;
  final _auth = StreamController<String?>.broadcast();

  @override
  String? get userId => 'me';

  @override
  Stream<String?> get authUserChanges => _auth.stream;

  @override
  Future<int> fetchUnreadNotificationCount() async => 0;

  @override
  Future<List<DmBadgeState>> fetchDmBadgeStates() async => [
        (
          conversationId: 'c-1',
          unread: unreadDms,
          muted: false,
          archived: false,
          request: false,
        ),
      ];

  @override
  Future<List<ActivityFeedEntry>> fetchFollowingActivityFeed({
    int limit = 20,
    ({DateTime startedAt, String id})? cursor,
    String? authorId,
    String? activityType,
    int feedWindowDays = 14,
  }) async {
    if (cursor != null) return const [];
    return [
      RunFeedEntry(
        run: RunRow(
          safetyAudience: false,
          id: 'run-1',
          userId: 'u-1',
          startedAt: DateTime.utc(2026, 6, 10, 7),
          durationS: 1500,
          distanceM: 5000,
          source: 'manual',
          activityType: 'run',
          isDnf: false,
          followersOnly: false,
          isPublic: true,
        ),
        author: const PublicProfile(id: 'u-1', displayName: 'Alexandra Longname-Runner'),
      ),
    ];
  }

  @override
  Future<List<UserProfileRow>> fetchAllFollowing(String userId) async => [
        UserProfileRow(
          profilePrivate: false,
          shadowHidden: false,
          id: 'u-1',
          displayName: 'Alexandra Longname-Runner',
        ),
      ];

  @override
  Future<Map<String, ({int kudosCount, bool viewerHasKudos, int commentCount})>>
      fetchEngagementSummaries(List<String> runIds) async => const {};

  @override
  Future<List<BadgeAwardEntry>> fetchFollowingBadgeAwards({
    int limit = 20,
    ({DateTime earnedAt, String id})? cursor,
  }) async =>
      const [];

  @override
  Future<List<PublicEventResult>> searchPublicEvents({
    String? query,
    String? category,
    String? cadence,
    String? byday,
    String? paid,
    String? time,
    int limit = 60,
  }) async =>
      [
        PublicEventResult(
          id: 'ev1',
          clubId: 'club1',
          clubName: 'Norfolk Botanical Runners',
          clubSlug: 'norfolk-botanical-runners',
          title: 'Sunday Long Run',
          category: 'class',
          discipline: 'Reformer Pilates for marathoners',
          startsAt: DateTime.utc(2026, 6, 15, 22),
          timezone: 'America/New_York',
          durationMin: 50,
          recurrenceFreq: 'weekly',
          recurrenceByday: const ['MO', 'WE'],
          capacity: 6,
          priceCents: 1800,
          currency: 'usd',
        ),
      ];

  @override
  Future<List<PeopleSuggestion>> fetchSuggestedPeople({int limit = 12}) async =>
      const [
        PeopleSuggestion(
          id: 'p-1',
          displayName: 'Casey Marathon-Everyday',
          publicRunsCount: 120,
          sharedClubs: 3,
          viewerFollows: false,
          handle: 'casey',
        ),
      ];
}

class SocialHubFakeService extends SocialService {
  @override
  Future<List<ClubView>> browseClubs({String? query}) async => const [];

  @override
  Future<List<ClubView>> fetchMyClubs() async => [
        ClubView(
          row: ClubRow(
            shadowHidden: false,
            id: 'club-1',
            ownerId: 'owner',
            name: 'Richmond Road Runners and Friends',
            slug: 'rrr',
            isPublic: false,
            isVerified: true,
            locationLabel: 'Richmond, Virginia',
            joinPolicy: 'open',
            memberCount: 1200,
            requiresActivityWaiver: false,
          ),
          memberCount: 1200,
          viewerRole: 'admin',
          viewerStatus: 'active',
          joinPolicy: 'open',
        ),
      ];

  @override
  Future<List<ChallengeView>> fetchChallenges() async {
    final now = DateTime.now();
    return [
      ChallengeView(
        id: 'ch-1',
        creatorId: 'creator',
        clubId: null,
        title: 'June hundred kilometre challenge',
        description: null,
        metric: 'distance',
        scope: 'individual',
        goalValue: 100000,
        activityType: null,
        startsAt: now.subtract(const Duration(days: 1)),
        endsAt: now.add(const Duration(days: 30)),
        isPublic: true,
        joined: true,
        myValue: 25000,
        myRank: 3,
        participantCount: 40,
        completedAt: null,
      ),
    ];
  }
}

/// An unread source that never reads, holding [count].
class FixedUnreadMessages extends UnreadMessages {
  FixedUnreadMessages(this.count) : super(listenToLifecycle: false);

  final int count;

  @override
  int get value => count;

  @override
  void bind(ApiClient? api) {}

  @override
  Future<void> refresh() async {}
}

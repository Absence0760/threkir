// Reactions, comment likes and @mention links on the mobile run social
// section (decisions § 1971). Mirrors the web RunSocial behaviour pinned in
// tests-e2e/social/reactions-likes-mentions.spec.ts.

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/run_social_section.dart';

class _Api extends ApiClient {
  _Api({this.ownerComment = false, this.addReturnsNoOp = false});

  final bool ownerComment;
  final bool addReturnsNoOp;
  final List<String> added = [];
  final List<String> removed = [];
  final List<String> liked = [];
  final List<String> searched = [];

  @override
  String? get userId => 'viewer-1';

  @override
  Future<Map<String, ({int kudosCount, bool viewerHasKudos, int commentCount})>>
  fetchEngagementSummaries(List<String> runIds) async => {};

  @override
  Future<ProfileSummary?> fetchProfileSummary(String userId) async => null;

  @override
  Future<List<RunCommentWithAuthor>> fetchRunCommentsWithAuthors(
    String runId, {
    int limit = 200,
  }) async => [
    RunCommentWithAuthor(
      comment: RunCommentRow(
        id: 'c1',
        runId: runId,
        authorId: ownerComment ? 'viewer-1' : 'owner-1',
        body: 'see you there @carol_x',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
      author: const PublicProfile(id: 'owner-1', displayName: 'Owner'),
    ),
  ];

  @override
  Future<List<Map<String, dynamic>>> fetchRunReactionSummary(String runId) async => [
    {'reaction': 'fire', 'reaction_count': 2, 'viewer_reacted': false},
  ];

  @override
  Future<bool> addRunReaction(String runId, String reaction) async {
    added.add(reaction);
    return !addReturnsNoOp;
  }

  @override
  Future<bool> removeRunReaction(String runId, String reaction) async {
    removed.add(reaction);
    return true;
  }

  @override
  Future<Map<String, ({int count, bool viewerLiked})>> fetchRunCommentLikeSummary(
    String runId,
  ) async => {'c1': (count: 3, viewerLiked: false)};

  @override
  Future<bool> likeRunComment(String commentId) async {
    liked.add(commentId);
    return true;
  }

  @override
  Future<Map<String, String>> resolveMentionHandles(List<String> handles) async =>
      {for (final h in handles) if (h == 'carol_x') h: 'carol-id'};

  @override
  Future<List<PeopleSuggestion>> searchPeople(String query, {int limit = 20}) async {
    searched.add(query);
    return const [
      PeopleSuggestion(
        id: 'dana-id',
        displayName: 'Dana',
        publicRunsCount: 1,
        sharedClubs: 0,
        viewerFollows: false,
        handle: 'dana_runs',
      ),
      PeopleSuggestion(
        id: 'nohandle',
        displayName: 'No Handle',
        publicRunsCount: 1,
        sharedClubs: 0,
        viewerFollows: false,
      ),
    ];
  }
}

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(url: 'http://127.0.0.1:24321', anonKey: 'eyJ.local.test');
  _supabaseReady = true;
}

Future<void> _pump(WidgetTester tester, ApiClient api, {String owner = 'owner-1'}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ListView(
          children: [RunSocialSection(api: api, runId: 'r1', runOwnerId: owner)],
        ),
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

void main() {
  setUpAll(_ensureSupabase);

  testWidgets('renders one chip per reaction key with the server count', (tester) async {
    await _pump(tester, _Api());
    for (final key in ['fire', 'strong', 'trophy', 'thumbs_up', 'wave']) {
      expect(find.byKey(ValueKey('reaction-$key')), findsOneWidget);
    }
    expect(
      find.descendant(of: find.byKey(const ValueKey('reaction-fire')), matching: find.text('2')),
      findsOneWidget,
    );
  });

  testWidgets('tapping a chip adds the reaction and bumps the count', (tester) async {
    final api = _Api();
    await _pump(tester, api);
    await tester.tap(find.byKey(const ValueKey('reaction-fire')));
    await tester.pump();
    await tester.pump();
    expect(api.added, ['fire']);
    expect(
      find.descendant(of: find.byKey(const ValueKey('reaction-fire')), matching: find.text('3')),
      findsOneWidget,
    );
  });

  testWidgets('a given reaction says so by weight, not by a primary count', (tester) async {
    await _pump(tester, _Api());
    Text count() => tester.widget<Text>(
          find.descendant(of: find.byKey(const ValueKey('reaction-fire')), matching: find.byType(Text)),
        );
    final before = count();
    expect(before.style?.fontWeight, isNot(FontWeight.w700));

    await tester.tap(find.byKey(const ValueKey('reaction-fire')));
    await tester.pump();
    await tester.pump();

    final after = count();
    final scheme = Theme.of(tester.element(find.byKey(const ValueKey('reaction-fire')))).colorScheme;
    expect(after.data, '3');
    expect(after.style?.fontWeight, FontWeight.w700,
        reason: 'the tint under the chip is too faint to be the cue');
    expect(after.style?.color, scheme.onSurfaceVariant,
        reason: 'primary type on the given fill reads under AA in light');
  });

  testWidgets('a no-op add flips the chip without moving the count', (tester) async {
    final api = _Api(addReturnsNoOp: true);
    await _pump(tester, api);
    await tester.tap(find.byKey(const ValueKey('reaction-fire')));
    await tester.pump();
    await tester.pump();
    expect(
      find.descendant(of: find.byKey(const ValueKey('reaction-fire')), matching: find.text('2')),
      findsOneWidget,
    );
  });

  testWidgets('the run owner cannot react to their own run', (tester) async {
    final api = _Api();
    await _pump(tester, api, owner: 'viewer-1');
    await tester.tap(find.byKey(const ValueKey('reaction-fire')), warnIfMissed: false);
    await tester.pump();
    expect(api.added, isEmpty);
  });

  testWidgets('liking a comment calls the API and bumps its count', (tester) async {
    final api = _Api();
    await _pump(tester, api);
    final like = find.byKey(const ValueKey('comment-like-c1'));
    expect(find.descendant(of: like, matching: find.text('3')), findsOneWidget);
    await tester.tap(like);
    await tester.pump();
    await tester.pump();
    expect(api.liked, ['c1']);
    expect(find.descendant(of: like, matching: find.text('4')), findsOneWidget);
  });

  testWidgets('your own comment cannot be liked', (tester) async {
    final api = _Api(ownerComment: true);
    await _pump(tester, api);
    await tester.tap(find.byKey(const ValueKey('comment-like-c1')), warnIfMissed: false);
    await tester.pump();
    expect(api.liked, isEmpty);
  });

  testWidgets('a mention of a real runner renders as a link', (tester) async {
    await _pump(tester, _Api());
    expect(find.byKey(const ValueKey('mention-carol_x')), findsOneWidget);
  });

  testWidgets('typing @ offers handled people only and a pick inserts the handle', (
    tester,
  ) async {
    final api = _Api();
    await _pump(tester, api);
    final field = find.byType(TextField).last;
    await tester.enterText(field, 'run with @da');
    await tester.pump();
    await tester.pump();
    expect(api.searched, ['@da']);
    expect(find.byKey(const ValueKey('mention-pick-dana_runs')), findsOneWidget);
    expect(find.text('No Handle'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('mention-pick-dana_runs')));
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, 'run with @dana_runs ');
    expect(find.byKey(const ValueKey('mention-pick-dana_runs')), findsNothing);
  });
}

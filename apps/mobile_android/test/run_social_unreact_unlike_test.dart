// Taking a reaction or a comment like back on the mobile run social section
// (decisions § 1971), the half run_social_reactions_test.dart does not drive:
// the viewer already reacted and already liked, and a second tap removes it.

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/run_social_section.dart';

class _Api extends ApiClient {
  final List<String> added = [];
  final List<String> removed = [];
  final List<String> liked = [];
  final List<String> unliked = [];

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
        authorId: 'owner-1',
        body: 'thanks for the pacing',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
      author: const PublicProfile(id: 'owner-1', displayName: 'Owner'),
    ),
  ];

  @override
  Future<List<Map<String, dynamic>>> fetchRunReactionSummary(String runId) async => [
    {'reaction': 'fire', 'reaction_count': 2, 'viewer_reacted': true},
    {'reaction': 'wave', 'reaction_count': 1, 'viewer_reacted': true},
  ];

  @override
  Future<bool> addRunReaction(String runId, String reaction) async {
    added.add(reaction);
    return true;
  }

  @override
  Future<bool> removeRunReaction(String runId, String reaction) async {
    removed.add(reaction);
    return true;
  }

  @override
  Future<Map<String, ({int count, bool viewerLiked})>> fetchRunCommentLikeSummary(
    String runId,
  ) async => {'c1': (count: 1, viewerLiked: true)};

  @override
  Future<bool> likeRunComment(String commentId) async {
    liked.add(commentId);
    return true;
  }

  @override
  Future<bool> unlikeRunComment(String commentId) async {
    unliked.add(commentId);
    return true;
  }

  @override
  Future<Map<String, String>> resolveMentionHandles(List<String> handles) async => const {};
}

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(url: 'http://127.0.0.1:24321', anonKey: 'eyJ.local.test');
  _supabaseReady = true;
}

Future<void> _pump(WidgetTester tester, ApiClient api) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ListView(
          children: [RunSocialSection(api: api, runId: 'r1', runOwnerId: 'owner-1')],
        ),
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

Finder _inChip(String key, String text) =>
    find.descendant(of: find.byKey(ValueKey('reaction-$key')), matching: find.text(text));

void main() {
  setUpAll(_ensureSupabase);

  testWidgets('tapping a reaction the viewer left removes it and drops the count', (
    tester,
  ) async {
    final api = _Api();
    await _pump(tester, api);
    expect(_inChip('fire', '2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('reaction-fire')));
    await tester.pump();
    await tester.pump();

    expect(api.removed, ['fire']);
    expect(api.added, isEmpty);
    expect(_inChip('fire', '1'), findsOneWidget);
    expect(_inChip('fire', '2'), findsNothing);
  });

  testWidgets('removing the last reaction on a key hides its count', (tester) async {
    final api = _Api();
    await _pump(tester, api);
    expect(_inChip('wave', '1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('reaction-wave')));
    await tester.pump();
    await tester.pump();

    expect(api.removed, ['wave']);
    expect(_inChip('wave', '1'), findsNothing);
    expect(_inChip('wave', '0'), findsNothing);
  });

  testWidgets('reacting again after removing adds the reaction back', (tester) async {
    final api = _Api();
    await _pump(tester, api);

    await tester.tap(find.byKey(const ValueKey('reaction-fire')));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('reaction-fire')));
    await tester.pump();
    await tester.pump();

    expect(api.removed, ['fire']);
    expect(api.added, ['fire']);
    expect(_inChip('fire', '2'), findsOneWidget);
  });

  testWidgets('tapping a comment the viewer liked unlikes it and clears the count', (
    tester,
  ) async {
    final api = _Api();
    await _pump(tester, api);
    final like = find.byKey(const ValueKey('comment-like-c1'));
    expect(find.descendant(of: like, matching: find.text('1')), findsOneWidget);
    expect(find.descendant(of: like, matching: find.byIcon(Icons.favorite)), findsOneWidget);

    await tester.tap(like);
    await tester.pump();
    await tester.pump();

    expect(api.unliked, ['c1']);
    expect(api.liked, isEmpty);
    expect(find.descendant(of: like, matching: find.text('1')), findsNothing);
    expect(find.descendant(of: like, matching: find.byIcon(Icons.favorite_border)), findsOneWidget);
  });
}

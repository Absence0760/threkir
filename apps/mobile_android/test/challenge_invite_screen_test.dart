// Widget tests for ChallengeInviteScreen, the mobile twin of the web
// /challenges/join/[token] page (decisions § 2261): the challenge the link
// names, one tap to join, a dead link said plainly, a private creator shown
// by the anonymous label (the preview withholds their id with their name), and
// a failed read offering a retry.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/challenge_invite_screen.dart';
import '../lib/social_service.dart';

ChallengeInvitePreview _preview({
  String? creatorId = 'abcd1234-0000-4000-8000-000000000009',
  String? creatorName = 'Cass',
  bool joined = false,
}) =>
    ChallengeInvitePreview(
      id: '5f1c7e2a-0000-4000-8000-000000000001',
      title: 'Run 50 km with me',
      description: 'Every km counts.',
      metric: 'activity_count',
      scope: 'individual',
      goalValue: 20,
      startsAt: DateTime.now().subtract(const Duration(days: 1)),
      endsAt: DateTime.now().add(const Duration(days: 20)),
      isPublic: false,
      participantCount: 12,
      creatorId: creatorId,
      creatorName: creatorName,
      joined: joined,
    );

class _FakeSocial extends SocialService {
  _FakeSocial({this.preview, this.throwOnPreview = false, this.joinResult});

  ChallengeInvitePreview? preview;
  bool throwOnPreview;
  String? joinResult;
  final List<String> joined = [];
  final Completer<void> joinGate = Completer<void>()..complete();

  @override
  String? get currentUserId => 'me';

  @override
  Future<ChallengeInvitePreview?> previewChallengeInvite(String token) async {
    if (throwOnPreview) throw Exception('offline');
    return preview;
  }

  @override
  Future<String?> joinChallengeByToken(String token) async {
    joined.add(token);
    await joinGate.future;
    return joinResult;
  }

  @override
  Future<ChallengeView?> fetchChallengeById(String id) =>
      Completer<ChallengeView?>().future;
}

Future<void> _pump(WidgetTester tester, _FakeSocial social) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: ChallengeInviteScreen(social: social, token: 'tok-abc12345'),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('shows the challenge the link names and who sent it', (tester) async {
    await _pump(tester, _FakeSocial(preview: _preview()));
    expect(find.text('Run 50 km with me'), findsOneWidget);
    expect(find.text('Invited by Cass'), findsOneWidget);
    expect(find.text('12 runners in'), findsOneWidget);
    expect(find.text('Every km counts.'), findsOneWidget);
    expect(find.byKey(const ValueKey('challenge-invite-join')), findsOneWidget);
  });

  testWidgets('a private creator is shown by the anonymous label, never a blank', (tester) async {
    await _pump(tester,
        _FakeSocial(preview: _preview(creatorId: null, creatorName: null)));
    expect(find.text('Invited by Runner'), findsOneWidget);
  });

  testWidgets('one tap joins with the link token and opens the challenge', (tester) async {
    final social = _FakeSocial(
        preview: _preview(), joinResult: '5f1c7e2a-0000-4000-8000-000000000001');
    await _pump(tester, social);
    await tester.tap(find.byKey(const ValueKey('challenge-invite-join')));
    await tester.pump();
    await tester.pump();
    expect(social.joined, ['tok-abc12345']);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ChallengeInviteScreen), findsNothing);
  });

  testWidgets('a token that names nothing says the link does not work', (tester) async {
    await _pump(tester, _FakeSocial(preview: null));
    expect(find.text("This invite link doesn't work"), findsOneWidget);
    expect(find.byKey(const ValueKey('challenge-invite-join')), findsNothing);
  });

  testWidgets('a join that finds the link rotated falls to the dead-link state', (tester) async {
    final social = _FakeSocial(preview: _preview(), joinResult: null);
    await _pump(tester, social);
    await tester.tap(find.byKey(const ValueKey('challenge-invite-join')));
    await tester.pump();
    await tester.pump();
    expect(find.text("This invite link doesn't work"), findsOneWidget);
  });

  testWidgets('already in: offers the challenge, not a second join', (tester) async {
    await _pump(tester, _FakeSocial(preview: _preview(joined: true)));
    expect(find.text("You're already in this challenge."), findsOneWidget);
    expect(find.byKey(const ValueKey('challenge-invite-join')), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Open challenge'), findsOneWidget);
  });

  testWidgets('a failed read offers a retry rather than calling the link dead', (tester) async {
    final social = _FakeSocial(throwOnPreview: true);
    await _pump(tester, social);
    expect(find.textContaining("Couldn't load this invite"), findsOneWidget);
    expect(find.text("This invite link doesn't work"), findsNothing);
    social
      ..throwOnPreview = false
      ..preview = _preview();
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Run 50 km with me'), findsOneWidget);
  });
}

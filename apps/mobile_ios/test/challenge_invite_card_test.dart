// ChallengeInviteCard (decisions § 2261): the creator's invite link, gated on
// the server flag, a reset behind a confirm, and a public challenge's share
// page for anyone.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/social_service.dart';
import '../lib/widgets/challenge_invite_card.dart';

class _FakeSocial extends SocialService {
  _FakeSocial({this.enabled = true});
  bool enabled;
  String token = 'tokenOne_12345678';
  int rotations = 0;
  int refReads = 0;

  @override
  Future<String?> myShareRef() async {
    refReads++;
    return 'a1b2c3d4e5';
  }

  @override
  Future<bool> challengeInviteLinksEnabled() async => enabled;

  @override
  Future<String?> getChallengeInviteToken(String id) async => token;

  @override
  Future<String?> rotateChallengeInviteToken(String id) async {
    rotations++;
    token = 'tokenTwo_87654321';
    return token;
  }
}

Future<void> _pump(WidgetTester tester, _FakeSocial social,
    {bool isPublic = false, bool canManage = true, bool isCreator = false}) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: ChallengeInviteCard(
          social: social,
          challengeId: 'c1',
          isPublic: isPublic,
          canManage: canManage,
          isCreator: isCreator,
          webBaseOverride: 'https://threkir.com',
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets("the creator's public share link reads their ref (decisions § 2268)",
      (tester) async {
    final creator = _FakeSocial();
    await _pump(tester, creator, isPublic: true, isCreator: true);
    expect(creator.refReads, 1);
  });

  testWidgets('a club admin sharing it reads no ref', (tester) async {
    final admin = _FakeSocial();
    await _pump(tester, admin, isPublic: true);
    expect(admin.refReads, 0);
  });

  testWidgets('a private challenge has no share link, so no ref is read', (tester) async {
    final creator = _FakeSocial();
    await _pump(tester, creator, isCreator: true);
    expect(creator.refReads, 0);
  });

  testWidgets('the creator sees the invite link on the web host', (tester) async {
    await _pump(tester, _FakeSocial());
    expect(find.text('https://threkir.com/challenges/join/tokenOne_12345678'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
  });

  testWidgets('with the gate closed a private challenge shows nothing', (tester) async {
    await _pump(tester, _FakeSocial(enabled: false));
    expect(find.text('Invite link'), findsNothing);
  });

  testWidgets('a reset asks first and then shows the new link', (tester) async {
    final social = _FakeSocial();
    await _pump(tester, social);
    await tester.tap(find.byKey(const ValueKey('challenge-invite-rotate')));
    await tester.pumpAndSettle();
    expect(find.text('Reset the invite link?'), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Reset link')));
    await tester.pumpAndSettle();
    expect(social.rotations, 1);
    expect(find.text('https://threkir.com/challenges/join/tokenTwo_87654321'), findsOneWidget);
  });

  testWidgets('cancelling the reset keeps the link', (tester) async {
    final social = _FakeSocial();
    await _pump(tester, social);
    await tester.tap(find.byKey(const ValueKey('challenge-invite-rotate')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(social.rotations, 0);
  });

  testWidgets('a non-creator on a public challenge gets only the share page', (tester) async {
    await _pump(tester, _FakeSocial(), isPublic: true, canManage: false);
    expect(find.byKey(const ValueKey('challenge-share-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('challenge-invite-url')), findsNothing);
  });
}

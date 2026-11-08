// ClubInviteCard, ClubInviteButton + ClubShareButton: an admin's invite link on every club
// whatever its join policy, a reset behind a confirm, and a public club's
// share page for anyone (issue #1300 CLB-03). Mirrors the web invite card
// and "Share club" button on /clubs/[slug].

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/social_service.dart';
import '../lib/widgets/club_invite_card.dart';

const _share = MethodChannel('dev.fluttercommunity.plus/share');

ClubView _club({
  String joinPolicy = 'request',
  bool isPublic = true,
  bool shadowHidden = false,
}) =>
    ClubView(
      row: ClubRow(
        shadowHidden: shadowHidden,
        id: 'club-1',
        ownerId: 'owner',
        name: 'Tempo Tuesday',
        slug: 'tempo-tuesday',
        isPublic: isPublic,
        joinPolicy: joinPolicy,
        memberCount: 5,
        isVerified: false,
        requiresActivityWaiver: false,
      ),
      memberCount: 5,
      viewerRole: 'owner',
      viewerStatus: 'active',
      joinPolicy: joinPolicy,
    );

class _FakeSocial extends SocialService {
  _FakeSocial({this.token, this.failLoad = false});
  String? token;
  bool failLoad;
  int loads = 0;
  int writes = 0;

  @override
  Future<String?> getClubInviteToken(String clubId) async {
    loads++;
    if (failLoad) throw Exception('offline');
    return token;
  }

  @override
  Future<String> regenerateClubInviteToken(String clubId) async {
    writes++;
    token = 'fresh${'0' * 27}';
    return token!;
  }
}

Future<void> _pump(WidgetTester tester, Widget body, {Widget? action}) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      appBar: AppBar(actions: [?action]),
      body: SingleChildScrollView(child: body),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

ClubInviteCard _card(_FakeSocial social, {String joinPolicy = 'request'}) =>
    ClubInviteCard(
      social: social,
      club: _club(joinPolicy: joinPolicy),
      webBaseOverride: 'https://threkir.com',
    );

void main() {
  final shared = <Object?>[];

  setUp(() {
    shared.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_share, (call) async {
      shared.add((call.arguments as Map)['text']);
      return 'dev.fluttercommunity.plus/share/success';
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_share, null);
  });

  testWidgets('a request-to-join club admin makes a first link without a confirm',
      (tester) async {
    final social = _FakeSocial();
    await _pump(tester, _card(social));
    expect(find.text('Anyone with this link joins straight away, without waiting for approval.'),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('club-invite-generate')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(social.writes, 1);
    expect(find.text('https://threkir.com/clubs/join/fresh${'0' * 27}'), findsOneWidget);
  });

  testWidgets('the body says what the link grants under each policy', (tester) async {
    await _pump(tester, _card(_FakeSocial(token: 'abc'), joinPolicy: 'invite'));
    expect(find.text('Only people with this link can join.'), findsOneWidget);
    await _pump(tester, _card(_FakeSocial(token: 'abc'), joinPolicy: 'open'));
    expect(find.text('Anyone with this link can join.'), findsOneWidget);
  });

  testWidgets('Share link hands the invite link to the share sheet', (tester) async {
    await _pump(tester, _card(_FakeSocial(token: 'abc123')));
    await tester.tap(find.text('Share link'));
    await tester.pump();
    expect(shared, ['https://threkir.com/clubs/join/abc123']);
  });

  testWidgets('a reset asks first and then shows the new link', (tester) async {
    final social = _FakeSocial(token: 'old');
    await _pump(tester, _card(social));
    await tester.tap(find.byKey(const ValueKey('club-invite-rotate')));
    await tester.pumpAndSettle();
    expect(find.text('Reset the invite link?'), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Reset link')));
    await tester.pumpAndSettle();
    expect(social.writes, 1);
    expect(find.text('https://threkir.com/clubs/join/fresh${'0' * 27}'), findsOneWidget);
  });

  testWidgets('cancelling the reset keeps the link', (tester) async {
    final social = _FakeSocial(token: 'old');
    await _pump(tester, _card(social));
    await tester.tap(find.byKey(const ValueKey('club-invite-rotate')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(social.writes, 0);
    expect(find.text('https://threkir.com/clubs/join/old'), findsOneWidget);
  });

  testWidgets('a failed load offers a retry instead of a generate button', (tester) async {
    final social = _FakeSocial(token: 'abc', failLoad: true);
    await _pump(tester, _card(social));
    expect(find.text("Couldn't load the invite link."), findsOneWidget);
    expect(find.byKey(const ValueKey('club-invite-generate')), findsNothing);
    social.failLoad = false;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(social.loads, 2);
    expect(find.text('https://threkir.com/clubs/join/abc'), findsOneWidget);
  });

  testWidgets('Share club hands out the public share page', (tester) async {
    await _pump(tester, const SizedBox(),
        action: ClubShareButton(club: _club(), webBaseOverride: 'https://threkir.com'));
    await tester.tap(find.byKey(const ValueKey('club-share')));
    await tester.pump();
    expect(shared, ['https://threkir.com/share/club/tempo-tuesday']);
  });

  testWidgets("an admin's invite action opens the link and the share page",
      (tester) async {
    await _pump(tester, const SizedBox(),
        action: ClubInviteButton(
            social: _FakeSocial(token: 'abc123'),
            club: _club(),
            webBaseOverride: 'https://threkir.com'));
    await tester.tap(find.byKey(const ValueKey('club-invite')));
    await tester.pumpAndSettle();
    expect(find.text('https://threkir.com/clubs/join/abc123'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('club-share-page')));
    await tester.pump();
    expect(shared, ['https://threkir.com/share/club/tempo-tuesday']);
  });

  testWidgets('a private club admin gets the invite link and no share page',
      (tester) async {
    await _pump(tester, const SizedBox(),
        action: ClubInviteButton(
            social: _FakeSocial(token: 'abc123'),
            club: _club(joinPolicy: 'invite', isPublic: false),
            webBaseOverride: 'https://threkir.com'));
    await tester.tap(find.byKey(const ValueKey('club-invite')));
    await tester.pumpAndSettle();
    expect(find.text('Only people with this link can join.'), findsOneWidget);
    expect(find.byKey(const ValueKey('club-share-page')), findsNothing);
  });

  test('only a public, visible club has a share page to hand out', () {
    expect(canShareClub(_club()), isTrue);
    expect(canShareClub(_club(isPublic: false)), isFalse);
    expect(canShareClub(_club(shadowHidden: true)), isFalse);
  });
}

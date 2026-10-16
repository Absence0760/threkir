import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/clubs_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import '../lib/widgets/undo_bar.dart';

/// "Your Strava clubs" on My clubs (issue #1151 step 4, decisions § 1959) —
/// the mobile mirror of web's `tests-e2e/clubs/strava-clubs.spec.ts` (the
/// inert build) and `tests-e2e/configured/strava-clubs.spec.ts` (a build with
/// a Strava client id), plus the load-failure and reconnect states web pins
/// in its component. The api client is faked at its methods; the parser,
/// the screen and the undo queue are real.

const _richmond = (
  id: 'c1111111-0000-0000-0000-000000000001',
  slug: 'richmond-run-club',
  name: 'Richmond Run Club',
);

const _stravaClubId = 918273645;

StravaClub _stravaClub({
  int id = _stravaClubId,
  String name = 'Strava Only Striders',
  String? city = 'Leeds',
  int? memberCount = 12,
  bool? viewerIsAdmin = true,
  StravaLinkedClub? linked,
}) =>
    StravaClub(
      stravaClubId: id,
      name: name,
      city: city,
      country: 'United Kingdom',
      sportType: 'running',
      memberCount: memberCount,
      viewerIsAdmin: viewerIsAdmin,
      linkedClub: linked,
    );

ClubView _mine({
  String? role = 'owner',
  String id = 'c1111111-0000-0000-0000-000000000001',
  String slug = 'richmond-run-club',
  String name = 'Richmond Run Club',
}) =>
    ClubView(
      row: ClubRow(
        shadowHidden: false,
        id: id,
        ownerId: 'owner',
        name: name,
        slug: slug,
        isPublic: true,
        isVerified: false,
        joinPolicy: 'open',
        memberCount: 3,
        requiresActivityWaiver: false,
      ),
      memberCount: 3,
      viewerRole: role,
      viewerStatus: role == null ? null : 'active',
      joinPolicy: 'open',
    );

class _FakeSocial extends SocialService {
  _FakeSocial(this.mine);
  final List<ClubView> mine;

  @override
  Future<List<ClubView>> browseClubs({String? query}) async => const [];

  @override
  Future<List<ClubView>> fetchMyClubs() async => mine;
}

class _FakeApi extends ApiClient {
  _FakeApi(this.listed);

  /// What `list` answers; an [Exception] is thrown instead.
  Object listed;
  int listCalls = 0;
  final List<(String, int)> links = [];
  final List<String> unlinks = [];
  StravaClubLinkError? refuseLink;
  Exception? failLink;
  Exception? failUnlink;

  @override
  Future<StravaClubsResult> fetchMyStravaClubs() async {
    listCalls++;
    final l = listed;
    if (l is Exception) throw l;
    return l as StravaClubsResult;
  }

  @override
  Future<void> linkStravaClub(String clubId, int stravaClubId) async {
    links.add((clubId, stravaClubId));
    final failed = failLink;
    if (failed != null) throw failed;
    final refused = refuseLink;
    if (refused != null) throw StravaClubLinkFailure(refused);
  }

  @override
  Future<void> unlinkStravaClub(String clubId) async {
    unlinks.add(clubId);
    final failed = failUnlink;
    if (failed != null) throw failed;
  }
}

StravaClubsResult _connected(List<StravaClub> clubs) =>
    StravaClubsResult(StravaClubsStatus.connected, clubs);

Future<AppLocalizations> _l10n() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pump(
  WidgetTester tester,
  _FakeApi api, {
  List<ClubView>? mine,
  bool configured = true,
}) async {
  // Room for the club list and the section below it without scrolling.
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ClubsScreen(
        social: _FakeSocial(mine ?? [_mine()]),
        training: TrainingService(),
        apiClient: api,
        stravaConfigured: () => configured,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Finder _row(int id) => find.byKey(ValueKey('strava-club-$id'));

Finder _inRow(int id, Finder f) => find.descendant(of: _row(id), matching: f);

void main() {
  setUpAll(() => dotenv.loadFromString(isOptional: true));
  tearDown(debugResetUndo);

  testWidgets('a build without a Strava client id never asks Strava',
      (tester) async {
    final api = _FakeApi(_connected([_stravaClub()]));
    await _pump(tester, api, configured: false);

    expect(api.listCalls, 0);
    expect(find.byKey(const ValueKey('strava-clubs')), findsNothing);
    expect(find.text(_richmond.name), findsOneWidget);
  });

  testWidgets('a runner who is not connected sees nothing of it',
      (tester) async {
    final api =
        _FakeApi(const StravaClubsResult(StravaClubsStatus.notConnected));
    await _pump(tester, api);

    expect(api.listCalls, 1);
    expect(find.byKey(const ValueKey('strava-clubs')), findsNothing);
  });

  testWidgets(
      "lists the runner's Strava clubs with the actions each one allows",
      (tester) async {
    final l = await _l10n();
    final api = _FakeApi(_connected([
      _stravaClub(),
      _stravaClub(
        id: _stravaClubId + 1,
        name: 'Member Only Milers',
        city: null,
        memberCount: 1,
        viewerIsAdmin: false,
      ),
    ]));
    await _pump(tester, api);

    expect(find.text(l.stravaClubsHeading), findsOneWidget);
    expect(api.listCalls, 1);

    expect(_inRow(_stravaClubId, find.text('Leeds, United Kingdom · 12 members')),
        findsOneWidget);
    expect(_inRow(_stravaClubId, find.text(l.stravaClubsSetUp)),
        findsOneWidget);
    expect(_inRow(_stravaClubId, find.text(l.stravaClubsLinkToMine)),
        findsOneWidget);

    final member = _stravaClubId + 1;
    expect(_inRow(member, find.text('United Kingdom · 1 member')),
        findsOneWidget);
    expect(_inRow(member, find.text(l.stravaClubsAdminOnly)), findsOneWidget);
    expect(_inRow(member, find.text(l.stravaClubsSetUp)), findsNothing);
    expect(_inRow(member, find.text(l.stravaClubsLinkToMine)), findsNothing);
  });

  testWidgets('linking is offered only to a runner who administers a club',
      (tester) async {
    final l = await _l10n();
    final api = _FakeApi(_connected([_stravaClub()]));
    await _pump(tester, api, mine: [_mine(role: 'member')]);

    expect(_inRow(_stravaClubId, find.text(l.stravaClubsSetUp)),
        findsOneWidget);
    expect(_inRow(_stravaClubId, find.text(l.stravaClubsLinkToMine)),
        findsNothing);
  });

  testWidgets("links a Strava club to one of the runner's own clubs",
      (tester) async {
    final l = await _l10n();
    final api = _FakeApi(_connected([_stravaClub()]));
    await _pump(tester, api);

    await tester.tap(_inRow(_stravaClubId, find.text(l.stravaClubsLinkToMine)));
    await tester.pumpAndSettle();
    expect(find.text(l.stravaClubsPickClubLabel), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(SimpleDialog), matching: find.text(_richmond.name)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.links, [(_richmond.id, _stravaClubId)]);
    expect(
        _inRow(_stravaClubId,
            find.text(l.stravaClubsViewOnThrekir(_richmond.name))),
        findsOneWidget);
    expect(_inRow(_stravaClubId, find.text(l.stravaClubsUnlink)),
        findsOneWidget);
    expect(find.text(l.stravaClubsLinked(_richmond.name)), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
  });

  testWidgets('a refused link says why and leaves the row unlinked',
      (tester) async {
    final l = await _l10n();
    final api = _FakeApi(_connected([_stravaClub()]))
      ..refuseLink = StravaClubLinkError.stravaAdminRequired;
    await _pump(tester, api);

    await tester.tap(_inRow(_stravaClubId, find.text(l.stravaClubsLinkToMine)));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(SimpleDialog), matching: find.text(_richmond.name)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(l.stravaClubsErrAdminRequired), findsOneWidget);
    expect(find.text(l.stravaClubsLinked(_richmond.name)), findsNothing);
    expect(_inRow(_stravaClubId, find.text(l.stravaClubsSetUp)),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
  });

  testWidgets('a link that fails without a reason says so, not "linked"',
      (tester) async {
    final l = await _l10n();
    final api = _FakeApi(_connected([_stravaClub()]))
      ..failLink = Exception('network');
    await _pump(tester, api);

    await tester.tap(_inRow(_stravaClubId, find.text(l.stravaClubsLinkToMine)));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(SimpleDialog), matching: find.text(_richmond.name)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(l.stravaClubsErrGeneric), findsOneWidget);
    expect(find.text(l.stravaClubsLinked(_richmond.name)), findsNothing);
    expect(
        _inRow(_stravaClubId,
            find.text(l.stravaClubsViewOnThrekir(_richmond.name))),
        findsNothing);
    await tester.pump(const Duration(seconds: 9));
  });

  testWidgets(
      'the picker offers only the clubs the runner owns or administers',
      (tester) async {
    final l = await _l10n();
    final api = _FakeApi(_connected([_stravaClub()]));
    await _pump(tester, api, mine: [
      _mine(),
      _mine(
          role: 'member',
          id: 'c2222222-0000-0000-0000-000000000002',
          slug: 'joined-joggers',
          name: 'Joined Joggers'),
      _mine(
          role: 'admin',
          id: 'c3333333-0000-0000-0000-000000000003',
          slug: 'admin-athletics',
          name: 'Admin Athletics'),
    ]);

    await tester.tap(_inRow(_stravaClubId, find.text(l.stravaClubsLinkToMine)));
    await tester.pumpAndSettle();

    final picker = find.byType(SimpleDialog);
    expect(find.descendant(of: picker, matching: find.text(_richmond.name)),
        findsOneWidget);
    expect(
        find.descendant(of: picker, matching: find.text('Admin Athletics')),
        findsOneWidget);
    expect(
        find.descendant(of: picker, matching: find.text('Joined Joggers')),
        findsNothing);
  });

  testWidgets(
      'linking a club moves it off the Strava club it was linked to before',
      (tester) async {
    final l = await _l10n();
    final other = _stravaClubId + 1;
    final api = _FakeApi(_connected([
      _stravaClub(),
      _stravaClub(
        id: other,
        name: 'Previously Linked',
        linked: StravaLinkedClub(
            id: _richmond.id, slug: _richmond.slug, name: _richmond.name),
      ),
    ]));
    await _pump(tester, api);

    await tester.tap(_inRow(_stravaClubId, find.text(l.stravaClubsLinkToMine)));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(SimpleDialog), matching: find.text(_richmond.name)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
        _inRow(_stravaClubId,
            find.text(l.stravaClubsViewOnThrekir(_richmond.name))),
        findsOneWidget);
    expect(_inRow(other, find.text(l.stravaClubsViewOnThrekir(_richmond.name))),
        findsNothing);
    expect(_inRow(other, find.text(l.stravaClubsSetUp)), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
  });

  testWidgets(
      "a row linked to a club the runner doesn't administer offers no unlink",
      (tester) async {
    final l = await _l10n();
    final api = _FakeApi(_connected([
      _stravaClub(
        linked: const StravaLinkedClub(
            id: 'c9999999-0000-0000-0000-000000000009',
            slug: 'someone-elses-club',
            name: "Someone Else's Club"),
      ),
    ]));
    await _pump(tester, api);

    expect(
        _inRow(_stravaClubId,
            find.text(l.stravaClubsViewOnThrekir("Someone Else's Club"))),
        findsOneWidget);
    expect(_inRow(_stravaClubId, find.text(l.stravaClubsUnlink)), findsNothing);
  });

  testWidgets('cancelling the picker links nothing', (tester) async {
    final l = await _l10n();
    final api = _FakeApi(_connected([_stravaClub()]));
    await _pump(tester, api);

    await tester.tap(_inRow(_stravaClubId, find.text(l.stravaClubsLinkToMine)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.commonCancel));
    await tester.pumpAndSettle();

    expect(api.links, isEmpty);
    expect(find.byType(SimpleDialog), findsNothing);
  });

  group('unlinking is undoable, and commits once the offer closes', () {
    Future<_FakeApi> openLinked(WidgetTester tester) async {
      final api = _FakeApi(_connected([
        _stravaClub(
          linked: StravaLinkedClub(
              id: _richmond.id, slug: _richmond.slug, name: _richmond.name),
        ),
      ]));
      await _pump(tester, api);
      return api;
    }

    testWidgets('Undo puts the link back and unlinks nothing',
        (tester) async {
      final l = await _l10n();
      final api = await openLinked(tester);

      await tester.tap(_inRow(_stravaClubId, find.text(l.stravaClubsUnlink)));
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing,
          reason: 'confirm and undo are alternatives, not partners');
      expect(_inRow(_stravaClubId, find.text(l.stravaClubsSetUp)),
          findsOneWidget);
      expect(find.text(l.stravaClubsUnlinked(_richmond.name)), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(
          _inRow(_stravaClubId,
              find.text(l.stravaClubsViewOnThrekir(_richmond.name))),
          findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
      expect(api.unlinks, isEmpty);
    });

    testWidgets('the window closing commits the held unlink', (tester) async {
      final l = await _l10n();
      final api = await openLinked(tester);

      await tester.tap(_inRow(_stravaClubId, find.text(l.stravaClubsUnlink)));
      await tester.pump();
      expect(api.unlinks, isEmpty);

      await tester.pump(const Duration(seconds: 9));
      expect(api.unlinks, [_richmond.id]);
      expect(_inRow(_stravaClubId, find.text(l.stravaClubsSetUp)),
          findsOneWidget);
    });

    testWidgets('a refused unlink puts the link back and says so',
        (tester) async {
      final l = await _l10n();
      final api = await openLinked(tester)
        ..failUnlink = Exception('rpc');

      await tester.tap(_inRow(_stravaClubId, find.text(l.stravaClubsUnlink)));
      await tester.pump();
      expect(_inRow(_stravaClubId, find.text(l.stravaClubsSetUp)),
          findsOneWidget);

      await tester.pump(const Duration(seconds: 9));
      await tester.pump();
      expect(api.unlinks, [_richmond.id]);
      expect(
          _inRow(_stravaClubId,
              find.text(l.stravaClubsViewOnThrekir(_richmond.name))),
          findsOneWidget);
      expect(find.text(l.stravaClubsErrUnlink), findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
    });
  });

  testWidgets('a failed load shows its own error and leaves the clubs alone',
      (tester) async {
    final l = await _l10n();
    final api = _FakeApi(Exception('strava_unavailable'));
    await _pump(tester, api);

    expect(find.text(_richmond.name), findsWidgets);
    expect(find.text(l.stravaClubsLoadError), findsOneWidget);

    api.listed = _connected([_stravaClub()]);
    await tester.tap(find.text(l.errorStateRetry));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.listCalls, 2);
    expect(_row(_stravaClubId), findsOneWidget);
  });

  testWidgets('a dead grant asks the runner to reconnect', (tester) async {
    final l = await _l10n();
    final api =
        _FakeApi(const StravaClubsResult(StravaClubsStatus.reconnectRequired));
    await _pump(tester, api);

    expect(find.text(l.stravaClubsReconnectText), findsOneWidget);
    expect(find.text(l.stravaClubsReconnect), findsOneWidget);
  });

  testWidgets('connected but in no clubs says so', (tester) async {
    final l = await _l10n();
    final api = _FakeApi(_connected(const []));
    await _pump(tester, api);

    expect(find.text(l.stravaClubsEmpty), findsOneWidget);
  });

  testWidgets('the section shows under an empty My clubs too',
      (tester) async {
    final l = await _l10n();
    final api = _FakeApi(_connected([_stravaClub()]));
    await _pump(tester, api, mine: const []);

    expect(find.byIcon(Icons.person_add_alt_1), findsOneWidget);
    expect(find.text(l.stravaClubsHeading), findsOneWidget);
    expect(_inRow(_stravaClubId, find.text(l.stravaClubsLinkToMine)),
        findsNothing);
  });

  testWidgets('Set up on Threkir opens the new-club form prefilled',
      (tester) async {
    final l = await _l10n();
    final api = _FakeApi(_connected([_stravaClub()]));
    await _pump(tester, api);

    await tester.tap(_inRow(_stravaClubId, find.text(l.stravaClubsSetUp)));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Strava Only Striders'),
        findsOneWidget);
    expect(find.widgetWithText(TextField, 'Leeds, United Kingdom'),
        findsOneWidget);
    expect(find.text(l.stravaClubsSetUpNote), findsOneWidget);
  });
}

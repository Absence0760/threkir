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

ClubView _mine({String? role = 'owner'}) => ClubView(
      row: ClubRow(
        shadowHidden: false,
        id: _richmond.id,
        ownerId: 'owner',
        name: _richmond.name,
        slug: _richmond.slug,
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
    final refused = refuseLink;
    if (refused != null) throw StravaClubLinkFailure(refused);
  }

  @override
  Future<void> unlinkStravaClub(String clubId) async {
    unlinks.add(clubId);
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
    expect(_inRow(_stravaClubId, find.text(l.stravaClubsSetUp)),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
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

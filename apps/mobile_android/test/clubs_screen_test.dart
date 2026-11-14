import 'dart:async';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';
import '../lib/geocoding.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/clubs_screen.dart';
import '../lib/screens/help_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import '../lib/widgets/error_state.dart';
import '../lib/widgets/verified_badge.dart';

ClubView _club({
  String id = 'club-1',
  String name = 'Track Club',
  String slug = 'track-club',
  bool isPublic = true,
  bool isVerified = false,
  String? locationLabel,
  int memberCount = 5,
  String? viewerRole,
}) =>
    ClubView(
      row: ClubRow(shadowHidden: false, 
        id: id,
        ownerId: 'owner',
        name: name,
        slug: slug,
        isPublic: isPublic,
        isVerified: isVerified,
        locationLabel: locationLabel,
        joinPolicy: 'open',
        memberCount: memberCount,
        requiresActivityWaiver: false,
      ),
      memberCount: memberCount,
      viewerRole: viewerRole,
      viewerStatus: viewerRole == null ? null : 'active',
      joinPolicy: 'open',
    );

/// Fake that returns canned browse / mine lists. Captures the term passed
/// to searchClubs so the Browse search wiring can be asserted.
class _FakeSocial extends SocialService {
  _FakeSocial({this.browse = const [], this.mine = const []});
  List<ClubView> browse;
  List<ClubView> mine;
  String? lastSearchTerm;
  int browseCalls = 0;

  @override
  Future<List<ClubView>> browseClubs({String? query}) async {
    browseCalls++;
    return browse;
  }

  @override
  Future<List<ClubView>> searchClubs(
    String query, {
    required String mapTilerKey,
    Future<GeocodedPlace?> Function(String)? geocoder,
  }) async {
    lastSearchTerm = query;
    return browse;
  }

  @override
  Future<List<ClubView>> fetchMyClubs() async => mine;
}

/// Fake whose load throws, to drive the generic error state.
class _ThrowingSocial extends SocialService {
  @override
  Future<List<ClubView>> browseClubs({String? query}) async =>
      throw Exception('boom');
  @override
  Future<List<ClubView>> fetchMyClubs() async => const [];
}

/// Fake whose load stays in flight until [gate] is completed, so a test
/// can observe the loading spinner before resolving it cleanly.
class _SlowSocial extends SocialService {
  final Completer<List<ClubView>> gate = Completer<List<ClubView>>();
  @override
  Future<List<ClubView>> browseClubs({String? query}) => gate.future;
  @override
  Future<List<ClubView>> fetchMyClubs() async => const [];
}

Future<void> _pump(WidgetTester tester, SocialService social) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ClubsScreen(
        social: social,
        training: TrainingService(),
      ),
    ),
  );
}

final _browseChip = find.descendant(
    of: find.byKey(const Key('view-switch')), matching: find.text('Browse'));

void main() {
  setUpAll(() {
    // ClubsScreen._load reads dotenv.env['MAPTILER_KEY']; without a
    // testLoad the access throws NotInitializedError and the load fails
    // into the error state before any list can render.
    dotenv.loadFromString(isOptional: true);
  });

  group('ClubsScreen — initial render', () {
    testWidgets('renders the Clubs app-bar title', (tester) async {
      await _pump(tester, _FakeSocial());
      await tester.pump();
      expect(find.widgetWithText(PageHeading, 'Clubs'), findsOneWidget);
    });

    testWidgets('Browse · My clubs is the view switch of the one FilterBar, '
        'not chips', (tester) async {
      await _pump(tester, _FakeSocial());
      await tester.pump();
      final bar = find.byKey(const ValueKey('clubs-filter-bar'));
      expect(bar, findsOneWidget);
      expect(
          find.descendant(of: bar, matching: find.byType(ViewSwitch<int>)),
          findsOneWidget);
      expect(find.descendant(of: bar, matching: _browseChip), findsOneWidget);
      expect(find.descendant(of: bar, matching: find.byType(ChoiceChip)),
          findsNothing);
    });

    testWidgets('Join with invite code sits in the search row, not on a row '
        'of its own, and the empty My clubs tab offers it too',
        (tester) async {
      await _pump(tester, _FakeSocial());
      await tester.pump();
      final code = find.byKey(const ValueKey('clubs-join-with-code'));
      expect(code, findsOneWidget);
      expect(tester.getCenter(code).dy,
          closeTo(tester.getCenter(find.byType(TextField)).dy, 1));
      expect(find.widgetWithText(TextButton, 'Join with invite code'),
          findsOneWidget);
    });

    testWidgets('starts on the My clubs tab, with My clubs\' own search',
        (tester) async {
      // Returning users default to "My clubs" so they see the clubs they're
      // already in. Its search filters those; Browse's searches the catalogue.
      await _pump(tester, _FakeSocial());
      await tester.pump();
      expect(find.widgetWithText(TextField, 'Search your clubs'),
          findsOneWidget);
      expect(find.widgetWithText(TextField, 'Search by name or location'),
          findsNothing);
    });

    testWidgets('My clubs\' search narrows by name as it is typed, and a '
        'search that matches none says so and clears', (tester) async {
      final social = _FakeSocial(mine: [
        _club(id: 'a', name: 'Morning Milers', slug: 'morning-milers'),
        _club(id: 'b', name: 'Sunset Striders', slug: 'sunset-striders'),
      ]);
      await _pump(tester, social);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final field = find.widgetWithText(TextField, 'Search your clubs');
      await tester.enterText(field, 'sunset');
      await tester.pump();
      expect(find.text('Sunset Striders'), findsOneWidget);
      expect(find.text('Morning Milers'), findsNothing);
      expect(social.lastSearchTerm, isNull,
          reason: 'a filter over the loaded clubs, not a server search');

      await tester.enterText(field, 'zzz');
      await tester.pump();
      expect(find.byKey(const ValueKey('clubs-mine-no-match')), findsOneWidget);
      expect(find.text('None of your clubs match your search'), findsOneWidget);
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('clubs-mine-no-match')),
          matching: find.text('Clear search')));
      await tester.pump();
      expect(find.text('Morning Milers'), findsOneWidget);
      expect(find.text('Sunset Striders'), findsOneWidget);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('at 320 dp and ${scale}x the views, search and code button '
          'fit, with nothing cut', (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(
                size: const Size(320, 800),
                textScaler: TextScaler.linear(scale)),
            child: ClubsScreen(social: _FakeSocial(), training: TrainingService()),
          ),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);
        final views = tester.getRect(find.byKey(const Key('view-switch')));
        expect(views.left, greaterThanOrEqualTo(0));
        final code =
            tester.getRect(find.byKey(const ValueKey('clubs-join-with-code')));
        expect(code.right, lessThanOrEqualTo(320));
        expect(code.top, greaterThanOrEqualTo(views.bottom));
      });
    }

    testWidgets('renders the New club FAB with an add icon',
        (tester) async {
      await _pump(tester, _FakeSocial());
      await tester.pump();
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('New club'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('switching to the Browse tab reveals the search field',
        (tester) async {
      await _pump(tester, _FakeSocial());
      await tester.pump();
      // Tap the "Browse" segment.
      await tester.tap(_browseChip);
      await tester.pump();
      expect(find.widgetWithText(TextField, 'Search by name or location'),
          findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('the Browse search field exposes a persistent accessible name',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _FakeSocial());
      await tester.pump();
      await tester.tap(_browseChip);
      await tester.pump();
      // Semantics wrapper keeps the field named once the hint disappears on
      // typing (web parity: SocialClubs' aria-label).
      expect(
        find.bySemanticsLabel(RegExp('Search by name or location')),
        findsAtLeastNWidgets(1),
      );
      handle.dispose();
    });
  });

  group('ClubsScreen — list rendering', () {
    testWidgets('renders a row per "my club" once the load resolves',
        (tester) async {
      await _pump(
        tester,
        _FakeSocial(mine: [
          _club(id: 'a', name: 'Morning Milers', slug: 'morning-milers'),
          _club(id: 'b', name: 'Sunset Striders', slug: 'sunset-striders'),
        ]),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Morning Milers'), findsOneWidget);
      expect(find.text('Sunset Striders'), findsOneWidget);
      expect(find.byType(IdentityAvatar), findsNWidgets(2));
    });

    testWidgets('a private club shows the PRIVATE badge', (tester) async {
      await _pump(
        tester,
        _FakeSocial(mine: [_club(name: 'Secret Squad', isPublic: false)]),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('PRIVATE'), findsOneWidget);
    });

    testWidgets('a verified club renders the verified badge', (tester) async {
      await _pump(
        tester,
        _FakeSocial(mine: [_club(name: 'Richmond Marathon', isVerified: true)]),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(VerifiedBadge), findsOneWidget);
    });

    testWidgets('a club with a location renders the place label',
        (tester) async {
      await _pump(
        tester,
        _FakeSocial(mine: [_club(locationLabel: 'Norfolk, VA')]),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Norfolk, VA'), findsOneWidget);
      expect(find.byIcon(Icons.place), findsOneWidget);
    });

    testWidgets('a viewer role pill shows for clubs the user belongs to',
        (tester) async {
      await _pump(
        tester,
        _FakeSocial(mine: [_club(viewerRole: 'admin')]),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('admin'), findsOneWidget);
    });
  });

  group('ClubsScreen — empty states', () {
    testWidgets('an empty My clubs tab shows the mine empty state',
        (tester) async {
      await _pump(tester, _FakeSocial(mine: const [], browse: const []));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // person_add_alt_1 is the My-clubs empty glyph.
      expect(find.byIcon(Icons.person_add_alt_1), findsOneWidget);
    });

    testWidgets('an empty Browse tab shows the browse empty state',
        (tester) async {
      await _pump(tester, _FakeSocial(mine: const [], browse: const []));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(_browseChip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // groups is the Browse empty glyph.
      expect(find.byIcon(Icons.groups_outlined), findsOneWidget);
    });
  });

  group('ClubsScreen — error states', () {
    testWidgets('a failed load shows the generic error state with Retry',
        (tester) async {
      await _pump(tester, _ThrowingSocial());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('a slow load shows the list skeleton before it resolves',
        (tester) async {
      final social = _SlowSocial();
      await _pump(tester, social);
      await tester.pump();
      // Load is gated → the skeleton persists until the gate completes.
      expect(find.byType(ListSkeleton), findsOneWidget);
      // Release the gate so the .timeout(...) timer + future drain cleanly.
      social.gate.complete(const []);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    });
  });

  group('ClubsScreen — Browse search', () {
    testWidgets('submitting a Browse query routes through searchClubs',
        (tester) async {
      final social = _FakeSocial(browse: const []);
      await _pump(tester, social);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(_browseChip);
      await tester.pump();

      await tester.enterText(
          find.widgetWithText(TextField, 'Search by name or location'),
          'Virginia');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(social.lastSearchTerm, 'Virginia');
    });
  });
  group('ClubsScreen — missing club (issue #1151)', () {
    Future<void> searchNothing(WidgetTester tester, String term) async {
      await _pump(tester, _FakeSocial());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(_browseChip);
      await tester.pump();
      await tester.enterText(
          find.widgetWithText(TextField, 'Search by name or location'), term);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('a search that finds nothing offers to set the club up',
        (tester) async {
      await searchNothing(tester, 'Nowhere Harriers');
      expect(find.textContaining('Is your club missing?'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Set up your club'),
          findsOneWidget);
      expect(find.widgetWithText(TextButton, 'How to create a club'),
          findsOneWidget);
    });

    testWidgets('Set up your club opens the new-club form prefilled',
        (tester) async {
      await searchNothing(tester, '  Nowhere Harriers  ');
      await tester.tap(find.widgetWithText(FilledButton, 'Set up your club'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.widgetWithText(TextField, 'Nowhere Harriers'),
          findsOneWidget);
    });

    testWidgets('How to create a club opens the create-a-club guide',
        (tester) async {
      await searchNothing(tester, 'Nowhere Harriers');
      await tester.tap(find.widgetWithText(TextButton, 'How to create a club'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final guide = tester.widget<GuideScreen>(find.byType(GuideScreen));
      expect(guide.guideId, 'create-a-club');
    });

    testWidgets('a failed load shows the error, not the set-up offer',
        (tester) async {
      await _pump(tester, _ThrowingSocial());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(_browseChip);
      await tester.pump();
      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.text('Set up your club'), findsNothing);
      expect(find.text('How to create a club'), findsNothing);
    });

    testWidgets('a load still in flight does not show the set-up offer',
        (tester) async {
      final social = _SlowSocial();
      await _pump(tester, social);
      await tester.pump();
      await tester.tap(_browseChip);
      await tester.pump();
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.text('Set up your club'), findsNothing);
      social.gate.complete(const []);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    });
  });
}

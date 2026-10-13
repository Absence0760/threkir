import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/help_destination.dart';
import '../lib/help_guides.dart';
import '../lib/help_loader.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/help_screen.dart';
import '../lib/widgets/help_button.dart';
import '../lib/widgets/info_tip.dart';

HelpLibrary _fixture() => HelpLibrary.parse(
  File('test/fixtures/help_guides.json').readAsStringSync(),
)!;

/// Hands every Help screen [library] instead of the generated asset.
void _useLibrary(HelpLibrary library) {
  helpLibraryLoader = () => Future.value(library);
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );
  await tester.pump();
}

/// Lets a push transition finish without `pumpAndSettle`, which the
/// skeleton's shimmer would never let settle if a load stalled.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

/// Fires the tap recognizer behind the [label] span of a rendered guide text.
void _tapSpan(WidgetTester tester, String label) {
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    TapGestureRecognizer? hit;
    rich.text.visitChildren((span) {
      if (span is TextSpan &&
          span.text == label &&
          span.recognizer is TapGestureRecognizer) {
        hit = span.recognizer! as TapGestureRecognizer;
        return false;
      }
      return true;
    });
    if (hit != null) {
      hit!.onTap!();
      return;
    }
  }
  fail('no tappable span "$label"');
}

bool _spanIsLink(WidgetTester tester, String label) {
  var found = false;
  var link = false;
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.text == label) {
        found = true;
        link = span.recognizer != null;
        return false;
      }
      return true;
    });
    if (found) break;
  }
  expect(found, isTrue, reason: 'no span "$label" rendered');
  return link;
}

void main() {
  late HelpLibrary library;

  setUp(() {
    library = _fixture();
    _useLibrary(library);
    pendingHelpDestination.value = null;
  });

  tearDown(() {
    helpLibraryLoader = loadHelpLibraryCached;
    pendingHelpDestination.value = null;
  });

  group('Help home', () {
    testWidgets('lists guides under their categories, newer ones under More', (
      tester,
    ) async {
      await _pump(tester, const HelpScreen());
      expect(find.text('Help'), findsOneWidget);
      expect(find.text('RACES'), findsOneWidget);
      expect(find.text('PAID CLASSES'), findsOneWidget);
      expect(find.text('Racing an event'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('A guide in a newer category'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('MORE GUIDES'), findsOneWidget);
    });

    testWidgets(
      'the audience filter keeps guides for that reader and everyone',
      (tester) async {
        await _pump(tester, const HelpScreen());
        await tester.tap(find.widgetWithText(ChoiceChip, 'Spectators'));
        await tester.pump();
        expect(find.text('Following a runner live'), findsOneWidget);
        expect(find.text('Connecting Strava'), findsOneWidget);
        expect(find.text('Racing an event'), findsNothing);
        expect(find.text('Charging for a class'), findsNothing);
      },
    );

    testWidgets('search replaces the categories with ranked results', (
      tester,
    ) async {
      await _pump(tester, const HelpScreen());
      await tester.enterText(find.byKey(const Key('help-search')), 'race');
      await tester.pump();
      expect(find.text('RESULTS'), findsOneWidget);
      expect(find.text('RACES'), findsNothing);
      final titles = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((t) => (t.title! as Text).data)
          .toList();
      expect(titles, [
        'Racing an event',
        'Following a runner live',
        'Charging for a class',
      ]);
    });

    testWidgets(
      'a search with no match says so, and clearing restores the list',
      (tester) async {
        await _pump(tester, const HelpScreen());
        await tester.enterText(find.byKey(const Key('help-search')), 'zzzz');
        await tester.pump();
        expect(find.text('No matching guides'), findsOneWidget);
        await tester.tap(find.byTooltip('Clear search'));
        await tester.pump();
        expect(find.text('No matching guides'), findsNothing);
        expect(find.text('Racing an event'), findsOneWidget);
      },
    );

    testWidgets('a guide row opens the guide', (tester) async {
      await _pump(tester, const HelpScreen());
      await tester.tap(find.text('Racing an event'));
      await _settle(tester);
      expect(find.byType(GuideScreen), findsOneWidget);
      expect(find.text('Before the start'), findsOneWidget);
    });

    testWidgets(
      'an unreadable guide asset is an unavailable state with retry',
      (tester) async {
        var loads = 0;
        helpLibraryLoader = () {
          loads++;
          return Future.value(loads == 1 ? null : library);
        };
        await _pump(tester, const HelpScreen());
        expect(find.text('Help guides could not be loaded.'), findsOneWidget);
        await tester.tap(find.text('Retry'));
        await tester.pump();
        await tester.pump();
        expect(loads, 2);
        expect(find.text('Racing an event'), findsOneWidget);
      },
    );

    testWidgets('an empty guide array is unavailable, not an empty list', (
      tester,
    ) async {
      _useLibrary(HelpLibrary(const []));
      await _pump(tester, const HelpScreen());
      expect(find.text('Help guides could not be loaded.'), findsOneWidget);
    });
  });

  group('Guide screen', () {
    testWidgets('renders summary, chips, steps, notes and related guides', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const GuideScreen(guideId: 'racing-an-event'));
      expect(find.text('Racing an event'), findsOneWidget);
      expect(find.text('Web'), findsOneWidget);
      expect(find.text('Android'), findsOneWidget);
      expect(find.text('iPhone'), findsOneWidget);
      expect(find.bySemanticsLabel('Step 2'), findsOneWidget);
      expect(find.byKey(const Key('help-note-tip')), findsOneWidget);
      expect(find.byKey(const Key('help-note-caution')), findsOneWidget);
      expect(find.text('Caution'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('RELATED GUIDES'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // A related id with no guide is dropped rather than listed dead.
      expect(
        find.byKey(const ValueKey('help-guide-following-live')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('help-guide-missing-guide')),
        findsNothing,
      );
      handle.dispose();
    });

    testWidgets('a gated guide shows its requirements', (tester) async {
      await _pump(tester, const GuideScreen(guideId: 'paid-class-setup'));
      expect(find.text('Needs Stripe connected'), findsOneWidget);
      expect(find.text('Needs paid registration on'), findsOneWidget);
    });

    testWidgets('a guide link opens that guide', (tester) async {
      await _pump(tester, const GuideScreen(guideId: 'racing-an-event'));
      _tapSpan(tester, 'how spectators follow you');
      await _settle(tester);
      expect(find.text('Opening the link'), findsOneWidget);
    });

    testWidgets('a mapped route link asks the shell for its destination', (
      tester,
    ) async {
      await _pump(tester, const GuideScreen(guideId: 'racing-an-event'));
      _tapSpan(tester, 'the races list');
      expect(pendingHelpDestination.value, HelpDestination.races);
    });

    testWidgets('an unmapped route renders as plain text', (tester) async {
      await _pump(tester, const GuideScreen(guideId: 'racing-an-event'));
      expect(_spanIsLink(tester, 'the old page'), isFalse);
      expect(_spanIsLink(tester, 'the races list'), isTrue);
    });

    testWidgets('an unknown guide id is a stated state with a way out', (
      tester,
    ) async {
      await _pump(tester, const GuideScreen(guideId: 'gone'));
      expect(find.text('This guide is not available.'), findsOneWidget);
      await tester.tap(find.text('Browse all guides'));
      await _settle(tester);
      expect(find.byType(HelpScreen), findsOneWidget);
    });
  });

  group('Guides for a screen', () {
    testWidgets('one match opens the guide itself', (tester) async {
      await _pump(
        tester,
        const HelpForRouteScreen(
          routes: ['/clubs/[slug]/events/[id]'],
          audience: 'participant',
        ),
      );
      expect(find.text('Before the start'), findsOneWidget);
    });

    testWidgets('several matches are listed with a way to everything', (
      tester,
    ) async {
      await _pump(
        tester,
        const HelpForRouteScreen(routes: ['/clubs/[slug]/events/[id]']),
      );
      expect(find.text('GUIDES FOR THIS SCREEN'), findsOneWidget);
      expect(find.text('Racing an event'), findsOneWidget);
      expect(find.text('Charging for a class'), findsOneWidget);
      expect(find.byKey(const Key('help-browse-all')), findsOneWidget);
    });

    testWidgets('no match falls back to the whole guide list', (tester) async {
      await _pump(tester, const HelpForRouteScreen(routes: ['/nowhere']));
      expect(find.byKey(const Key('help-search')), findsOneWidget);
    });

    testWidgets('the AppBar help button opens the guides for its routes', (
      tester,
    ) async {
      await _pump(
        tester,
        Scaffold(
          appBar: AppBar(
            actions: const [
              HelpButton(routes: ['/settings/integrations']),
            ],
          ),
        ),
      );
      await tester.tap(find.byTooltip('How this works'));
      await _settle(tester);
      expect(find.text('Connecting Strava'), findsOneWidget);
      expect(find.text('Connecting'), findsOneWidget);
    });
  });

  group('InfoTipButton', () {
    testWidgets('offers Read the guide only when it names one', (tester) async {
      await _pump(
        tester,
        const Scaffold(
          body: Column(
            children: [
              InfoTipButton(
                label: 'About Strava',
                title: 'Strava',
                body: 'Imports runs.',
                guideId: 'connect-strava',
              ),
              InfoTipButton(label: 'About HR', title: 'HR', body: 'Straps.'),
            ],
          ),
        ),
      );
      await tester.tap(find.byTooltip('About HR'));
      await _settle(tester);
      expect(find.text('Read the guide'), findsNothing);
      await tester.tap(find.text('Dismiss'));
      await _settle(tester);

      await tester.tap(find.byTooltip('About Strava'));
      await _settle(tester);
      await tester.tap(find.text('Read the guide'));
      await _settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(GuideScreen), findsOneWidget);
      expect(find.text('Connecting Strava'), findsOneWidget);
    });
  });
}

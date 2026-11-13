import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/ai_disclosure.dart';
import '../lib/local_route_store.dart';
import '../lib/preferences.dart';
import '../lib/route_describe_client.dart';
import '../lib/route_description.dart';
import '../lib/screens/route_detail_screen.dart';

cm.Route _route() => cm.Route(
      id: 'r1',
      userId: 'test-user',
      name: 'River Loop',
      waypoints: const [],
      distanceMetres: 5000,
      elevationGainMetres: 90,
      surface: 'trail',
    );

Future<void> _pump(
  WidgetTester tester, {
  Future<bool> Function()? checkPro,
  Future<AiDescriptionResult> Function(
          RouteDescriptionInput, cm.DistanceUnit, String, String)?
      describeAi,
  bool useMiles = false,
  Locale? locale,
}) async {
  SharedPreferences.setMockInitialValues({'use_miles': useMiles});
  final prefs = Preferences();
  await tester.runAsync(() => prefs.init());

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RouteDetailScreen(
        route: _route(),
        routeStore: LocalRouteStore(),
        preferences: prefs,
        checkPro: checkPro,
        describeAi: describeAi,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(Duration.zero);
}

Future<void> _tapDescribe(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -600));
  await tester.pump();
  await tester.tap(find.text('Describe this route'));
  // One frame to flush the templated baseline + the async Pro/AI work.
  await tester.pump();
  await tester.pump(Duration.zero);
}

void main() {
  setUpAll(() {
    dotenv.loadFromString(isOptional: true);
  });

  group('RouteDetailScreen describe affordance', () {
    testWidgets('shows the describe button for a route with no description',
        (tester) async {
      await _pump(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
      expect(find.text('Describe this route'), findsOneWidget);
    });

    testWidgets('non-Pro renders the templated baseline + upgrade hint, no AI',
        (tester) async {
      var aiCalled = false;
      await _pump(
        tester,
        checkPro: () async => false,
        describeAi: (_, __, ___, ____) async {
          aiCalled = true;
          return const AiDescriptionResult(
              description: 'AI', source: 'ai', upgrade: false);
        },
      );
      await _tapDescribe(tester);

      // Templated baseline: surface + shape + climb clause from the parts.
      expect(find.textContaining('River Loop is a'), findsOneWidget);
      expect(find.textContaining('trail'), findsOneWidget);
      // 90 m over 5 km = 18 m/km → "gently rolling".
      expect(find.textContaining('gently rolling'), findsOneWidget);
      // Free user sees the upsell, never the AI attribution, and the upsell
      // links to Pro rather than telling them to go and find it.
      expect(find.text('AI descriptions are a Pro feature.'),
          findsOneWidget);
      expect(find.text('See Pro'), findsOneWidget);
      expect(find.text("Written by AI from this route's stats"), findsNothing);
      expect(aiCalled, isFalse);
    });

    testWidgets('Pro replaces the baseline with the AI text + attribution',
        (tester) async {
      await _pump(
        tester,
        checkPro: () async => true,
        describeAi: (_, __, ___, ____) async => const AiDescriptionResult(
          description: 'A gorgeous riverside trail loop with a steady climb.',
          source: 'ai',
          upgrade: false,
        ),
      );
      await _tapDescribe(tester);

      expect(
        find.text('A gorgeous riverside trail loop with a steady climb.'),
        findsOneWidget,
      );
      expect(find.text("Written by AI from this route's stats"), findsOneWidget);
      // The upgrade hint is gone for a Pro user whose call returned upgrade:false.
      expect(find.text('AI descriptions are a Pro feature.'),
          findsNothing);
    });

    testWidgets("a server template keeps the viewer's localised sentence",
        (tester) async {
      // The endpoint's fallback is its English assembler, so taking it would
      // swap a French viewer's sentence for an English one.
      await _pump(
        tester,
        locale: const Locale('fr'),
        checkPro: () async => true,
        describeAi: (_, __, ___, ____) async => const AiDescriptionResult(
          description: 'River Loop is a 5.0 km trail point-to-point route.',
          source: 'template',
          upgrade: false,
        ),
      );
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
      await tester.tap(find.text('Décrire cet itinéraire'));
      await tester.pump();
      await tester.pump(Duration.zero);

      expect(
        find.textContaining(
            'River Loop est un itinéraire point à point sur sentier'),
        findsOneWidget,
      );
      expect(find.textContaining('River Loop is a'), findsNothing);
    });

    for (final unit in cm.DistanceUnit.values) {
      testWidgets("hands the viewer's unit (${unit.name}) to the AI call",
          (tester) async {
        final sent = <cm.DistanceUnit>[];
        await _pump(
          tester,
          checkPro: () async => true,
          useMiles: unit == cm.DistanceUnit.mi,
          describeAi: (_, u, __, ___) async {
            sent.add(u);
            return const AiDescriptionResult(
                description: 'A loop.', source: 'ai', upgrade: false);
          },
        );
        await _tapDescribe(tester);
        expect(sent, [unit]);
      });
    }

    for (final (shown, tag) in const [
      (Locale('en'), 'en'),
      (Locale('fr'), 'fr'),
      (Locale('ja'), 'ja'),
      (Locale('pt', 'BR'), 'pt-BR'),
    ]) {
      testWidgets("hands the app's resolved locale ($tag) to the AI call",
          (tester) async {
        final sent = <String>[];
        await _pump(
          tester,
          locale: shown,
          checkPro: () async => true,
          describeAi: (_, __, locale, ___) async {
            sent.add(locale);
            return const AiDescriptionResult(
                description: 'A loop.', source: 'ai', upgrade: false);
          },
        );
        await tester.drag(find.byType(ListView), const Offset(0, -600));
        await tester.pump();
        await tester
            .tap(find.text(lookupAppLocalizations(shown).routeDetailDescribe));
        await tester.pump();
        await tester.pump(Duration.zero);
        expect(sent, [tag]);
      });
    }

    testWidgets('AI failure keeps the templated baseline + shows the error',
        (tester) async {
      await _pump(
        tester,
        checkPro: () async => true,
        describeAi: (_, __, ___, ____) async => throw StateError('boom'),
      );
      await _tapDescribe(tester);

      // Baseline survives the failure.
      expect(find.textContaining('River Loop is a'), findsOneWidget);
      expect(find.text('Couldn\'t generate a description. Please try again.'),
          findsOneWidget);
      // No AI attribution since the model call failed.
      expect(find.text("Written by AI from this route's stats"), findsNothing);
    });

    testWidgets('a consent gap keeps the baseline and points at the '
        'disclosure, not a retry', (tester) async {
      // Issue #734: /api/coach/route-describe now refuses a caller who has
      // not accepted the widened AI disclosure. That is not a transient
      // failure, so "please try again" would be a lie — and the paywall
      // shares the same 403, so it must not read as an upsell either.
      await _pump(
        tester,
        checkPro: () async => true,
        describeAi: (_, __, ___, ____) async => throw StateError(kAiDisclosureError),
      );
      await _tapDescribe(tester);

      expect(find.textContaining('River Loop is a'), findsOneWidget);
      expect(
        find.text(
            'AI descriptions need your consent to the updated AI disclosure.'),
        findsOneWidget,
      );
      expect(find.text("Couldn't generate a description. Please try again."),
          findsNothing);
      expect(find.text('AI descriptions are a Pro feature.'),
          findsNothing);
    });
  });

  group('isAiDisclosureDenial', () {
    test('only a 403 whose body carries the code is a consent denial', () {
      const body = '{"code":"ai_disclosure_required","required_version":2}';
      expect(isAiDisclosureDenial(403, body), isTrue);
      // The paywall's own 403 must not be read as a consent gap.
      expect(isAiDisclosureDenial(403, '{"error":"upgrade required"}'), isFalse);
      expect(isAiDisclosureDenial(500, body), isFalse);
      expect(isAiDisclosureDenial(403, 'not json'), isFalse);
      expect(isAiDisclosureDenial(403, ''), isFalse);
      expect(isAiDisclosureDenial(403, '[]'), isFalse);
    });
  });

  test('the request body carries the unit the server writes the paragraph in',
      () {
    const input = RouteDescriptionInput(name: 'River Loop', distanceM: 5000);
    expect(routeDescribeBody(input, cm.DistanceUnit.mi, 'en', 'r1')['unit'], 'mi');
    expect(routeDescribeBody(input, cm.DistanceUnit.km, 'en', 'r1')['unit'], 'km');
  });

  test('the request body carries the locale the server writes the paragraph in',
      () {
    const input = RouteDescriptionInput(name: 'River Loop', distanceM: 5000);
    expect(routeDescribeBody(input, cm.DistanceUnit.km, 'pt-BR', 'r1')['locale'],
        'pt-BR');
  });

  test('the request body carries the route id the server scopes the name by',
      () {
    const input = RouteDescriptionInput(name: 'River Loop', distanceM: 5000);
    expect(
        routeDescribeBody(input, cm.DistanceUnit.km, 'en', 'r1')['route_id'],
        'r1');
  });

  testWidgets("hands the route's id to the AI call", (tester) async {
    final sent = <String>[];
    await _pump(
      tester,
      checkPro: () async => true,
      describeAi: (_, __, ___, routeId) async {
        sent.add(routeId);
        return const AiDescriptionResult(
            description: 'A loop.', source: 'ai', upgrade: false);
      },
    );
    await _tapDescribe(tester);
    expect(sent, ['r1']);
  });

  test('the locale tag is the canonical identifier web sends', () {
    expect(routeDescribeLocaleTag(const Locale('en')), 'en');
    expect(routeDescribeLocaleTag(const Locale('ja')), 'ja');
    expect(routeDescribeLocaleTag(const Locale('pt', 'BR')), 'pt-BR');
    expect(routeDescribeLocaleTag(const Locale('pt', 'PT')), 'pt-PT');
    // gen-l10n's bare base is the European catalogue.
    expect(routeDescribeLocaleTag(const Locale('pt')), 'pt-PT');
  });
}

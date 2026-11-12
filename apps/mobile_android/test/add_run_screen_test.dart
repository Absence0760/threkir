import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/local_run_store.dart';
import '../lib/local_route_store.dart';
import '../lib/preferences.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/add_run_screen.dart';
import 'pump_until.dart';

late Directory _runsDir;

class _FakeApi extends ApiClient {}

Future<({LocalRunStore runs, LocalRouteStore routes, Preferences prefs})>
    _makeStores() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();

  _runsDir = Directory.systemTemp.createTempSync('add_run_screen_test_');
  final runStore = LocalRunStore();
  await runStore.init(overrideDirectory: _runsDir);

  // LocalRouteStore has no overrideDirectory; construct without calling
  // init() so path_provider is never touched. routes getter returns []
  // by default, which is all AddRunScreen needs for the route-picker path.
  final routeStore = LocalRouteStore();

  return (runs: runStore, routes: routeStore, prefs: prefs);
}

Future<void> _pump(
  WidgetTester tester,
  LocalRunStore runStore,
  LocalRouteStore routeStore,
  Preferences prefs, {
  DateTime Function() now = DateTime.now,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AddRunScreen(
        runStore: runStore,
        routeStore: routeStore,
        preferences: prefs,
        now: now,
      ),
    ),
  );
}

void main() {
  tearDown(() {
    if (_runsDir.existsSync()) _runsDir.deleteSync(recursive: true);
  });

  group('AddRunScreen', () {
    testWidgets('renders When, Activity, and Distance section labels',
        (tester) async {
      final s = await _makeStores();
      await _pump(tester, s.runs, s.routes, s.prefs);
      await tester.pumpAndSettle();
      expect(find.text('When'), findsOneWidget);
      expect(find.text('Activity'), findsOneWidget);
      // The distance label appears in the Duration/Distance section.
      expect(find.text('Distance'), findsAtLeastNWidgets(1));
    });

    // a11y: the distance field carries only a separate section Text as
    // its visible label, which a screen reader won't associate with the
    // edit box. The Semantics wrap gives the field its own accessible
    // name (uxhunt-mobile finding #3).
    testWidgets('distance field exposes an accessible name for screen readers',
        (tester) async {
      final s = await _makeStores();
      await _pump(tester, s.runs, s.routes, s.prefs);
      await tester.pumpAndSettle();
      // Distance is the first TextFormField on the screen; how many of the
      // later ones the list has built by now is a layout accident.
      final node = tester.getSemantics(find.byType(TextFormField).first);
      expect(node.label, 'Distance');
    });

    testWidgets('each duration box is named, not just suffixed', (tester) async {
      // The visible 'h' / 'm' / 's' hints are `suffixText`, which Flutter does
      // NOT fold into a field's accessible name — so all three announced as a
      // bare "text field" and a screen-reader user could not tell which box
      // they were editing.
      final s = await _makeStores();
      await _pump(tester, s.runs, s.routes, s.prefs);
      await tester.pumpAndSettle();

      final labels = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where((w) => w.properties.textField == true)
          .map((w) => w.properties.label)
          .toSet();
      expect(labels.containsAll({'Hours', 'Minutes', 'Seconds'}), isTrue,
          reason: 'got: $labels');
    });

    testWidgets('Save action is present in the app bar', (tester) async {
      final s = await _makeStores();
      await _pump(tester, s.runs, s.routes, s.prefs);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('renders ChoiceChips for all four activity types',
        (tester) async {
      final s = await _makeStores();
      await _pump(tester, s.runs, s.routes, s.prefs);
      expect(find.text('Run'), findsOneWidget);
      expect(find.text('Walk'), findsOneWidget);
      expect(find.text('Cycle'), findsOneWidget);
      // Picker label rebrand: Hike → Trail run. Enum stays `hike`.
      expect(find.text('Trail run'), findsOneWidget);
    });

    testWidgets('tapping Save without values does not save a run', (tester) async {
      final s = await _makeStores();
      await _pump(tester, s.runs, s.routes, s.prefs);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      // Form validation blocks save — store remains empty.
      expect(s.runs.runs, isEmpty);
    });

    Finder durationBox(String label) => find.descendant(
          of: find.bySemanticsLabel(label),
          matching: find.byType(TextField),
        );

    // Reason: issue #1300 § 5 — "12333" in the Hours box saved a 2 km run
    // lasting 12,333 hours. The box now holds three digits (240 h is the whole
    // bound), and a total past ten days is refused with its own message.
    testWidgets('the hours box takes three digits and 240 h is the ceiling',
        (tester) async {
      final s = await _makeStores();
      await _pump(tester, s.runs, s.routes, s.prefs);

      await tester.enterText(find.byType(TextFormField).first, '2');
      await tester.enterText(durationBox('Hours'), '12333');
      await tester.pump();
      expect(
        tester.widget<TextField>(durationBox('Hours')).controller!.text,
        '123',
      );

      await tester.enterText(durationBox('Hours'), '240');
      await tester.enterText(durationBox('Minutes'), '1');
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(find.text("A run can't be longer than 240 hours"), findsOneWidget);
      expect(s.runs.runs, isEmpty);
    });

    testWidgets('minutes past 59 are refused rather than carried into hours',
        (tester) async {
      final s = await _makeStores();
      await _pump(tester, s.runs, s.routes, s.prefs);

      await tester.enterText(find.byType(TextFormField).first, '5');
      await tester.enterText(durationBox('Minutes'), '750');
      await tester.pump();
      expect(
        tester.widget<TextField>(durationBox('Minutes')).controller!.text,
        '75',
      );
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(find.text('Minutes must be between 0 and 59'), findsOneWidget);
      expect(s.runs.runs, isEmpty);
    });

    // Reason: 21 typed into Hours instead of Minutes is a valid duration, so
    // only its pace gives it away — 2 km in 21 h is under 0.1 km/h.
    testWidgets('a duration slower than 1 km/h asks before saving',
        (tester) async {
      final s = await _makeStores();
      await _pump(tester, s.runs, s.routes, s.prefs);

      await tester.enterText(find.byType(TextFormField).first, '2');
      await tester.enterText(durationBox('Hours'), '21');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Check the duration'), findsOneWidget);
      await tester.tap(find.text('Fix it'));
      await tester.pumpAndSettle();
      expect(find.text('Check the duration'), findsNothing);
      expect(s.runs.runs, isEmpty);
    });

    // Reason: the date picker stops at today, but the time picker let a run
    // start at 22:00 when it was 10:26 (issue #1300 § 5).
    testWidgets('a start time later today than now is refused', (tester) async {
      final s = await _makeStores();
      final now = DateTime(2026, 11, 5, 10, 26);
      await _pump(tester, s.runs, s.routes, s.prefs, now: () => now);

      await tester.tap(find.text('10:00'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), '10');
      await tester.enterText(fields.at(1), '00');
      await tester.pumpAndSettle();
      final pm = find.text('PM');
      if (pm.evaluate().isNotEmpty) await tester.tap(pm);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pump();

      expect(find.text("The start time can't be in the future"), findsOneWidget);
      expect(find.text('10:00'), findsOneWidget);
      await tester.pump(const Duration(seconds: 8));
    });

    // Reason: five of the seven shipped locales (de, es, fr, pt, pt_BR) put a
    // comma on the decimal key, and the distance field used to filter it out
    // — so a German runner's "5,2" reached the parser as "52" and a 5.2 km
    // run was stored as 52 km, silently and with nothing to notice.
    testWidgets('a comma decimal saves the distance the runner typed',
        (tester) async {
      final s = await _makeStores();
      await _pump(tester, s.runs, s.routes, s.prefs);

      await tester.enterText(find.byType(TextFormField).first, '5,2');
      await tester.enterText(
        find.descendant(
          of: find.bySemanticsLabel('Minutes'),
          matching: find.byType(TextField),
        ),
        '30',
      );
      await tester.pump();

      // runStore.save encodes the track off-isolate and writes a real file,
      // neither of which the fake-async clock advances — so the tap has to run
      // on the real event loop, and the wait is for the store's own
      // notification, which lands after the write and the index flush.
      var saved = false;
      s.runs.addListener(() => saved = true);
      await tester.runAsync(() => tester.tap(find.text('Save')));
      await pumpUntil(tester, () => saved,
          describe: "the run's file + index to land on disk");

      expect(s.runs.runs.single.distanceMetres, closeTo(5200, 0.01));
    });

    // Reason: the route-picker section was previously gated on
    // `routes.isNotEmpty`, so a user with zero saved routes saw no
    // indication that route-attachment exists. Field report: "I
    // don't see the attach route, for adding a new run." The fix
    // always renders the section header + an empty-state hint when
    // there are no routes yet. Pinning both halves of the contract.
    testWidgets('Route (optional) section renders even when routeStore is empty',
        (tester) async {
      final s = await _makeStores();
      // s.routes is a freshly-constructed LocalRouteStore — routes is empty.
      expect(s.routes.routes, isEmpty);
      await _pump(tester, s.runs, s.routes, s.prefs);
      await tester.pumpAndSettle();

      expect(find.text('Route (optional)'), findsOneWidget,
          reason: 'Route section header must show so the affordance is '
              'discoverable before the user has built or imported any routes.');
      expect(
        find.text('No saved routes yet — build or import one to attach it here'),
        findsOneWidget,
        reason: 'Empty-state hint must render in place of the picker so '
            'users learn the feature exists.',
      );
    });

    // Positive-shape pin for the route-picker section: when the user
    // has saved routes, the empty-state hint goes away and the search
    // input appears. Pairs with the empty-state test above so a
    // refactor that swaps the two branches fails on the visible copy.
    testWidgets(
        'Route (optional) section renders the picker when routeStore has routes',
        (tester) async {
      final s = await _makeStores();
      s.routes.debugSeed([
        cm.Route(
          id: 'r-1',
          userId: 'test-user',
          name: 'River loop',
          waypoints: const [
            cm.Waypoint(lat: 47.37, lng: 8.54),
            cm.Waypoint(lat: 47.371, lng: 8.541),
          ],
          distanceMetres: 5000,
        ),
      ]);
      await _pump(tester, s.runs, s.routes, s.prefs);
      await tester.pumpAndSettle();

      expect(find.text('Route (optional)'), findsOneWidget);
      expect(find.text('Search saved routes'), findsOneWidget,
          reason: 'Picker placeholder must surface when routes are '
              'available so the user can drill in to select one.');
      // The empty-state hint must NOT appear in this branch.
      expect(
        find.text(
            'No saved routes yet — build or import one to attach it here'),
        findsNothing,
        reason: 'Empty hint must be hidden once routes exist.',
      );
    });

    // Picker opens to a real list of routes. Drives one keystroke
    // through the search bar, verifies filtering, then taps a row to
    // round-trip a selection. The InputDecorator in AddRunScreen then
    // shows the picked route name + formatted distance, and the
    // search icon flips to a Clear (X) IconButton. Tap that to remove
    // the selection — the picker goes back to the search prompt.
    testWidgets('picker open → filter → select → clear round trip',
        (tester) async {
      final s = await _makeStores();
      s.routes.debugSeed([
        cm.Route(
          id: 'r-park',
          userId: 'test-user',
          name: 'Park loop',
          waypoints: const [
            cm.Waypoint(lat: 47.37, lng: 8.54),
            cm.Waypoint(lat: 47.371, lng: 8.541),
          ],
          distanceMetres: 4200,
        ),
        cm.Route(
          id: 'r-river',
          userId: 'test-user',
          name: 'River out-and-back',
          waypoints: const [
            cm.Waypoint(lat: 47.37, lng: 8.54),
            cm.Waypoint(lat: 47.378, lng: 8.55),
          ],
          distanceMetres: 8000,
        ),
      ]);
      await _pump(tester, s.runs, s.routes, s.prefs);
      await tester.pumpAndSettle();

      // Open the picker — tap the InputDecorator with the search prompt.
      await tester.tap(find.text('Search saved routes'));
      await tester.pumpAndSettle();

      // Both rows visible in the picker.
      expect(find.text('Park loop'), findsOneWidget);
      expect(find.text('River out-and-back'), findsOneWidget);

      // Filter to a single match.
      await tester.enterText(find.byType(TextField).first, 'river');
      await tester.pumpAndSettle();
      expect(find.text('River out-and-back'), findsOneWidget);
      expect(find.text('Park loop'), findsNothing);

      // Tap the surviving row → selection lands + picker pops.
      await tester.tap(find.text('River out-and-back'));
      await tester.pumpAndSettle();

      // Back on AddRunScreen: the InputDecorator now shows the route
      // name (the formatted distance follows the bullet separator).
      expect(find.textContaining('River out-and-back'), findsOneWidget);
      // Clear icon replaces the search icon when a route is selected.
      expect(find.byIcon(Icons.clear), findsOneWidget);
      expect(find.byIcon(Icons.search), findsNothing,
          reason: 'Search icon must flip to Clear once a route is picked.');

      // Tap Clear → selection cleared, search icon returns.
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();
      expect(find.text('Search saved routes'), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
    });
  });

  group('AddRunScreen — discard guard', () {
    // Pushes the screen over a root route so a guarded pop can be observed
    // returning to the root.
    Future<void> pushScreen(
      WidgetTester tester,
      LocalRunStore runStore,
      LocalRouteStore routeStore,
      Preferences prefs,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AddRunScreen(
                        runStore: runStore,
                        routeStore: routeStore,
                        preferences: prefs,
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'edited field: back shows the discard confirm; Cancel keeps the input',
        (tester) async {
      final s = await _makeStores();
      await pushScreen(tester, s.runs, s.routes, s.prefs);

      await tester.enterText(find.byType(TextFormField).first, '5.0');
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(AddRunScreen), findsOneWidget);
      expect(find.text('5.0'), findsOneWidget);
    });

    testWidgets('edited field: Discard pops without saving', (tester) async {
      final s = await _makeStores();
      await pushScreen(tester, s.runs, s.routes, s.prefs);

      await tester.enterText(find.byType(TextFormField).first, '5.0');
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Discard')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.byType(AddRunScreen), findsNothing);
      expect(find.text('open'), findsOneWidget);
      expect(s.runs.runs, isEmpty);
    });

    testWidgets('untouched form: back pops with no confirm', (tester) async {
      final s = await _makeStores();
      await pushScreen(tester, s.runs, s.routes, s.prefs);

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(AddRunScreen), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });
  });

  // Issue #1300 § 3: with no saved routes the field was a bare InputDecorator
  // with no tap handler, so "build or import one" pointed at nothing.
  group('empty route field builds or imports a route', () {
    const pickerChannel =
        MethodChannel('miguelruivo.flutter.plugins.filepicker');
    tearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pickerChannel, null));

    final built = cm.Route(
      id: 'built-1',
      userId: 'test-user',
      name: 'Harbour loop',
      waypoints: const [
        cm.Waypoint(lat: 47.37, lng: 8.54),
        cm.Waypoint(lat: 47.371, lng: 8.541),
      ],
      distanceMetres: 7250,
    );

    Future<void> pumpEmpty(
      WidgetTester tester,
      ({LocalRunStore runs, LocalRouteStore routes, Preferences prefs}) s, {
      ApiClient? api,
      Future<cm.Route?> Function(BuildContext)? openRouteBuilder,
    }) async {
      // Tall enough that the lazily built ListView reaches the title field.
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AddRunScreen(
          runStore: s.runs,
          routeStore: s.routes,
          preferences: s.prefs,
          apiClient: api,
          openRouteBuilder: openRouteBuilder,
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('tapping it offers Build a route and Import a file',
        (tester) async {
      final s = await _makeStores();
      await pumpEmpty(tester, s, api: _FakeApi());

      await tester.tap(find.byKey(const Key('add_run_add_route')));
      await tester.pumpAndSettle();

      expect(find.text('Build a route'), findsOneWidget);
      expect(find.text('Import a file'), findsOneWidget);
    });

    testWidgets('signed out, the sheet offers only Import', (tester) async {
      final s = await _makeStores();
      await pumpEmpty(tester, s);

      await tester.tap(find.byKey(const Key('add_run_add_route')));
      await tester.pumpAndSettle();

      expect(find.text('Build a route'), findsNothing,
          reason: 'the route builder needs a signed-in ApiClient');
      expect(find.text('Import a file'), findsOneWidget);
    });

    testWidgets('a route saved in the builder comes back selected',
        (tester) async {
      final s = await _makeStores();
      var opened = 0;
      // The real builder saves the route to the store before popping it.
      await pumpEmpty(tester, s, api: _FakeApi(), openRouteBuilder: (_) async {
        opened++;
        s.routes.debugSeed([built]);
        return built;
      });

      await tester.tap(find.byKey(const Key('add_run_add_route')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Build a route'));
      await tester.pumpAndSettle();

      expect(opened, 1);
      expect(find.text('Harbour loop • 7.25 km'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '7.25'), findsOneWidget,
          reason: 'selecting the route fills the distance');
      expect(find.widgetWithText(TextFormField, 'Harbour loop'), findsOneWidget,
          reason: 'and the empty title');
    });

    testWidgets('leaving the builder without saving leaves the field empty',
        (tester) async {
      final s = await _makeStores();
      await pumpEmpty(tester, s,
          api: _FakeApi(), openRouteBuilder: (_) async => null);

      await tester.tap(find.byKey(const Key('add_run_add_route')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Build a route'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add_run_add_route')), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '7.25'), findsNothing);
    });

    testWidgets('a file holding one route is imported and selected',
        (tester) async {
      final s = await _makeStores();
      final dir = Directory.systemTemp.createTempSync('add_run_import_');
      addTearDown(() => dir.deleteSync(recursive: true));
      await tester.runAsync(
          () => s.routes.init(overrideDirectory: Directory('${dir.path}/store')
            ..createSync()));
      final file = File('${dir.path}/canal.gpx')
        ..writeAsStringSync('<?xml version="1.0"?>'
            '<gpx version="1.1" creator="t"><trk><name>Canal path</name>'
            '<trkseg>'
            '<trkpt lat="51.5" lon="-0.12"></trkpt>'
            '<trkpt lat="51.51" lon="-0.12"></trkpt>'
            '</trkseg></trk></gpx>');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pickerChannel, (_) async => [
                {
                  'name': 'canal.gpx',
                  'path': file.path,
                  'size': file.lengthSync(),
                },
              ]);
      await pumpEmpty(tester, s);

      await tester.tap(find.byKey(const Key('add_run_add_route')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import a file'));
      await pumpUntil(
          tester,
          () => find.textContaining('Canal path •').evaluate().isNotEmpty,
          describe: 'the imported route to be selected');

      expect(s.routes.routes.map((r) => r.name), ['Canal path']);
      expect(find.widgetWithText(TextFormField, 'Canal path'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });
  });
}

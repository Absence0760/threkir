import 'dart:typed_data';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/widgets/head_to_head_card.dart';
import '../lib/widgets/run_share_card.dart';

import 'pump_until.dart';

Map<String, dynamic> _row(String id, String? handle, String name, num mine,
        num theirs) =>
    {
      'friend_id': id,
      'friend_display_name': name,
      'friend_handle': handle,
      'friend_avatar_url': null,
      'target_name': 'River Loop',
      'my_run_id': 'r1',
      'my_seconds': mine,
      'friend_run_id': 'r-$id',
      'friend_seconds': theirs,
    };

Widget _app(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

Future<void> _pumpPanel(
  WidgetTester tester,
  HeadToHeadLoader load, {
  RunShareImageSaver? save,
}) async {
  tester.view.physicalSize = const Size(1200, 3300);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(HeadToHeadPanel(
    load: load,
    fileName: 'h2h-test',
    saveImage: save ?? (_, __) async {},
  )));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('lists the friends the read returns and draws the first',
      (tester) async {
    await _pumpPanel(
        tester,
        () async => [
              _row('f1', 'sam', 'Sam', 1900, 1950),
              _row('f2', null, 'Jo Bloggs', 2000, 1800),
            ]);
    expect(find.text('@sam'), findsWidgets);
    expect(find.text('Jo Bloggs'), findsOneWidget);
    expect(find.text('RIVER LOOP'), findsNothing);
    expect(find.text('River Loop'), findsOneWidget);
    expect(find.text('31:40'), findsOneWidget);
    expect(find.text('32:30'), findsOneWidget);
    expect(find.text('I won by 0:50'), findsOneWidget);
    expect(find.text('HEAD TO HEAD'), findsOneWidget);
  });

  testWidgets('picking another friend redraws the card for them',
      (tester) async {
    await _pumpPanel(
        tester,
        () async => [
              _row('f1', 'sam', 'Sam', 1900, 1950),
              _row('f2', null, 'Jo Bloggs', 2000, 1800),
            ]);
    await tester.tap(find.text('Jo Bloggs'));
    await tester.pump();
    expect(find.text('Jo Bloggs won by 3:20'), findsOneWidget);
    expect(find.text('30:00'), findsOneWidget);
  });

  testWidgets('equal times read as a dead heat', (tester) async {
    await _pumpPanel(
        tester, () async => [_row('f1', 'sam', 'Sam', 1900, 1900.2)]);
    expect(find.text('Dead heat'), findsOneWidget);
  });

  testWidgets('nobody to compare with says what a comparison needs',
      (tester) async {
    await _pumpPanel(tester, () async => const []);
    expect(find.byKey(const Key('head-to-head-empty')), findsOneWidget);
    expect(find.text('Image'), findsNothing);
  });

  testWidgets('a failed read is an error with a retry, not the empty state',
      (tester) async {
    var calls = 0;
    await _pumpPanel(tester, () async {
      calls++;
      if (calls == 1) throw Exception('boom');
      return [_row('f1', 'sam', 'Sam', 1900, 1950)];
    });
    expect(find.text("Couldn't load the comparison."), findsOneWidget);
    expect(find.byKey(const Key('head-to-head-empty')), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(calls, 2);
    expect(find.text('I won by 0:50'), findsOneWidget);
  });

  testWidgets('Save hands the saver a PNG of the card', (tester) async {
    Uint8List? saved;
    await _pumpPanel(
      tester,
      () async => [_row('f1', 'sam', 'Sam', 1900, 1950)],
      save: (png, name) async => saved = png,
    );
    await tester.ensureVisible(find.text('Save to Photos'));
    await tester.runAsync(() => tester.tap(find.text('Save to Photos')));
    await pumpUntil(
      tester,
      () => find.text('Saved to your photos').evaluate().isNotEmpty,
      describe: 'the saved banner',
    );
    expect(saved!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    await tester.pump(const Duration(seconds: 5));
  });

  group('run share sheet', () {
    Future<void> openSheet(WidgetTester tester,
        {String? routeId, HeadToHeadLoader? load}) async {
      tester.view.physicalSize = const Size(1200, 3300);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();
      final run = Run(
        id: 'r1',
        startedAt: DateTime.utc(2026, 4, 15, 8),
        duration: const Duration(minutes: 31, seconds: 40),
        distanceMetres: 5000,
        source: RunSource.app,
        routeId: routeId,
        metadata: const {'title': 'Loop', 'activity_type': 'run'},
      );
      await tester.pumpWidget(_app(Builder(
        builder: (context) => TextButton(
          onPressed: () => showRunShareSheet(
            context,
            run: run,
            preferences: prefs,
            title: 'Loop',
            privacyZones: const [],
            saveImageOverride: (_, __) async {},
            headToHeadLoadOverride: load,
          ),
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('offers Versus and shows the card in the sheet',
        (tester) async {
      await openSheet(tester,
          routeId: 'route-1',
          load: () async => [_row('f1', 'sam', 'Sam', 1900, 1950)]);
      await tester.tap(find.text('Versus'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(HeadToHeadPanel), findsOneWidget);
      expect(find.text('I won by 0:50'), findsOneWidget);
      expect(find.text('Image'), findsOneWidget,
          reason: 'the panel brings one set of export buttons, not two');
    });

    testWidgets('a sheet with no comparison to load offers no Versus',
        (tester) async {
      await openSheet(tester);
      expect(find.text('Versus'), findsNothing);
    });
  });
}

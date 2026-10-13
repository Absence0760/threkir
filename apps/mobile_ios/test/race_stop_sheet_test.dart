import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/help_guides.dart';
import '../lib/help_loader.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/help_screen.dart';
import '../lib/widgets/race_stop_sheet.dart';

Future<Future<void> Function()> _open(
  WidgetTester tester, {
  required bool coverageMet,
  required void Function(RaceStopChoice?) onChoice,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => onChoice(
              await showRaceStopSheet(context, coverageMet: coverageMet),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  return () async {
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  };
}

void main() {
  testWidgets('with the course covered it offers Resume race and Finish race', (
    tester,
  ) async {
    RaceStopChoice? choice;
    final open = await _open(
      tester,
      coverageMet: true,
      onChoice: (c) => choice = c,
    );
    await open();

    expect(find.text('Race paused'), findsOneWidget);
    expect(find.text('Resume race'), findsOneWidget);
    expect(find.text('Finish race'), findsOneWidget);
    expect(find.textContaining('less than 90%'), findsNothing);

    await tester.tap(find.byKey(const Key('race-stop-finish')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(choice, RaceStopChoice.finish);
  });

  testWidgets('under 90% covered it says finishing now is a DNF', (
    tester,
  ) async {
    RaceStopChoice? choice;
    final open = await _open(
      tester,
      coverageMet: false,
      onChoice: (c) => choice = c,
    );
    await open();

    expect(find.textContaining('less than 90%'), findsOneWidget);
    expect(find.text('Finish as DNF'), findsOneWidget);
    expect(find.text('Finish race'), findsNothing);

    await tester.tap(find.byKey(const Key('race-stop-resume')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(choice, RaceStopChoice.resume);
  });

  testWidgets('How this works opens the participant guide for the event', (
    tester,
  ) async {
    final library = HelpLibrary.parse(
      File('test/fixtures/help_guides.json').readAsStringSync(),
    )!;
    helpLibraryLoader = () => Future.value(library);
    addTearDown(() => helpLibraryLoader = loadHelpLibraryCached);
    final open = await _open(tester, coverageMet: true, onChoice: (_) {});
    await open();

    await tester.tap(find.byKey(const Key('race-stop-help')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.byType(HelpForRouteScreen), findsOneWidget);
    // The organiser's paid-class guide shares the event route; a runner
    // mid-race gets only the guide written for participants.
    expect(find.text('Racing an event'), findsOneWidget);
    expect(find.text('Charging for a class'), findsNothing);
  });
}

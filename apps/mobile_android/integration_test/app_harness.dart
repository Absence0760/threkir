import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/main.dart' as app;

/// Launch the app through its real `main()`, the entry point the OS runs,
/// with the device-scoped `onboarded` flag set first.
///
/// The flag lives in the platform's real SharedPreferences store and survives
/// a reinstall of a debug build on the same simulator or emulator, so a
/// suite that did not set it would start on whichever screen the previous
/// run left behind.
Future<void> launchApp({required bool onboarded}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('onboarded', onboarded);
  app.main();
}

/// Pump real frames until [finder] matches, failing with [describe] at
/// [timeout].
///
/// On a device the clock is real, so a cold launch takes as long as plugin
/// start-up takes. `pumpAndSettle` is the wrong wait here: the dashboard and
/// the map run animations that never settle, and it would time out on a
/// screen that had in fact arrived.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  required String describe,
  Duration timeout = const Duration(seconds: 90),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (!DateTime.now().isBefore(deadline)) {
      fail('timed out after ${timeout.inSeconds} s waiting for $describe');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The catalogue the running app resolved for this device's locale, read off
/// a mounted [element] so assertions hold in every shipped language.
AppLocalizations l10nOf(WidgetTester tester, Finder element) =>
    AppLocalizations.of(tester.element(element.first));

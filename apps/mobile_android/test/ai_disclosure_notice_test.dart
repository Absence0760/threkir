// Widget tests for AiDisclosureNotice, the one copy of the AI-processing
// disclosure every host shows (Coach gate, You → Account, route
// fallback). It must name every lane the current disclosure version covers:
// a bullet in the catalogue the notice leaves out is processing a runner
// would accept without having been told about.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/ai_disclosure.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/l10n/gen/app_localizations_en.dart';
import '../lib/widgets/ai_disclosure_notice.dart';

final _l10n = AppLocalizationsEn();

Future<void> _mount(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(420, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: AiDisclosureNotice())),
    ),
  );
}

void main() {
  testWidgets('renders the intro, the processing terms and the privacy pointer',
      (tester) async {
    await _mount(tester);
    expect(find.text(_l10n.coachConsentIntro), findsOneWidget);
    expect(find.text(_l10n.coachConsentProcessing), findsOneWidget);
    expect(_l10n.coachConsentIntro, contains('Anthropic'));
    expect(_l10n.coachConsentProcessing, contains('privacy policy'));
    expect(
      _l10n.coachConsentProcessing,
      contains('on your ${_l10n.settingsAccountTitle} page'),
    );
  });

  // Where consent is withdrawn is part of the consent text, so in every
  // locale it names the page by its title, Account. It names the page, not a
  // path to it: a path drifts whenever navigation moves (decisions § 2496).
  test('every locale names the Account page as where to withdraw', () {
    final dir = Directory('lib/l10n');
    final arbs = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.arb'))
        .toList();
    expect(arbs, isNotEmpty);
    for (final f in arbs) {
      final arb = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final text = arb['coachConsentProcessing'] as String;
      expect(text, contains(arb['settingsAccountTitle'] as String),
          reason: f.path);
      expect(text, isNot(contains('→')), reason: f.path);
    }
  });

  testWidgets('shows every coachConsentBullet* the English catalogue holds',
      (tester) async {
    await _mount(tester);
    final arb = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
        as Map<String, dynamic>;
    final bullets = {
      for (final e in arb.entries)
        if (e.key.startsWith('coachConsentBullet')) e.key: e.value as String,
    };
    expect(bullets, isNotEmpty);
    for (final MapEntry(:key, :value) in bullets.entries) {
      expect(find.text('• $value'), findsOneWidget, reason: key);
    }
    expect(
      find.textContaining(RegExp(r'^• ')),
      findsNWidgets(bullets.length),
    );
  });

  testWidgets(
      'names the lane the current version added (v$kAiDisclosureCurrentVersion, '
      'the coach assistant)', (tester) async {
    expect(kAiDisclosureCurrentVersion, kAiDisclosureVersionCoachAssist);
    await _mount(tester);
    expect(find.text('• ${_l10n.coachConsentBulletCoachAssist}'),
        findsOneWidget);
    expect(find.text('• ${_l10n.coachConsentBulletPlatePhoto}'),
        findsOneWidget);
    expect(find.text('• ${_l10n.coachConsentBulletPlanEdit}'), findsOneWidget);
  });
}

import 'package:api_client/api_client.dart'
    show UltraSignUpCandidate, UltraSignUpPersonLink, UltraSignUpRecentEvent;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/race_service.dart';
import '../lib/widgets/ultrasignup_link.dart';
import '../lib/widgets/undo_bar.dart';

/// Settings → Integrations → "Find your UltraSignup profile" (decisions
/// § 1841): look a name up, pick yourself, unlink. Mirrors web's
/// `UltraSignUpLinkPanel.svelte`; the service below stands in for the four
/// wire calls, which `packages/api_client/test/ultrasignup_person_test.dart`
/// pins at the http boundary.
class _LinkService extends RaceService {
  UltraSignUpPersonLink? link;
  List<UltraSignUpCandidate> candidates;
  bool failLookup;
  bool failLink;
  final List<String> lookups = [];
  final List<UltraSignUpPersonLink> linked = [];
  int unlinks = 0;

  _LinkService({
    this.link,
    this.candidates = const [],
    this.failLookup = false,
    this.failLink = false,
  });

  @override
  Future<UltraSignUpPersonLink?> fetchUltraSignUpLink() async => link;

  @override
  Future<List<UltraSignUpCandidate>> lookupUltraSignUpPeople(
      String firstName, String lastName) async {
    lookups.add('$firstName|$lastName');
    if (failLookup) throw const UltraSignUpUnavailable();
    return candidates;
  }

  @override
  Future<void> linkUltraSignUpPerson(UltraSignUpPersonLink next) async {
    if (failLink) throw StateError('write refused');
    linked.add(next);
    link = next;
  }

  @override
  Future<void> unlinkUltraSignUpPerson() async {
    unlinks++;
    link = null;
  }
}

const _ada = UltraSignUpPersonLink(
    personId: '12345', firstName: 'Ada', lastName: 'Lovelace');

const _candidates = [
  UltraSignUpCandidate(
    id: '12345',
    firstName: 'Ada',
    lastName: 'Lovelace',
    age: 36,
    resultCount: 4,
    recentEvents: [
      UltraSignUpRecentEvent(name: 'Bear 100', date: '2026-09-26'),
      UltraSignUpRecentEvent(name: 'Wasatch'),
    ],
  ),
  UltraSignUpCandidate(
    id: '777',
    firstName: 'Ada',
    lastName: 'Lovelace',
    age: null,
    resultCount: 1,
    recentEvents: [],
  ),
];

Widget _host(RaceService service) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: UltraSignUpLinkTile(service: service)),
    );

Future<AppLocalizations> _l10n() =>
    AppLocalizations.delegate.load(const Locale('en'));

/// Pump the tile, open the finder, and type a name.
Future<void> _openAndType(WidgetTester tester, RaceService service,
    {String first = 'Ada', String last = 'Lovelace'}) async {
  final l = await _l10n();
  await tester.pumpWidget(_host(service));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('ultrasignup-link-tile')));
  await tester.pumpAndSettle();
  await tester.enterText(
      find.widgetWithText(TextField, l.integrationsUltrasignupFirstName), first);
  await tester.enterText(
      find.widgetWithText(TextField, l.integrationsUltrasignupLastName), last);
  await tester.pump();
}

Finder _findButton(AppLocalizations l) =>
    find.widgetWithText(FilledButton, l.integrationsUltrasignupFind);

void main() {
  tearDown(debugResetUndo);

  testWidgets('the tile says who the runner is linked as', (tester) async {
    final l = await _l10n();
    await tester.pumpWidget(_host(_LinkService(link: _ada)));
    await tester.pumpAndSettle();
    expect(find.text(l.integrationsUltrasignupLinkedAs('Ada Lovelace', '12345')),
        findsOneWidget);
    expect(find.text(l.integrationsUltrasignupFindLabel), findsNothing);
  });

  testWidgets('unlinked, the tile offers the finder', (tester) async {
    final l = await _l10n();
    await tester.pumpWidget(_host(_LinkService()));
    await tester.pumpAndSettle();
    expect(find.text(l.integrationsUltrasignupFindLabel), findsOneWidget);
  });

  testWidgets('Find me waits for both halves of the name', (tester) async {
    final l = await _l10n();
    final service = _LinkService();
    await _openAndType(tester, service, last: '  ');
    expect(tester.widget<FilledButton>(_findButton(l)).onPressed, isNull);
    await tester.enterText(
        find.widgetWithText(TextField, l.integrationsUltrasignupLastName),
        'Lovelace');
    await tester.pump();
    expect(tester.widget<FilledButton>(_findButton(l)).onPressed, isNotNull);
    expect(service.lookups, isEmpty);
  });

  testWidgets('a search lists every same-named person, with what tells them apart',
      (tester) async {
    final l = await _l10n();
    final service = _LinkService(candidates: _candidates);
    await _openAndType(tester, service);
    await tester.tap(_findButton(l));
    await tester.pumpAndSettle();

    expect(service.lookups, ['Ada|Lovelace']);
    expect(find.text(l.integrationsUltrasignupPickPrompt), findsOneWidget);
    expect(find.byKey(const Key('ultrasignup-candidate-12345')), findsOneWidget);
    expect(find.byKey(const Key('ultrasignup-candidate-777')), findsOneWidget);
    expect(find.text('Age 36 · 4 results'), findsOneWidget);
    expect(find.text('1 result'), findsOneWidget,
        reason: 'an unknown age is left out, not shown as 0');
    expect(find.text('Bear 100 (2026) · Wasatch'), findsOneWidget);
  });

  testWidgets('picking a person links them and the tile follows', (tester) async {
    final l = await _l10n();
    final service = _LinkService(candidates: _candidates);
    await _openAndType(tester, service);
    await tester.tap(_findButton(l));
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
      of: find.byKey(const Key('ultrasignup-candidate-12345')),
      matching: find.widgetWithText(OutlinedButton, l.integrationsUltrasignupThisIsMe),
    ));
    await tester.pumpAndSettle();

    expect(service.linked, [_ada]);
    expect(find.byKey(const Key('ultrasignup-linked-as')), findsOneWidget);
    expect(find.text(l.integrationsUltrasignupLinked), findsOneWidget);

    Navigator.of(tester.element(find.byType(UltraSignUpLinkPanel))).pop();
    await tester.pumpAndSettle();
    expect(find.text(l.integrationsUltrasignupLinkedAs('Ada Lovelace', '12345')),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a name nobody answers to is said, not left blank', (tester) async {
    final l = await _l10n();
    await _openAndType(tester, _LinkService());
    await tester.tap(_findButton(l));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ultrasignup-no-matches')), findsOneWidget);
    expect(find.text(l.integrationsUltrasignupPickPrompt), findsNothing);
  });

  testWidgets('a failed lookup is a banner, not an empty result', (tester) async {
    final l = await _l10n();
    await _openAndType(tester, _LinkService(failLookup: true));
    await tester.tap(_findButton(l));
    await tester.pump();
    await tester.pump();
    expect(find.text(l.integrationsUltrasignupLookupFailed), findsOneWidget);
    expect(find.byKey(const Key('ultrasignup-no-matches')), findsNothing,
        reason: '"we could not ask" must not read as "nobody has that name"');
    expect(tester.widget<FilledButton>(_findButton(l)).onPressed, isNotNull,
        reason: 'the runner can try again');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a failed link leaves the runner unlinked and says so',
      (tester) async {
    final l = await _l10n();
    final service = _LinkService(candidates: _candidates, failLink: true);
    await _openAndType(tester, service);
    await tester.tap(_findButton(l));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byKey(const Key('ultrasignup-candidate-12345')),
      matching: find.widgetWithText(OutlinedButton, l.integrationsUltrasignupThisIsMe),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text(l.integrationsUltrasignupLinkFailed), findsOneWidget);
    expect(find.byKey(const Key('ultrasignup-linked-as')), findsNothing);
    expect(find.byKey(const Key('ultrasignup-candidate-12345')), findsOneWidget,
        reason: 'the candidates stay so the pick can be retried');
    await tester.pump(const Duration(seconds: 3));
  });

  group('unlink offers undo instead of a confirm', () {
    Future<void> openLinked(WidgetTester tester, _LinkService service) async {
      await tester.pumpWidget(_host(service));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ultrasignup-link-tile')));
      await tester.pumpAndSettle();
    }

    testWidgets('the link goes at once and the delete is held', (tester) async {
      final l = await _l10n();
      final service = _LinkService(link: _ada);
      await openLinked(tester, service);

      await tester.tap(
          find.widgetWithText(OutlinedButton, l.integrationsUltrasignupUnlink));
      await tester.pump();

      expect(find.byType(AlertDialog), findsNothing,
          reason: 'confirm and undo are alternatives, not partners');
      expect(find.byKey(const Key('ultrasignup-linked-as')), findsNothing);
      expect(find.text(l.integrationsUltrasignupFindLabel), findsWidgets);
      expect(find.text(l.integrationsUltrasignupUnlinked), findsOneWidget);
      expect(service.unlinks, 0);

      await tester.pump(const Duration(seconds: 9));
      expect(service.unlinks, 1);
    });

    testWidgets('Undo puts the same person back and deletes nothing',
        (tester) async {
      final l = await _l10n();
      final service = _LinkService(link: _ada);
      await openLinked(tester, service);

      await tester.tap(
          find.widgetWithText(OutlinedButton, l.integrationsUltrasignupUnlink));
      await tester.pump();
      await tester.tap(find.text('Undo'));
      await tester.pump();

      expect(find.byKey(const Key('ultrasignup-linked-as')), findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
      expect(service.unlinks, 0);
    });
  });
}

// "Who can see this" on the phone (decisions § R8SHARE-1): the four levels,
// named people, revoke, and the two exits the caller acts on.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/audience_level.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/audience_sheet.dart';

class _FakeBackend implements AudienceBackend {
  AudienceColumns? columns;
  List<AudiencePerson> shares;
  List<AudiencePerson> people;
  bool failSetLevel = false;
  bool failColumns = false;
  final List<String> calls = [];

  _FakeBackend({
    this.columns = const AudienceColumns(isPublic: false, followersOnly: false),
    this.shares = const [],
    this.people = const [],
  });

  @override
  Future<AudienceColumns?> fetchColumns() async {
    if (failColumns) throw Exception('down');
    return columns;
  }

  @override
  Future<List<AudiencePerson>> fetchShares() async => shares;

  @override
  Future<List<AudiencePerson>> fetchCandidates() async => people;

  @override
  Future<void> setLevel(AudienceLevel level) async {
    calls.add('setLevel:${level.name}');
    if (failSetLevel) throw Exception('refused');
    columns = audienceColumns(level);
    if (levelRevokesGrants(level)) shares = const [];
  }

  @override
  Future<void> addShare(String recipientId) async {
    calls.add('add:$recipientId');
  }

  @override
  Future<void> revokeShare(String recipientId) async {
    calls.add('revoke:$recipientId');
  }
}

const _morgan = AudiencePerson(id: 'u-morgan', displayName: 'Morgan Lee');
const _alex = AudiencePerson(id: 'u-alex', displayName: 'Alex Chen');

AudienceSheetResult? _result;

Future<void> _open(WidgetTester tester, AudienceBackend backend) async {
  _result = null;
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                _result = await showAudienceSheet(context, backend: backend);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await _tap(tester, find.text('open'));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

bool _selected(WidgetTester tester, AudienceLevel level) => tester
    .widget<ListTile>(find.byKey(ValueKey('audience-level-${level.name}')))
    .selected;

void main() {
  testWidgets('a private run with no grants reads as Only me', (tester) async {
    await _open(tester, _FakeBackend(people: const [_morgan]));
    expect(_selected(tester, AudienceLevel.private), isTrue);
    expect(find.text('Not shared with anyone yet.'), findsOneWidget);
    expect(find.byKey(const ValueKey('audience-share-link')), findsNothing);
  });

  testWidgets('choosing Followers stores it and offers the in-app link', (
    tester,
  ) async {
    final backend = _FakeBackend();
    await _open(tester, backend);
    await _tap(tester, find.byKey(const ValueKey('audience-level-followers')));
    expect(backend.calls, ['setLevel:followers']);
    expect(_selected(tester, AudienceLevel.followers), isTrue);
    expect(find.text('Updated who can see this.'), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('audience-share-link')));
    expect(_result, AudienceSheetResult.shareLink);
  });

  testWidgets('Public is handed back to the caller, never written here', (
    tester,
  ) async {
    final backend = _FakeBackend();
    await _open(tester, backend);
    await _tap(tester, find.byKey(const ValueKey('audience-level-public')));
    expect(backend.calls, isEmpty);
    expect(_result, AudienceSheetResult.requestPublic);
  });

  testWidgets('sharing with a person makes the level Specific people', (
    tester,
  ) async {
    final backend = _FakeBackend(people: const [_alex, _morgan]);
    await _open(tester, backend);
    await _tap(
      tester,
      find.descendant(
        of: find.byKey(const ValueKey('audience-person-u-morgan')),
        matching: find.text('Share'),
      ),
    );
    expect(backend.calls, ['add:u-morgan']);
    expect(_selected(tester, AudienceLevel.specific), isTrue);
    expect(
      find.byKey(const ValueKey('audience-shared-u-morgan')),
      findsOneWidget,
    );
    expect(find.text('Morgan Lee can now open it.'), findsOneWidget);
  });

  testWidgets('the search narrows the people list by name', (tester) async {
    await _open(tester, _FakeBackend(people: const [_alex, _morgan]));
    await tester.enterText(
      find.byKey(const ValueKey('audience-search')),
      'mor',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('audience-person-u-morgan')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('audience-person-u-alex')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('audience-search')),
      'zzz',
    );
    await tester.pumpAndSettle();
    expect(find.text('No one matches that name.'), findsOneWidget);
  });

  testWidgets('revoking one person removes them and says so', (tester) async {
    final backend = _FakeBackend(
      shares: const [_morgan],
      people: const [_morgan],
    );
    await _open(tester, backend);
    expect(_selected(tester, AudienceLevel.specific), isTrue);
    await _tap(tester, find.byTooltip('Stop sharing with Morgan Lee'));
    expect(backend.calls, ['revoke:u-morgan']);
    expect(
      find.byKey(const ValueKey('audience-shared-u-morgan')),
      findsNothing,
    );
    expect(find.text('Morgan Lee can no longer open it.'), findsOneWidget);
    expect(_selected(tester, AudienceLevel.private), isTrue);
  });

  testWidgets('Only me with live grants asks first, and Cancel keeps them', (
    tester,
  ) async {
    final backend = _FakeBackend(shares: const [_morgan]);
    await _open(tester, backend);
    await _tap(tester, find.byKey(const ValueKey('audience-level-private')));
    expect(find.text('Stop sharing with everyone?'), findsOneWidget);
    await _tap(tester, find.text('Cancel'));
    expect(backend.calls, isEmpty);
    expect(_selected(tester, AudienceLevel.specific), isTrue);

    await _tap(tester, find.byKey(const ValueKey('audience-level-private')));
    await _tap(tester, find.widgetWithText(TextButton, 'Only me'));
    expect(backend.calls, ['setLevel:private']);
    expect(find.text('Not shared with anyone yet.'), findsOneWidget);
  });

  testWidgets('a refused change is reported and the level stays put', (
    tester,
  ) async {
    final backend = _FakeBackend()..failSetLevel = true;
    await _open(tester, backend);
    await _tap(tester, find.byKey(const ValueKey('audience-level-followers')));
    expect(_selected(tester, AudienceLevel.private), isTrue);
    expect(
      find.textContaining("Couldn't change who can see this"),
      findsOneWidget,
    );
  });

  testWidgets('an unreadable row offers retry instead of the levels', (
    tester,
  ) async {
    final backend = _FakeBackend()..failColumns = true;
    await _open(tester, backend);
    expect(
      find.byKey(const ValueKey('audience-columns-error')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('audience-level-private')), findsNothing);

    backend.failColumns = false;
    await _tap(
      tester,
      find.descendant(
        of: find.byKey(const ValueKey('audience-columns-error')),
        matching: find.text('Retry'),
      ),
    );
    expect(_selected(tester, AudienceLevel.private), isTrue);
  });
}

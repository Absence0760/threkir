// Widget tests for GroupPeoplePicker (issue #1365 slice 3): the follow graph
// it offers, the search that narrows it, the selection count, the seat cap
// (which counts invitations, `groupSeatsLeft`), the people it never offers
// because they are already in the group or invited, and a failed load told
// apart from an empty one.

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/group_messages.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/l10n/gen/app_localizations_en.dart';
import '../lib/widgets/group_people_picker.dart';

UserProfileRow _p(String id, String name) => UserProfileRow(
      id: id,
      displayName: name,
      shadowHidden: false,
      profilePrivate: false,
    );

class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.fail = false});

  bool fail;
  int loads = 0;

  @override
  String? get userId => 'me';

  @override
  Future<KeysetPage<UserProfileRow>> fetchFollowers(
    String userId, {
    int limit = 100,
    List<Object?>? after,
  }) async {
    loads++;
    if (fail) throw Exception('offline');
    return KeysetPage([
      _p('ana', 'Ana Lopez'),
      _p('ben', 'Ben Ortiz'),
      _p('me', 'Me Myself'),
    ], null);
  }

  @override
  Future<KeysetPage<UserProfileRow>> fetchFollowing(
    String userId, {
    int limit = 100,
    List<Object?>? after,
  }) async {
    if (fail) throw Exception('offline');
    return KeysetPage([
      _p('ben', 'Ben Ortiz'),
      _p('cat', 'Cat Ng'),
      _p('dee', 'Dee Anand'),
    ], null);
  }
}

final _l10n = AppLocalizationsEn();

Finder _person(String id) => find.byKey(ValueKey('group-person-$id'));

class _Host extends StatefulWidget {
  const _Host({
    required this.api,
    required this.max,
    this.exclude = const {},
    this.disabled = false,
  });

  final ApiClient api;
  final int max;
  final Set<String> exclude;
  final bool disabled;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  List<String> selected = [];

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: GroupPeoplePicker(
          api: widget.api,
          selected: selected,
          onChanged: (ids) => setState(() => selected = ids),
          max: widget.max,
          exclude: widget.exclude,
          disabled: widget.disabled,
        ),
      );
}

Future<_HostState> _mount(
  WidgetTester tester,
  ApiClient api, {
  int max = 31,
  Set<String> exclude = const {},
  bool disabled = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: _Host(api: api, max: max, exclude: exclude, disabled: disabled),
      ),
    ),
  );
  await tester.pump();
  return tester.state<_HostState>(find.byType(_Host));
}

bool _enabled(WidgetTester tester, String id) =>
    tester.widget<CheckboxListTile>(_person(id)).onChanged != null;

String _count(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('group-people-count')))
    .data!;

void main() {
  testWidgets('offers both directions of the follow graph once each, never '
      'the viewer', (tester) async {
    await _mount(tester, _FakeApiClient());
    for (final id in ['ana', 'ben', 'cat', 'dee']) {
      expect(_person(id), findsOneWidget, reason: id);
    }
    expect(_person('me'), findsNothing);
    expect(_count(tester), _l10n.groupsPeopleSelected(0, 31));
  });

  testWidgets('search narrows the list and says when nothing matches',
      (tester) async {
    await _mount(tester, _FakeApiClient());
    final search = find.byKey(const ValueKey('group-people-search'));
    await tester.enterText(search, 'an');
    await tester.pump();
    expect(_person('ana'), findsOneWidget);
    expect(_person('dee'), findsOneWidget);
    expect(_person('ben'), findsNothing);
    expect(_person('cat'), findsNothing);

    await tester.enterText(search, 'zzz');
    await tester.pump();
    expect(find.text(_l10n.groupsPeopleNoMatches), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);

    await tester.enterText(search, '');
    await tester.pump();
    expect(find.byType(CheckboxListTile), findsNWidgets(4));
  });

  testWidgets('ticking and unticking keeps the count in step', (tester) async {
    final host = await _mount(tester, _FakeApiClient());
    await tester.tap(_person('ana'));
    await tester.pump();
    await tester.tap(_person('cat'));
    await tester.pump();
    expect(host.selected, ['ana', 'cat']);
    expect(_count(tester), _l10n.groupsPeopleSelected(2, 31));

    await tester.tap(_person('ana'));
    await tester.pump();
    expect(host.selected, ['cat']);
    expect(_count(tester), _l10n.groupsPeopleSelected(1, 31));
  });

  testWidgets(
      'the seat cap counts invitations: a group of 29 with 1 invite pending '
      'takes 2 more, then the rest lock', (tester) async {
    final seats = groupSeatsLeft(29, 1);
    expect(seats, kGroupMaxMembers - 30);
    final host = await _mount(tester, _FakeApiClient(), max: seats);
    expect(find.byKey(const ValueKey('group-people-full')), findsNothing);

    await tester.tap(_person('ana'));
    await tester.pump();
    await tester.tap(_person('ben'));
    await tester.pump();
    expect(host.selected, ['ana', 'ben']);
    expect(_count(tester), _l10n.groupsPeopleSelected(2, seats));
    expect(find.byKey(const ValueKey('group-people-full')), findsOneWidget);
    expect(find.text(_l10n.groupsPeopleFull(seats)), findsOneWidget);

    expect(_enabled(tester, 'cat'), isFalse);
    expect(_enabled(tester, 'dee'), isFalse);
    await tester.tap(_person('cat'), warnIfMissed: false);
    await tester.pump();
    expect(host.selected, ['ana', 'ben']);

    // A ticked person can still be unticked, which frees the seat.
    expect(_enabled(tester, 'ana'), isTrue);
    await tester.tap(_person('ana'));
    await tester.pump();
    expect(_enabled(tester, 'cat'), isTrue);
    expect(find.byKey(const ValueKey('group-people-full')), findsNothing);
  });

  testWidgets('a full group (no seats left) locks every person',
      (tester) async {
    await _mount(tester, _FakeApiClient(), max: groupSeatsLeft(30, 2));
    for (final id in ['ana', 'ben', 'cat', 'dee']) {
      expect(_enabled(tester, id), isFalse, reason: id);
    }
  });

  testWidgets('members and invitees are not offered at all', (tester) async {
    await _mount(tester, _FakeApiClient(), exclude: {'ben', 'cat'});
    expect(_person('ben'), findsNothing);
    expect(_person('cat'), findsNothing);
    expect(_person('ana'), findsOneWidget);
    expect(_person('dee'), findsOneWidget);
  });

  testWidgets('everyone already in reads as nobody to invite', (tester) async {
    await _mount(tester, _FakeApiClient(),
        exclude: {'ana', 'ben', 'cat', 'dee'});
    expect(find.byKey(const ValueKey('group-people-empty')), findsOneWidget);
    expect(find.text(_l10n.groupsPeopleEmpty), findsOneWidget);
  });

  testWidgets('disabled locks every row', (tester) async {
    await _mount(tester, _FakeApiClient(), disabled: true);
    for (final id in ['ana', 'ben', 'cat', 'dee']) {
      expect(_enabled(tester, id), isFalse, reason: id);
    }
  });

  testWidgets('a failed load says so and Retry loads again', (tester) async {
    final api = _FakeApiClient(fail: true);
    await _mount(tester, api);
    expect(find.byKey(const ValueKey('group-people-error')), findsOneWidget);
    expect(find.text(_l10n.groupsPeopleLoadFailed), findsOneWidget);
    expect(find.byKey(const ValueKey('group-people-empty')), findsNothing);

    api.fail = false;
    await tester.tap(find.text(_l10n.errorStateRetry));
    await tester.pump();
    expect(api.loads, 2);
    expect(find.byKey(const ValueKey('group-people-error')), findsNothing);
    expect(_person('ana'), findsOneWidget);
  });
}

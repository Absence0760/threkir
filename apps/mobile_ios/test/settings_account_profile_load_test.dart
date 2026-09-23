import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_account_screen.dart';

/// Each profile read takes the next queued completer, so a test decides
/// when — and whether — every read lands.
class _ProfileApi extends ApiClient {
  String? uid = 'a';
  final List<Completer<UserProfileRow?>> reads = <Completer<UserProfileRow?>>[];
  final List<String?> writes = <String?>[];
  final _auth = StreamController<String?>.broadcast();

  @override
  String? get userId => uid;
  @override
  String? get userEmail => uid == null ? null : '$uid@test.com';
  @override
  Stream<String?> get authUserChanges => _auth.stream;
  @override
  Future<Map<String, dynamic>?> fetchAiDisclosure() async => null;
  @override
  Future<UserProfileRow?> fetchMyProfile() {
    final read = Completer<UserProfileRow?>();
    reads.add(read);
    return read.future;
  }

  @override
  Future<void> updateDisplayName(String? displayName) async {
    writes.add(displayName);
  }

  void switchTo(String? next) {
    uid = next;
    _auth.add(next);
  }
}

UserProfileRow _row(String id, String? name) =>
    UserProfileRow(shadowHidden: false, id: id, displayName: name);

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(
    url: 'http://127.0.0.1:24321',
    anonKey: 'eyJ.local.test',
  );
  _supabaseReady = true;
}

Future<void> _pump(WidgetTester tester, _ProfileApi api) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsAccountScreen(
        apiClient: api,
        preferences: Preferences(),
        settingsSync: null,
      ),
    ),
  );
  // Not pumpAndSettle: a pending read shows a spinner that never settles.
  await tester.pump();
}

Finder _tile(String title) => find.ancestor(
      of: find.text(title),
      matching: find.byType(ListTile),
    );

const _loadFailed =
    "Couldn't load your profile, so your photo and display name can't be changed yet.";

void main() {
  setUp(() async {
    await _ensureSupabase();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('the name editor stays closed until the saved name has loaded',
      (tester) async {
    final api = _ProfileApi();
    await _pump(tester, api);

    expect(
      find.descendant(of: _tile('Display name'), matching: find.text('Loading…')),
      findsOneWidget,
    );
    await tester.tap(_tile('Display name'));
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);

    api.reads.single.complete(_row('a', 'Alex Rivera'));
    await tester.pumpAndSettle();

    await tester.tap(_tile('Display name'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    ));
    expect(field.controller!.text, 'Alex Rivera');
    expect(api.writes, isEmpty);
  });

  testWidgets(
      'a failed read offers Retry instead of an editor seeded with blanks',
      (tester) async {
    final api = _ProfileApi();
    await _pump(tester, api);

    api.reads.single.completeError(StateError('profile read failed'));
    await tester.pumpAndSettle();

    expect(find.text(_loadFailed), findsOneWidget);
    expect(find.text('Display name'), findsNothing);
    expect(find.text('Profile photo'), findsNothing);

    await tester.tap(find.descendant(
      of: _tile(_loadFailed),
      matching: find.text('Retry'),
    ));
    await tester.pump();
    expect(api.reads, hasLength(2));

    api.reads.last.complete(_row('a', 'Alex Rivera'));
    await tester.pumpAndSettle();

    expect(find.text(_loadFailed), findsNothing);
    expect(find.text('Alex Rivera'), findsOneWidget);
    expect(api.writes, isEmpty);
  });

  testWidgets(
      "a read that lands after an account switch does not show the previous account's name",
      (tester) async {
    final api = _ProfileApi();
    await _pump(tester, api);

    api.switchTo('b');
    await tester.pump();
    expect(api.reads, hasLength(2));

    api.reads.last.complete(_row('b', 'Bea'));
    await tester.pumpAndSettle();
    api.reads.first.complete(_row('a', 'Alex Rivera'));
    await tester.pumpAndSettle();

    expect(find.text('Bea'), findsOneWidget);
    expect(find.text('Alex Rivera'), findsNothing);
  });

  testWidgets('an account switch closes the editor again until the next read lands',
      (tester) async {
    final api = _ProfileApi();
    await _pump(tester, api);
    api.reads.single.complete(_row('a', 'Alex Rivera'));
    await tester.pumpAndSettle();

    api.switchTo('b');
    // The auth event is delivered during the first frame; its rebuild draws
    // on the second.
    await tester.pump();
    await tester.pump();

    expect(find.text('Alex Rivera'), findsNothing);
    await tester.tap(_tile('Display name'));
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);

    api.reads.last.completeError(StateError('profile read failed'));
    await tester.pumpAndSettle();
    expect(find.text(_loadFailed), findsOneWidget);
    expect(api.writes, isEmpty);
  });
}

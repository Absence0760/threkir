import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_account_screen.dart';
import '../lib/undo_queue.dart';
import '../lib/widgets/top_banner.dart' show kTopBannerMaxDuration;
import '../lib/widgets/undo_bar.dart';
import 'pump_until.dart';
import 'supabase_test_init.dart';

// Issue #1064: the delete-account challenge is one fixed localized word for
// every account. The email is a Hide My Email relay address here — the case
// the old email challenge made unfinishable.
const _relayEmail = '4554ffzhy7@privaterelay.appleid.com';

class _DeleteApi extends ApiClient {
  int deleteCalls = 0;
  int signOutCalls = 0;
  final List<String> calls = [];

  @override
  String? get userId => 'u1';
  @override
  String? get userEmail => _relayEmail;
  @override
  Future<Map<String, dynamic>?> fetchAiDisclosure() async => null;
  @override
  Future<UserProfileRow?> fetchMyProfile() async => UserProfileRow(profilePrivate: false, 
        shadowHidden: false,
        id: 'u1',
        displayName: 'Runner',
        avatarUrl: null,
      );
  @override
  Future<void> deleteAccount() async {
    deleteCalls++;
    calls.add('deleteAccount');
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    calls.add('signOut');
  }
}

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await initializeTestSupabase();
  _supabaseReady = true;
}

Future<void> _openDialog(
  WidgetTester tester,
  _DeleteApi api, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsAccountScreen(
        apiClient: api,
        preferences: Preferences(),
        settingsSync: null,
      ),
    ),
  );
  await tester.pumpAndSettle();
  final l10n = lookupAppLocalizations(locale);
  final tile = find.text(l10n.settingsAccountDeleteAccount);
  await tester.scrollUntilVisible(
    tile,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(tile);
  await pumpUntil(
    tester,
    () => find.byType(AlertDialog).evaluate().isNotEmpty,
    describe: 'the delete-account dialog to open',
  );
}

Finder get _challengeField => find.descendant(
    of: find.byType(AlertDialog), matching: find.byType(TextField));

FilledButton _deleteButton(WidgetTester tester) => tester.widget<FilledButton>(
      find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(FilledButton)),
    );

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(_challengeField, text);
  await tester.pump();
}

void main() {
  setUp(() async {
    await _ensureSupabase();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('label names the fixed word, never the account email',
      (tester) async {
    await _openDialog(tester, _DeleteApi());

    expect(find.text('Type "DELETE" to confirm'), findsOneWidget);
    expect(find.textContaining(_relayEmail), findsNothing);
  });

  testWidgets('the account email does not enable Delete', (tester) async {
    await _openDialog(tester, _DeleteApi());

    expect(_deleteButton(tester).onPressed, isNull);
    await _type(tester, _relayEmail);
    expect(_deleteButton(tester).onPressed, isNull);
  });

  testWidgets('the fixed word (any case, padded) confirms and deletes',
      (tester) async {
    final api = _DeleteApi();
    await _openDialog(tester, api);

    await _type(tester, '  delete ');
    expect(_deleteButton(tester).onPressed, isNotNull);

    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await pumpUntil(
      tester,
      () => api.signOutCalls == 1,
      describe: 'deleteAccount + signOut after confirming',
    );
    expect(api.deleteCalls, 1);
    // Let the "Account deleted" banner's dismiss timer expire.
    await tester.pump(kTopBannerMaxDuration);
  });

  // Reason: deleting the account with a delete still held in its undo
  // window ended the session first, so the held commit fired afterwards
  // with no session.
  testWidgets('a delete held in its undo window commits before the account '
      'is deleted', (tester) async {
    addTearDown(debugResetUndo);
    setUndoWindowS(0);
    final api = _DeleteApi();
    undoQueue.defer(DeferredDestruction(
      message: 'Removed',
      commit: () async => api.calls.add('commit'),
      restore: () {},
    ));
    await _openDialog(tester, api);

    await _type(tester, 'DELETE');
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await pumpUntil(
      tester,
      () => api.signOutCalls == 1,
      describe: 'deleteAccount + signOut after confirming',
    );
    expect(api.calls, ['commit', 'deleteAccount', 'signOut']);
    await tester.pump(kTopBannerMaxDuration);
  });

  testWidgets('the word follows the locale', (tester) async {
    final api = _DeleteApi();
    await _openDialog(tester, api, locale: const Locale('de'));

    expect(find.text('Gib „LÖSCHEN“ ein, um zu bestätigen'), findsOneWidget);
    await _type(tester, 'DELETE');
    expect(_deleteButton(tester).onPressed, isNull);
    await _type(tester, 'löschen');
    expect(_deleteButton(tester).onPressed, isNotNull);
    expect(api.deleteCalls, 0);
  });
}

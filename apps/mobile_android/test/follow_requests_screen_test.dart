import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/follow_requests_screen.dart';

class _FakeApi extends ApiClient {
  _FakeApi(this.requests, {this.declineThrows = false});

  List<IncomingFollowRequest> requests;
  final bool declineThrows;
  final List<String> approved = [];
  final List<String> declined = [];

  @override
  Future<List<IncomingFollowRequest>> fetchIncomingFollowRequests() async =>
      requests;

  @override
  Future<void> approveFollowRequest(String requesterId) async {
    approved.add(requesterId);
  }

  @override
  Future<void> declineFollowRequest(String requesterId) async {
    if (declineThrows) throw StateError('follow request not declined');
    declined.add(requesterId);
  }
}

IncomingFollowRequest _req(String id, String name) => IncomingFollowRequest(
      requester: PublicProfile(id: id, displayName: name),
      requestedAt: DateTime.utc(2026, 10, 1),
    );

Future<void> _pump(WidgetTester tester, ApiClient api) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: FollowRequestsScreen(api: api),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  // Outside any testWidgets body: the auth client arms a periodic refresh
  // timer, which inside one is a fake timer still pending at teardown.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:24321',
      anonKey: 'eyJ.local.test',
    );
  });

  testWidgets('approving removes the row and calls the approve RPC',
      (tester) async {
    final api = _FakeApi([_req('a', 'Ada'), _req('b', 'Bo')]);
    await _pump(tester, api);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('Bo'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('follow-request-approve-a')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.approved, ['a']);
    expect(find.text('Ada'), findsNothing);
    expect(find.text('Bo'), findsOneWidget);
    expect(find.text('Ada can now see your profile'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4)); // drain banner timer
  });

  testWidgets('declining the last request leaves the empty state',
      (tester) async {
    final api = _FakeApi([_req('a', 'Ada')]);
    await _pump(tester, api);

    await tester.tap(find.byKey(const ValueKey('follow-request-decline-a')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.declined, ['a']);
    expect(find.byKey(const ValueKey('follow-requests-empty')), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a failed decline keeps the row and says so', (tester) async {
    final api = _FakeApi([_req('a', 'Ada')], declineThrows: true);
    await _pump(tester, api);

    await tester.tap(find.byKey(const ValueKey('follow-request-decline-a')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Ada'), findsOneWidget);
    expect(find.text("Couldn't update the request."), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });
}

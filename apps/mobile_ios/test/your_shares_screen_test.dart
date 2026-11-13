// Your shares (decisions § 2268): the creator's links with their counts, the
// empty state, and a failed load that says so and retries.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/your_shares_screen.dart';
import '../lib/share_ref.dart';
import '../lib/social_service.dart';
import '../lib/widgets/error_state.dart';
import 'worst_case_layout.dart';

class _FakeSocial extends SocialService {
  _FakeSocial(this.rows, {this.fail = false});
  List<ShareStat> rows;
  bool fail;
  int loads = 0;

  @override
  Future<List<ShareStat>> fetchMyShareStats() async {
    loads++;
    if (fail) throw StateError('offline');
    return rows;
  }
}

Future<void> _pump(WidgetTester tester, _FakeSocial social) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: YourSharesScreen(social: social),
  ));
  await tester.pump();
  await tester.pump();
}

const _stats = [
  ShareStat(
      kind: 'plan',
      entityId: 'p1',
      title: 'Marathon block for the autumn city races',
      visits: 12345,
      refVisits: 5432,
      signups: 210,
      starts: 3,
      refStarts: 1),
  ShareStat(kind: 'challenge', entityId: 'c1', title: 'Run 50 km', joins: 4, refJoins: 4),
  ShareStat(kind: 'profile', entityId: 'u1', visits: 7, botVisits: 2),
];

void main() {
  worstCaseTestWidgets('Your shares list', (tester, locale) async {
    await tester.pumpWidget(worstCaseApp(
      locale: locale,
      home: YourSharesScreen(social: _FakeSocial(_stats)),
    ));
    await tester.pump();
    await tester.pump();
    await walkScrollable(tester, find.byType(Scrollable).first, 'Your shares');
  });

  testWidgets('each link shows its visits, sign-ups and starts or joins', (tester) async {
    await _pump(
        tester,
        _FakeSocial(const [
          ShareStat(
              kind: 'plan',
              entityId: 'p1',
              title: 'Marathon block',
              visits: 12,
              refVisits: 5,
              signups: 2,
              starts: 3,
              refStarts: 1),
          ShareStat(kind: 'challenge', entityId: 'c1', title: 'Run 50 km', joins: 4, refJoins: 4),
          ShareStat(kind: 'profile', entityId: 'u1', visits: 7, botVisits: 2),
        ]));
    expect(find.text('Marathon block'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('5 through your link'), findsOneWidget);
    expect(find.text('Plan starts'), findsOneWidget);
    expect(find.text('Run 50 km'), findsOneWidget);
    expect(find.text('Challenge joins'), findsOneWidget);
    expect(find.text('4 through your link'), findsOneWidget);
    expect(find.text('Your profile'), findsOneWidget);
    expect(find.text('Plus 2 visits from crawlers, not counted above.'), findsOneWidget);
  });

  testWidgets('no links yet shows the empty state', (tester) async {
    await _pump(tester, _FakeSocial(const []));
    expect(find.text('Nothing shared yet'), findsOneWidget);
  });

  testWidgets('a failed load says so and retries', (tester) async {
    final social = _FakeSocial(const [], fail: true);
    await _pump(tester, social);
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text("Couldn't load your shares."), findsOneWidget);
    social.fail = false;
    social.rows = const [ShareStat(kind: 'plan', entityId: 'p1', title: 'Back again')];
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(social.loads, 2);
    expect(find.text('Back again'), findsOneWidget);
  });
}

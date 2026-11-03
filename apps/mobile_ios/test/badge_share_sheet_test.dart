import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/badge_grid.dart';
import '../lib/widgets/badge_share_sheet.dart';

AchievementRow _award({bool isPublic = true}) => AchievementRow(
      id: 'b1',
      userId: 'u1',
      badgeKey: 'streak',
      tier: 'gold',
      sourceKind: 'streak',
      earnedAt: DateTime.utc(2026, 5, 1, 12),
      isPublic: isPublic,
    );

Widget _host(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  setUp(() => initializeDateFormatting());

  group('BadgeGrid owner controls', () {
    testWidgets('the owner sees a private badge flagged and can open it', (tester) async {
      AchievementRow? opened;
      await tester.pumpWidget(_host(BadgeGrid(
        badges: [_award(isPublic: false)],
        isOwner: true,
        onOpen: (b) => opened = b,
      )));
      await tester.pump();
      expect(find.byTooltip('Private'), findsOneWidget);
      await tester.tap(find.text('Century streak'));
      expect(opened?.id, 'b1');
    });

    testWidgets('a visitor sees no flag and opens nothing', (tester) async {
      AchievementRow? opened;
      await tester.pumpWidget(_host(BadgeGrid(
        badges: [_award()],
        onOpen: (b) => opened = b,
      )));
      await tester.pump();
      expect(find.byTooltip('Private'), findsNothing);
      await tester.tap(find.text('Century streak'));
      expect(opened, isNull);
    });
  });

  group('showBadgeShareSheet', () {
    Future<void> open(
      WidgetTester tester, {
      required AchievementRow badge,
      required BadgeVisibilitySetter setVisibility,
      List<AchievementRow>? changes,
      List<String>? shared,
    }) async {
      await tester.pumpWidget(_host(Builder(
        builder: (context) => TextButton(
          onPressed: () => showBadgeShareSheet(
            context,
            badge: badge,
            setVisibility: setVisibility,
            onChanged: (b) => changes?.add(b),
            shareOverride: (_, text) async => shared?.add(text),
          ),
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    ButtonStyleButton button(WidgetTester tester, String key) =>
        tester.widget<ButtonStyleButton>(find.byKey(Key(key)));

    testWidgets('a public badge shares its public page', (tester) async {
      final shared = <String>[];
      await open(tester, badge: _award(), setVisibility: (_, __) async {}, shared: shared);
      expect(find.text('Century streak'), findsWidgets);
      expect(find.text('Make private'), findsOneWidget);
      await tester.tap(find.byKey(const Key('badge-share')));
      await tester.pumpAndSettle();
      expect(shared, hasLength(1));
      expect(shared.single, contains('/share/badge/b1'));
      expect(shared.single, contains('Century streak'));
    });

    testWidgets('a private badge cannot be shared until it is made public', (tester) async {
      final calls = <(String, bool)>[];
      final changes = <AchievementRow>[];
      await open(
        tester,
        badge: _award(isPublic: false),
        setVisibility: (id, isPublic) async => calls.add((id, isPublic)),
        changes: changes,
      );
      expect(button(tester, 'badge-share').enabled, isFalse);
      expect(find.text('Make this badge public to share it.'), findsOneWidget);

      await tester.tap(find.text('Make public'));
      await tester.pumpAndSettle();
      expect(calls, [('b1', true)]);
      expect(changes.single.isPublic, isTrue);
      expect(button(tester, 'badge-share').enabled, isTrue);
      expect(find.text('Make private'), findsOneWidget);
    });

    testWidgets('a failed change says so and keeps the badge as it was', (tester) async {
      final changes = <AchievementRow>[];
      await open(
        tester,
        badge: _award(),
        setVisibility: (_, __) async => throw StateError('refused'),
        changes: changes,
      );
      await tester.tap(find.text('Make private'));
      await tester.pump();
      await tester.pump();
      expect(find.text("Couldn't change visibility. Try again."), findsOneWidget);
      expect(changes, isEmpty);
      expect(find.text('Make private'), findsOneWidget);
      // Let the banner's dismiss timer run out so none is left pending.
      await tester.pump(const Duration(seconds: 5));
    });

    test('the share URL is the web badge page', () {
      expect(badgeShareUrl('b1', webBase: 'https://threkir.com').toString(),
          'https://threkir.com/share/badge/b1');
    });
  });
}

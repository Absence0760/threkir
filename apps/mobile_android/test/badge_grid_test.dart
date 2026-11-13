import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/badges.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/widgets/badge_grid.dart';

AchievementRow _award({
  String badgeKey = 'streak',
  String tier = 'gold',
  bool isPublic = true,
}) =>
    AchievementRow(
      id: '$badgeKey-$tier',
      userId: 'u1',
      badgeKey: badgeKey,
      tier: tier,
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

  testWidgets('empty owner state renders the keep-running prompt',
      (tester) async {
    await tester.pumpWidget(_host(const BadgeGrid(badges: [], isOwner: true)));
    expect(find.text('No badges yet — keep running.'), findsOneWidget);
  });

  testWidgets('empty non-owner state renders the public-empty prompt',
      (tester) async {
    await tester.pumpWidget(_host(const BadgeGrid(badges: [], isOwner: false)));
    expect(find.text('No public badges yet.'), findsOneWidget);
  });

  testWidgets('a seeded award renders its label, tier and earned date',
      (tester) async {
    await tester.pumpWidget(_host(BadgeGrid(badges: [_award()])));
    await tester.pump();
    expect(find.text('Century streak'), findsOneWidget);
    expect(find.text('GOLD'), findsOneWidget);
    expect(find.textContaining('Earned'), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department), findsOneWidget);
  });

  test('badgeLabelFor resolves a stored award to its catalogue label', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(badgeLabelFor(l10n, 'pr', 'gold'), 'PR collector');
    expect(badgeLabelFor(l10n, 'unknown', 'gold'), 'unknown');
  });

  // Mirrored by the badgeWords cases in apps/web/src/lib/social/badges.test.ts.
  test('badgeWords: a distance badge names its threshold in the reader\'s unit',
      () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    String? desc(String key, String tier, DistanceUnit unit) =>
        badgeWords(l10n, key, tier, unit: unit, localeTag: 'en')?.desc;
    String? label(String key, String tier, DistanceUnit unit) =>
        badgeWords(l10n, key, tier, unit: unit, localeTag: 'en')?.label;
    expect(desc('distance_single', 'gold', DistanceUnit.km),
        'Ran 42.2 km in a single run');
    expect(desc('distance_single', 'gold', DistanceUnit.mi),
        'Ran 26.2 mi in a single run');
    expect(desc('distance_single', 'bronze', DistanceUnit.mi),
        'Ran 3.1 mi in a single run');
    expect(label('distance_lifetime', 'gold', DistanceUnit.km), '1,000 km club');
    expect(label('distance_lifetime', 'gold', DistanceUnit.mi), '621 mi club');
    expect(desc('distance_lifetime', 'platinum', DistanceUnit.mi),
        '3,107 mi logged all-time');
  });

  test('badgeWords: other families take no distance, and an unknown award is null',
      () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final w = badgeWords(l10n, 'streak', 'bronze', unit: DistanceUnit.mi);
    expect(w?.label, l10n.badgesStreak7Label);
    expect(w?.desc, l10n.badgesStreak7Desc);
    expect(w?.icon, 'local_fire_department');
    expect(badgeWords(l10n, 'nope', 'bronze'), isNull);
    expect(badgeWords(l10n, 'streak', 'platinum')?.icon, 'whatshot');
  });

  test('badgeWords: the number follows the reader\'s locale', () {
    final l10n = lookupAppLocalizations(const Locale('fr'));
    expect(
        badgeWords(l10n, 'distance_lifetime', 'gold',
                unit: DistanceUnit.km, localeTag: 'fr')
            ?.label,
        'Club des 1\u202f000 km');
  });

  testWidgets('a miles reader reads a distance badge in miles', (tester) async {
    SharedPreferences.setMockInitialValues({'use_miles': true});
    final prefs = Preferences();
    await prefs.init();
    registerActivePreferences(prefs);
    addTearDown(() async {
      SharedPreferences.setMockInitialValues({});
      final km = Preferences();
      await km.init();
      registerActivePreferences(km);
    });
    await tester.pumpWidget(_host(BadgeGrid(badges: [
      _award(badgeKey: 'distance_single', tier: 'gold'),
    ])));
    await tester.pump();
    expect(find.text('Ran 26.2 mi in a single run'), findsOneWidget);
    expect(find.textContaining('km'), findsNothing);
  });

  test('badgeIconData maps every catalogue icon to a real IconData', () {
    for (final b in kBadgeCatalogue) {
      for (final t in b.tiers) {
        expect(badgeIconData(t.icon), isA<IconData>());
      }
    }
  });

  test('badgeTierColor + badgeTierLabel cover all tiers', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    for (final tier in kTierOrder) {
      expect(badgeTierColor(tier), isA<Color>());
      expect(badgeTierLabel(l10n, tier), isNotEmpty);
    }
  });
}

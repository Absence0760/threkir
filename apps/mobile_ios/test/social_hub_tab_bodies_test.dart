// ignore_for_file: avoid_relative_lib_imports
// Every Social tab at the worst case the issue #1374 rules name: a 320 dp
// phone, 2x text and Android's 3-button navigation bar. Each tab body is a
// HubTabBody, so the hub draws the one app bar (title, Messages, the bell and
// the strip) and the one FAB; this walks every tab with a row on each, fails
// on an overflow, and checks the hub's FAB sits clear of the nav bar wherever
// a tab has a primary action.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ui_kit/ui_kit.dart' show AppSearchField, FilterBar;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/screens/social_screen.dart';
import '../lib/training_service.dart';
import 'social_hub_fakes.dart';
import 'three_button_nav_bar.dart' show kThreeButtonNavBar;

const _phone = Size(320, 640);

void main() {
  setUpAll(() async {
    await ensureSocialTestSupabase();
    await initializeDateFormatting();
    // The Clubs tab reads dotenv['MAPTILER_KEY'] on load.
    dotenv.loadFromString(isOptional: true);
  });

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('social_tabs_'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> pumpHub(WidgetTester tester) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: kThreeButtonNavBar);
    tester.view.padding = const FakeViewPadding(bottom: kThreeButtonNavBar);
    addTearDown(tester.view.reset);
    final routeStore = LocalRouteStore();
    await routeStore.init(overrideDirectory: tmp);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2.0)),
        child: child!,
      ),
      home: SocialScreen(
        api: SocialHubFakeApi(),
        social: SocialHubFakeService(),
        training: TrainingService(),
        routeStore: routeStore,
        selectedTab: ValueNotifier(SocialTab.feed),
        unreadMessages: FixedUnreadMessages(3),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    final tab =
        find.descendant(of: find.byType(TabBar), matching: find.text(label));
    await tester.ensureVisible(tab);
    await tester.tap(tab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  // The tabs with a primary action, by the label of the FAB the hub shows.
  const fabs = {
    'Clubs': 'New club',
    'Challenges': 'Create challenge',
  };

  testWidgets('every tab fits 320 dp at 2x, with no app bar of its own and '
      'the FAB clear of the 3-button bar', (tester) async {
    await pumpHub(tester);
    for (final label in ['Feed', 'Clubs', 'Events', 'Challenges', 'People']) {
      await openTab(tester, label);
      expect(tester.takeException(), isNull, reason: '$label overflowed');
      expect(find.byType(AppBar), findsOneWidget,
          reason: '$label drew an app bar under the strip');
      final fab = find.byType(FloatingActionButton);
      if (fabs[label] case final text?) {
        expect(find.widgetWithText(FloatingActionButton, text), findsOneWidget,
            reason: '$label\'s primary action is the hub\'s FAB');
        expect(tester.getRect(fab).bottom,
            lessThanOrEqualTo(_phone.height - kThreeButtonNavBar),
            reason: '$label\'s FAB reaches into the nav bar');
        expect(tester.getRect(fab).right, lessThanOrEqualTo(_phone.width));
      } else {
        expect(fab, findsNothing, reason: '$label has no primary action');
      }
    }
  });

  testWidgets('the list tabs\' controls are one FilterBar each', (tester) async {
    await pumpHub(tester);
    for (final (label, key) in [
      ('Feed', 'feed-filter-bar'),
      ('Clubs', 'clubs-filter-bar'),
      ('Events', 'events-filter-bar'),
      ('People', 'people-filter-bar'),
    ]) {
      await openTab(tester, label);
      expect(find.byKey(ValueKey(key)), findsOneWidget,
          reason: '$label\'s controls are not its FilterBar');
    }
    await openTab(tester, 'Events');
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('events-filter-bar')),
            matching: find.byType(AppSearchField)),
        findsOneWidget);
    expect(find.byType(FilterBar), findsWidgets);
  });

  testWidgets('the hub\'s top bar fits Messages and the bell at 2x on 320 dp',
      (tester) async {
    await pumpHub(tester);
    expect(tester.takeException(), isNull);
    final messages = find.byKey(const ValueKey('social-messages'));
    expect(messages, findsOneWidget);
    expect(find.byTooltip('Notifications'), findsOneWidget);
    expect(tester.getRect(messages).right, lessThanOrEqualTo(_phone.width));
  });
}

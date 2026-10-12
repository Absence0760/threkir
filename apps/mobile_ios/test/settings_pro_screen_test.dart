import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/date_format.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/legal_links.dart';
import '../lib/pro_sellable.dart';
import '../lib/revenuecat.dart';
import '../lib/screens/settings_pro_screen.dart';
import '../lib/store_links.dart';
import 'pro_plan_fixtures.dart';
import 'pump_until.dart';

class _FakeProStore implements ProStore {
  _FakeProStore(
    this._load, {
    this.entitlement,
    this.purchaseResult = PurchaseResult.cancelled,
    this.entitlementOnSuccess,
  });

  final Future<ProPlanOptions?> Function() _load;
  final purchased = <ProPlan>[];
  var restores = 0;

  /// What the store reports as the active Pro entitlement right now.
  ProEntitlement? entitlement;
  final PurchaseResult purchaseResult;

  /// The entitlement a successful purchase or restore leaves behind.
  final ProEntitlement? entitlementOnSuccess;

  @override
  bool get configured => true;

  @override
  Future<ProPlanOptions?> loadPlans() => _load();

  @override
  Future<PurchaseResult> purchase(ProPlan plan) async {
    purchased.add(plan);
    if (purchaseResult == PurchaseResult.purchased) {
      entitlement = entitlementOnSuccess;
    }
    return purchaseResult;
  }

  @override
  Future<PurchaseResult> restore() async {
    restores++;
    entitlement = entitlementOnSuccess;
    return entitlement == null
        ? PurchaseResult.cancelled
        : PurchaseResult.purchased;
  }

  @override
  Future<ProEntitlement?> loadEntitlement() async => entitlement;
}

/// Pins two things about the mobile Pro storefront:
///
/// 1. The hollow-subscription gate (decisions §466) — the purchase CTA
///    renders only when the deploy has a live Pro perk, mirroring web's
///    `proSellable` branch. Unknown (the manifest didn't answer) counts as
///    not sellable, so the failure direction is "don't take the money".
/// 2. The plan choice (C5): annual and monthly priced from the store, the
///    chosen plan is the one purchased, and a missing or failed offering
///    degrades to the single monthly fallback rather than breaking.
/// 3. The payment double-submit guard: tapping Subscribe puts the IAP tiles
///    into a busy state, so a second tap can't open a second checkout.
///    RevenueCat is unconfigured in the test env, so checkout falls through
///    to the external-upgrade URL — we gate that launch to hold the busy
///    window open and assert the tile is disabled while in flight.
void main() {
  const launcher = MethodChannel('plugins.flutter.io/url_launcher');

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:24321', anonKey: 'eyJ.local.test');
    await initializeDateFormatting();
  });

  Future<void> pumpPro(WidgetTester tester, ProPerks perks) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsProScreen(loadPerks: () async => perks),
      ),
    );
    await tester.pump();
  }

  final subscribeTile =
      find.widgetWithIcon(ListTile, Icons.workspace_premium_outlined);

  testWidgets('no purchase CTA when the deploy has no live Pro perk',
      (tester) async {
    await pumpPro(tester, ProPerks.none);

    expect(find.text('Pro — coming soon'), findsOneWidget);
    expect(find.textContaining('Subscribe to Pro'), findsNothing);
    // The teaser tile is inert — no onTap, so no path to checkout at all.
    expect(tester.widget<ListTile>(subscribeTile).onTap, isNull);
    // The USD/regional disclosure belongs to a price we are not quoting.
    expect(find.textContaining('Billed in US dollars'), findsNothing);
    // Restore + manage stay reachable: an existing subscriber must still be
    // able to re-link or cancel on a deploy that has stopped selling.
    expect(find.text('Restore purchases'), findsOneWidget);
    expect(find.text('Manage subscription'), findsOneWidget);
  });

  testWidgets('purchase CTA returns when a single perk goes live',
      (tester) async {
    await pumpPro(tester,
        const ProPerks(coach: false, routeGen: true, webCheckout: true));

    expect(find.textContaining('Subscribe to Pro'), findsOneWidget);
    expect(find.text('Pro — coming soon'), findsNothing);
    expect(tester.widget<ListTile>(subscribeTile).onTap, isNotNull);
  });

  testWidgets('storefront stays a teaser while the perk lookup is unresolved',
      (tester) async {
    final pending = Completer<ProPerks>();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsProScreen(loadPerks: () => pending.future),
      ),
    );
    await tester.pump();

    expect(find.text('Pro — coming soon'), findsOneWidget);
    expect(find.textContaining('Subscribe to Pro'), findsNothing);

    pending.complete(
        const ProPerks(coach: true, routeGen: false, webCheckout: true));
    // One pump to let the await continuation run, one to rebuild.
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Subscribe to Pro'), findsOneWidget);
  });

  // decisions § 1826: with no RevenueCat key the purchase would be the web
  // page, and with web checkout off that page can only point at the iPhone
  // app. Android shows the teaser rather than a tile into that dead end.
  testWidgets('Android with no store and no web checkout shows the teaser',
      (tester) async {
    await pumpPro(tester, const ProPerks(coach: true, routeGen: false));

    expect(find.textContaining('Subscribe to Pro'), findsNothing);
    expect(find.text('Pro — coming soon'), findsOneWidget);
    expect(tester.widget<ListTile>(subscribeTile).onTap, isNull);
    expect(find.text('Restore purchases'), findsOneWidget);
    expect(find.text('Manage subscription'), findsOneWidget);
  });

  // decisions § 1700: iOS may not route a digital purchase or a donation to
  // Threkir through the web. RevenueCat is unconfigured here, so a live perk
  // would otherwise be sold through exactly that web checkout.
  testWidgets('iOS offers no web checkout and no Support link',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      // Web checkout live too: iOS still may not link out to it.
      await pumpPro(tester,
          const ProPerks(coach: true, routeGen: false, webCheckout: true));

      expect(find.textContaining('Subscribe to Pro'), findsNothing);
      expect(find.text('Pro — coming soon'), findsOneWidget);
      expect(find.byIcon(Icons.volunteer_activism_outlined), findsNothing);
      expect(find.text('Restore purchases'), findsOneWidget);
      expect(find.text('Manage subscription'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Terms and Privacy are reachable from the storefront (3.1.2)',
      (tester) async {
    final launched = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(launcher,
        (call) async {
      if (call.method == 'launch' || call.method == 'launchUrl') {
        launched.add((call.arguments as Map)['url'] as String);
      }
      return true;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(launcher, null));

    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await pumpPro(tester, const ProPerks(coach: true, routeGen: false));
        expect(find.widgetWithText(TextButton, 'Terms of Service'),
            findsOneWidget);
        expect(
            find.widgetWithText(TextButton, 'Privacy Policy'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    await tester.tap(find.widgetWithText(TextButton, 'Terms of Service'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Privacy Policy'));
    await tester.pump();
    expect(launched, [
      legalDocUrl(LegalDoc.terms),
      legalDocUrl(LegalDoc.privacy),
    ]);
  });

  testWidgets('Android keeps the Support link', (tester) async {
    await pumpPro(tester, ProPerks.none);

    expect(find.byIcon(Icons.volunteer_activism_outlined), findsOneWidget);
  });

  testWidgets('iOS Manage subscription opens Apple, not the page that sells Pro',
      (tester) async {
    final launched = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(launcher,
        (call) async {
      if (call.method == 'launch' || call.method == 'launchUrl') {
        launched.add((call.arguments as Map)['url'] as String);
      }
      return true;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(launcher, null));

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pumpPro(tester, ProPerks.none);
      await tester.tap(find.text('Manage subscription'));
      await tester.pump();
      await tester.pump();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }

    expect(launched, [appleSubscriptionsUrl]);
  });

  testWidgets('Subscribe tile disables while a checkout is in flight (no double-submit)',
      (tester) async {
    final gate = Completer<void>();
    var launchCalls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(launcher,
        (call) async {
      // url_launcher probes (canLaunch/supportsMode) pass through; only the
      // actual launch holds the gate so the busy window stays open.
      if (call.method == 'launch' || call.method == 'launchUrl') {
        launchCalls++;
        await gate.future;
        return true;
      }
      return true;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(launcher, null));

    await pumpPro(tester,
        const ProPerks(coach: true, routeGen: false, webCheckout: true));

    expect(subscribeTile, findsOneWidget);
    expect(tester.widget<ListTile>(subscribeTile).enabled, isTrue);

    await tester.tap(subscribeTile);
    await tester.pump();

    // Busy: the tile is now disabled, so a second tap can't fire a second
    // checkout.
    expect(tester.widget<ListTile>(subscribeTile).enabled, isFalse);

    // Release the gate; the checkout completes and the tile re-enables.
    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(launchCalls, 1);
  });

  group('plan choice', () {
    const livePerks = ProPerks(coach: true, routeGen: false);

    Future<_FakeProStore> pumpWithStore(
      WidgetTester tester,
      Future<ProPlanOptions?> Function() load,
    ) async {
      final store = _FakeProStore(load);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsProScreen(
            loadPerks: () async => livePerks,
            store: store,
          ),
        ),
      );
      await tester.pump();
      return store;
    }

    Future<void> waitForSubscribe(WidgetTester tester, String title) =>
        pumpUntil(
          tester,
          () => find.text(title).evaluate().isNotEmpty,
          describe: 'the subscribe tile to read "$title"',
        );

    final bothPlans = ProPlanOptions(
      monthly: proMonthlyPackage,
      annual: proAnnualPackage,
    );

    testWidgets('both plans show store prices, the saving, and default to annual',
        (tester) async {
      await pumpWithStore(tester, () async => bothPlans);
      await waitForSubscribe(tester, r'Subscribe to Pro — $79.99/year');

      expect(find.text(r'Yearly — $79.99/year'), findsOneWidget);
      expect(find.text(r'Monthly — $9.99/month'), findsOneWidget);
      expect(find.text('Save 33% compared with paying monthly'), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      expect(
        find.widgetWithText(ListTile, r'Yearly — $79.99/year'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ListTile>(
                find.widgetWithText(ListTile, r'Yearly — $79.99/year'))
            .selected,
        isTrue,
      );
      expect(find.textContaining('Auto-renews yearly'), findsOneWidget);
      // The store price is the real one, so the USD disclaimer is not shown.
      expect(find.textContaining('Billed in US dollars'), findsNothing);
    });

    testWidgets('subscribing on the default buys the annual package',
        (tester) async {
      final store = await pumpWithStore(tester, () async => bothPlans);
      await waitForSubscribe(tester, r'Subscribe to Pro — $79.99/year');

      await tester.tap(subscribeTile);
      await pumpUntil(tester, () => store.purchased.isNotEmpty,
          describe: 'the checkout to start');
      expect(store.purchased, [ProPlan.annual]);
    });

    testWidgets('choosing monthly buys the monthly package', (tester) async {
      final store = await pumpWithStore(tester, () async => bothPlans);
      await waitForSubscribe(tester, r'Subscribe to Pro — $79.99/year');

      await tester.tap(find.text(r'Monthly — $9.99/month'));
      await tester.pump();
      expect(find.text(r'Subscribe to Pro — $9.99/month'), findsOneWidget);
      expect(find.textContaining('Auto-renews monthly'), findsOneWidget);

      await tester.tap(subscribeTile);
      await pumpUntil(tester, () => store.purchased.isNotEmpty,
          describe: 'the checkout to start');
      expect(store.purchased, [ProPlan.monthly]);
    });

    testWidgets('a single package is offered alone, at its store price',
        (tester) async {
      final store = await pumpWithStore(
          tester, () async => ProPlanOptions(monthly: proMonthlyPackage));
      await pumpUntil(
        tester,
        () =>
            find.text(r'Subscribe to Pro — $9.99/month').evaluate().isNotEmpty &&
            find.textContaining('Billed in US dollars').evaluate().isEmpty,
        describe: 'the store price to replace the USD fallback',
      );

      expect(find.text(r'Subscribe to Pro — $9.99/month'), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_checked), findsNothing);
      expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
      expect(find.textContaining('compared with paying monthly'), findsNothing);

      await tester.tap(subscribeTile);
      await pumpUntil(tester, () => store.purchased.isNotEmpty,
          describe: 'the checkout to start');
      expect(store.purchased, [ProPlan.monthly]);
    });

    testWidgets('an annual-only offering sells the annual package',
        (tester) async {
      final store = await pumpWithStore(
          tester, () async => ProPlanOptions(annual: proAnnualPackage));
      await waitForSubscribe(tester, r'Subscribe to Pro — $79.99/year');
      expect(find.byIcon(Icons.radio_button_checked), findsNothing);

      await tester.tap(subscribeTile);
      await pumpUntil(tester, () => store.purchased.isNotEmpty,
          describe: 'the checkout to start');
      expect(store.purchased, [ProPlan.annual]);
    });

    testWidgets('no offering falls back to the monthly USD list price',
        (tester) async {
      final store = await pumpWithStore(tester, () async => null);
      await waitForSubscribe(tester, r'Subscribe to Pro — $9.99/month');

      expect(find.textContaining('Billed in US dollars'), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_checked), findsNothing);

      await tester.tap(subscribeTile);
      await pumpUntil(tester, () => store.purchased.isNotEmpty,
          describe: 'the checkout to start');
      expect(store.purchased, [ProPlan.monthly]);
    });

    testWidgets('a failing offerings fetch leaves the screen usable',
        (tester) async {
      await pumpWithStore(
          tester, () => Future<ProPlanOptions?>.error(StateError('offline')));
      await waitForSubscribe(tester, r'Subscribe to Pro — $9.99/month');

      expect(tester.takeException(), isNull);
      expect(find.text('Restore purchases'), findsOneWidget);
      expect(find.text('Manage subscription'), findsOneWidget);
    });
  });
  // Issue #1122: after buying Pro the screen kept offering the plans, as if
  // the subscriber were free. Pro status is the store entitlement (instant
  // after a purchase) or the server tier (authoritative, lags the webhook).
  group('subscriber state', () {
    const livePerks = ProPerks(coach: true, routeGen: false);
    final bothPlans = ProPlanOptions(
      monthly: proMonthlyPackage,
      annual: proAnnualPackage,
    );
    final renewsAt = DateTime.utc(2026, 11, 11, 12);

    Future<_FakeProStore> pumpSubscriber(
      WidgetTester tester, {
      ProEntitlement? entitlement,
      PurchaseResult purchaseResult = PurchaseResult.cancelled,
      ProEntitlement? entitlementOnSuccess,
      bool? serverPro,
    }) async {
      final store = _FakeProStore(
        () async => bothPlans,
        entitlement: entitlement,
        purchaseResult: purchaseResult,
        entitlementOnSuccess: entitlementOnSuccess,
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsProScreen(
            loadPerks: () async => livePerks,
            store: store,
            loadServerPro: serverPro == null ? null : () async => serverPro,
          ),
        ),
      );
      await tester.pump();
      return store;
    }

    Future<void> waitForText(WidgetTester tester, String text) => pumpUntil(
          tester,
          () => find.text(text).evaluate().isNotEmpty,
          describe: '"$text" to show',
        );

    void expectNoStorefront() {
      expect(find.textContaining('Subscribe to Pro'), findsNothing);
      expect(find.text(r'Yearly — $79.99/year'), findsNothing);
      expect(find.text(r'Monthly — $9.99/month'), findsNothing);
      expect(find.text('Pro — coming soon'), findsNothing);
      expect(find.text('Restore purchases'), findsOneWidget);
      expect(find.text('Manage subscription'), findsOneWidget);
    }

    testWidgets('a store entitlement shows the plan and renewal, not the plans',
        (tester) async {
      await pumpSubscriber(
        tester,
        entitlement: ProEntitlement(plan: ProPlan.monthly, expiresAt: renewsAt),
        serverPro: true,
      );
      await waitForText(tester, "You're on Pro");

      expect(
        find.text('Monthly plan · Renews ${formatDateMed(renewsAt, 'en')}'),
        findsOneWidget,
      );
      expectNoStorefront();
      // The server agrees, so nothing is still unlocking.
      expect(find.textContaining('can take a minute'), findsNothing);
    });

    testWidgets('a cancelled subscription says when it ends', (tester) async {
      await pumpSubscriber(
        tester,
        entitlement: ProEntitlement(
          plan: ProPlan.annual,
          expiresAt: renewsAt,
          willRenew: false,
        ),
        serverPro: true,
      );
      await waitForText(tester,
          "Yearly plan · Ends ${formatDateMed(renewsAt, 'en')}, won't renew");
      expectNoStorefront();
    });

    testWidgets('the server tier alone is enough (Pro bought on web)',
        (tester) async {
      await pumpSubscriber(tester, serverPro: true);
      await waitForText(tester, "You're on Pro");

      expect(
        find.text('Your Pro benefits are active. Thanks for supporting the app.'),
        findsOneWidget,
      );
      expectNoStorefront();
    });

    testWidgets('a free user still gets the storefront', (tester) async {
      await pumpSubscriber(tester, serverPro: false);
      await waitForText(tester, r'Subscribe to Pro — $79.99/year');

      expect(find.text("You're on Pro"), findsNothing);
    });

    testWidgets('a purchase turns the storefront into the subscriber state',
        (tester) async {
      final store = await pumpSubscriber(
        tester,
        purchaseResult: PurchaseResult.purchased,
        entitlementOnSuccess:
            ProEntitlement(plan: ProPlan.monthly, expiresAt: renewsAt),
        serverPro: false,
      );
      await waitForText(tester, r'Subscribe to Pro — $79.99/year');

      await tester.tap(find.text(r'Monthly — $9.99/month'));
      await tester.pump();
      await tester.tap(
          find.widgetWithIcon(ListTile, Icons.workspace_premium_outlined));
      await waitForText(tester, "You're on Pro");

      expect(store.purchased, [ProPlan.monthly]);
      expectNoStorefront();
      // The webhook has not flipped the server tier yet: say so rather than
      // implying the benefits are already live.
      expect(
        find.text('Your purchase went through. Unlocking your Pro benefits '
            'on your account can take a minute.'),
        findsOneWidget,
      );
      // Let the welcome banner's auto-dismiss timer run out; the screen's
      // own server re-check timer is cancelled when the tree is disposed.
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('a restore that finds Pro shows the subscriber state',
        (tester) async {
      final store = await pumpSubscriber(
        tester,
        entitlementOnSuccess:
            ProEntitlement(plan: ProPlan.annual, expiresAt: renewsAt),
        serverPro: true,
      );
      await waitForText(tester, r'Subscribe to Pro — $79.99/year');

      await tester.tap(find.text('Restore purchases'));
      await waitForText(tester, "You're on Pro");

      expect(store.restores, 1);
      expect(
        find.text('Yearly plan · Renews ${formatDateMed(renewsAt, 'en')}'),
        findsOneWidget,
      );
      expectNoStorefront();
      // Let the restore banner's auto-dismiss timer run out.
      await tester.pump(const Duration(seconds: 4));
    });
  });
}

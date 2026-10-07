import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show PackageType;

import '../lib/revenuecat.dart';
import '../lib/store_links.dart';
import 'pro_plan_fixtures.dart';

void main() {
  setUpAll(() {
    // No env keys → wrapper reports unconfigured. Tests that need to
    // simulate the configured state pass a `keyOverride`.
    dotenv.loadFromString(isOptional: true);
  });

  tearDown(resetRevenueCatStateForTest);

  group('isRevenueCatConfigured', () {
    test('false when no platform key is in dotenv.env', () {
      expect(isRevenueCatConfigured(), isFalse);
    });

    test('true when keyOverride is non-empty', () {
      expect(
        isRevenueCatConfigured(keyOverride: 'rc_test_key'),
        isTrue,
      );
    });

    test('false when keyOverride is empty', () {
      expect(isRevenueCatConfigured(keyOverride: ''), isFalse);
    });
  });

  group('configureRevenueCat', () {
    test('returns false when no API key is provided', () async {
      final ok = await configureRevenueCat('user-1');
      expect(ok, isFalse);
    });

    test('keyOverride is honoured for tests', () async {
      // Without a key override, the wrapper has nothing to feed into
      // Purchases.configure. We can't actually init the SDK in a
      // headless test (no platform channel), so the path under test
      // here is: "given a key, the wrapper tries to configure and
      // surfaces the failure as false". An exception inside
      // Purchases.configure is swallowed and false is returned.
      final ok = await configureRevenueCat(
        'user-1',
        keyOverride: 'rc_test_key',
      );
      // Headless test → MissingPluginException inside Purchases →
      // wrapper catches and returns false. The contract under test is
      // "no crashes on a host-test runner".
      expect(ok, isFalse);
    });
  });

  group('startProCheckout', () {
    test('returns PurchaseResult.notConfigured when SDK has no API key',
        () async {
      final r = await startProCheckout('user-1', plan: ProPlan.annual);
      expect(r, PurchaseResult.notConfigured);
    });
  });

  group('pickProPackage', () {
    final both = proOfferings([proMonthlyPackage, proAnnualPackage]);

    test('the annual plan buys the annual package', () {
      expect(pickProPackage(both, ProPlan.annual), proAnnualPackage);
    });

    test('the monthly plan buys the monthly package', () {
      expect(pickProPackage(both, ProPlan.monthly), proMonthlyPackage);
    });

    test('never substitutes the other plan for a missing one', () {
      final monthlyOnly = proOfferings([proMonthlyPackage]);
      expect(pickProPackage(monthlyOnly, ProPlan.annual), isNull);
      expect(pickProPackage(monthlyOnly, ProPlan.monthly), proMonthlyPackage);
    });

    test('no current offering buys nothing', () {
      expect(pickProPackage(proOfferings(const []), ProPlan.monthly), isNull);
    });
  });

  group('proPlanOptions', () {
    test('both plans: annual is listed first and is the default', () {
      final options =
          proPlanOptions(proOfferings([proMonthlyPackage, proAnnualPackage]));
      expect(options.plans, [ProPlan.annual, ProPlan.monthly]);
      expect(options.defaultPlan, ProPlan.annual);
      expect(options.savingPercent, 33);
    });

    test('a single package is the only plan, with no saving to state', () {
      final options = proPlanOptions(proOfferings([proMonthlyPackage]));
      expect(options.plans, [ProPlan.monthly]);
      expect(options.defaultPlan, ProPlan.monthly);
      expect(options.savingPercent, isNull);
    });

    test('custom-typed packages are recognised by identifier', () {
      final monthly = proPackage('pro_monthly', PackageType.custom,
          price: 9.99, priceString: r'$9.99');
      final yearly = proPackage('pro_yearly', PackageType.custom,
          price: 79.99, priceString: r'$79.99');
      final options = proPlanOptions(proOfferings([yearly, monthly]));
      expect(options.monthly, monthly);
      expect(options.annual, yearly);
    });

    test('an unrecognisable single package is sold as the monthly plan', () {
      final odd = proPackage('pro', PackageType.custom,
          price: 9.99, priceString: r'$9.99');
      final options = proPlanOptions(proOfferings([odd]));
      expect(options.plans, [ProPlan.monthly]);
      expect(options.monthly, odd);
    });

    test('no packages means no plans', () {
      final options = proPlanOptions(proOfferings(const []));
      expect(options.plans, isEmpty);
      expect(options.defaultPlan, isNull);
    });

    test('no saving is stated across two currencies', () {
      final eurAnnual = proPackage(r'$rc_annual', PackageType.annual,
          price: 79.99, priceString: '79,99 €', currencyCode: 'EUR');
      final options =
          proPlanOptions(proOfferings([proMonthlyPackage, eurAnnual]));
      expect(options.savingPercent, isNull);
    });
  });

  group('annualSavingPercent', () {
    test('rounds down so the saving is never overstated', () {
      // 1 - 79.99 / 119.88 = 33.27%.
      expect(annualSavingPercent(9.99, 79.99), 33);
      // 1 - 9,800 / 14,400 = 31.94%: rounding would claim 32.
      expect(annualSavingPercent(1200, 9800), 31);
    });

    test('an exact percentage is not floored below itself', () {
      expect(annualSavingPercent(10, 90), 25);
      expect(annualSavingPercent(10, 60), 50);
    });

    test('no saving when the year costs as much as twelve months or more', () {
      expect(annualSavingPercent(9.99, 119.88), isNull);
      expect(annualSavingPercent(9.99, 130), isNull);
    });

    test('a saving under one percent is not stated', () {
      expect(annualSavingPercent(10, 119.5), isNull);
    });

    test('a zero or negative price states nothing', () {
      expect(annualSavingPercent(0, 79.99), isNull);
      expect(annualSavingPercent(9.99, 0), isNull);
    });
  });

  group('loadProPlans', () {
    test('returns null when SDK has no API key', () async {
      // Unconfigured build: the Pro tile falls back to the $9.99 USD list
      // price + regional note.
      expect(await loadProPlans('user-1'), isNull);
    });
  });

  group('managementUrl', () {
    test('returns null when SDK has no API key', () async {
      final url = await managementUrl('user-1');
      expect(url, isNull);
    });
  });

  group('resolveManageSubscriptionUrl', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('falls back to the web page on Android when the SDK has no key',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(await resolveManageSubscriptionUrl('user-1'), webUpgradeUrl);
    });

    test('falls back to Apple, not the page that sells Pro, on iOS',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(
        await resolveManageSubscriptionUrl('user-1'),
        appleSubscriptionsUrl,
      );
    });

    test('a signed-out caller gets the fallback without reaching the SDK',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(
        await resolveManageSubscriptionUrl(null, keyOverride: 'rc_test_key'),
        appleSubscriptionsUrl,
      );
    });
  });
}

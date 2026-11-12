import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/store_links.dart';

/// Pins the iOS payment-link rule (decisions § 1700): an iOS build never
/// hands anyone to the web page that sells Pro, and its "manage
/// subscription" fallback is Apple's page. Android keeps the web page.
void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    dotenv.clean();
  });

  test('iOS may not link to a web payment page', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(webPaymentLinksAllowed(), isFalse);
  });

  test('iOS falls back to Apple subscription management', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(manageSubscriptionFallbackUrl(), appleSubscriptionsUrl);
  });

  test('Android keeps the web upgrade page for both', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(webPaymentLinksAllowed(), isTrue);
    expect(manageSubscriptionFallbackUrl(), webUpgradeUrl());
  });

  test('the upgrade page follows the build\'s web origin, not production',
      () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    dotenv.loadFromString(
      envString: 'WEB_BASE_URL=https://preview.threkir.com/',
    );
    expect(webUpgradeUrl(), 'https://preview.threkir.com/settings/upgrade');
    expect(manageSubscriptionFallbackUrl(),
        'https://preview.threkir.com/settings/upgrade');
  });

  test('the upgrade page falls back to production when no origin is set', () {
    expect(webUpgradeUrl(), 'https://threkir.com/settings/upgrade');
  });
}

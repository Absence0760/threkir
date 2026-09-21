import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/store_links.dart';

/// Pins the iOS payment-link rule (decisions § 1700): an iOS build never
/// hands anyone to the web page that sells Pro, and its "manage
/// subscription" fallback is Apple's page. Android keeps the web page.
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

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
    expect(manageSubscriptionFallbackUrl(), webUpgradeUrl);
  });
}

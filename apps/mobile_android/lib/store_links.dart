import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

import 'web_base_url.dart';

/// The web page that sells Pro and takes donations to Threkir itself, on the
/// build's configured origin so a preview build never sends anyone to
/// production's checkout.
String webUpgradeUrl({String? webBase}) =>
    webPageUrl('/settings/upgrade', override: webBase);

/// Apple's own subscription-management page. It sells nothing, so it is where
/// iOS goes wherever Android falls back to [webUpgradeUrl].
const String appleSubscriptionsUrl =
    'https://apps.apple.com/account/subscriptions';

/// Whether this build may send someone to a web page that takes payment for a
/// digital good: the Pro subscription, or a donation to Threkir.
///
/// False on iOS. App Review Guideline 3.1.1 requires both to go through
/// In-App Purchase, and links out to another way of paying for them are
/// rejected outside the US storefront (decisions § 1700). Charity fundraisers
/// and paid in-person club events are a different category — 3.2.2(iv) and
/// 3.1.3(e) send those to the web — and are not gated here.
///
/// Reads [defaultTargetPlatform] rather than `Platform.isIOS` so a widget test
/// can drive the iOS branch with `debugDefaultTargetPlatformOverride`.
bool webPaymentLinksAllowed() => defaultTargetPlatform != TargetPlatform.iOS;

/// Where "manage subscription" opens when the store SDK has no management URL
/// of its own for this user.
String manageSubscriptionFallbackUrl() =>
    webPaymentLinksAllowed() ? webUpgradeUrl() : appleSubscriptionsUrl;

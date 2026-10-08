import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'store_links.dart';

/// RevenueCat native-SDK wrapper for the in-app Pro purchase sheet. Its web
/// counterpart under `billing/` drives a different SDK against a different
/// store, so the two are NOT a lockstep parity pair and neither registry
/// carries them; what they share is the not-configured sentinel contract
/// below. The wrapper has three jobs:
///
/// 1. **Stay compilable on unconfigured builds.** When the platform-
///    appropriate API key isn't in `dotenv.env`, every entry point
///    returns a "not configured" sentinel (`false` / `null` / a
///    [PurchaseResult.notConfigured]). The native SDK is never
///    initialised, so dev / CI builds work without a RevenueCat
///    account.
/// 2. **Be idempotent.** [configureRevenueCat] is safe to call
///    multiple times — it's a no-op when the SDK is already
///    configured for the same user.
/// 3. **Treat user-cancelled purchases as benign.** Tapping
///    "X / cancel" on the RC sheet throws a platform exception; the
///    wrapper maps that to a [PurchaseResult.cancelled] so callers
///    don't surface a red error toast for a normal dismissal.
///
/// The native SDK flips `subscription_tier` server-side via the
/// `revenuecat-webhook` Edge Function, so callers typically refetch
/// `ApiClient.fetchMyProfile()` a couple of seconds after a
/// successful purchase.

/// Env keys read at startup. Mirror the names the deploy pipeline
/// expects; documented in `docs/features/paywall.md` and the deploy plan.
const _kAndroidKey = 'REVENUECAT_API_KEY_ANDROID';
const _kIosKey = 'REVENUECAT_API_KEY_IOS';

@visibleForTesting
String envApiKey() {
  if (Platform.isAndroid) return dotenv.env[_kAndroidKey] ?? '';
  if (Platform.isIOS) return dotenv.env[_kIosKey] ?? '';
  // Desktop / web (unsupported targets here) — never configured.
  return '';
}

/// True when the running build has a platform-appropriate
/// RevenueCat API key in `dotenv.env`. Tests can pass a [keyOverride]
/// to assert against a known value; the other helpers also accept the
/// override so a configured-state test never has to fake `Platform`.
bool isRevenueCatConfigured({String? keyOverride}) {
  final key = keyOverride ?? envApiKey();
  return key.isNotEmpty;
}

bool _configured = false;
String? _configuredUserId;

/// Idempotently configure the native SDK for [userId]. Re-configures
/// when the user changes so tokens don't leak across sign-outs.
/// Returns `false` when no API key is available — caller falls
/// through to the web URL where [webPaymentLinksAllowed] permits one.
Future<bool> configureRevenueCat(
  String userId, {
  String? keyOverride,
}) async {
  final key = keyOverride ?? envApiKey();
  if (key.isEmpty) return false;
  if (_configured && _configuredUserId == userId) return true;
  try {
    final config = PurchasesConfiguration(key)..appUserID = userId;
    await Purchases.configure(config);
    _configured = true;
    _configuredUserId = userId;
    return true;
  } catch (e) {
    debugPrint('RevenueCat configure failed: $e');
    return false;
  }
}

/// Outcome of [startProCheckout]. Distinguishes "purchase went
/// through" from "user cancelled" (benign) from "RC isn't configured
/// on this build" (caller falls through to the web URL where
/// [webPaymentLinksAllowed] permits one).
enum PurchaseResult { purchased, cancelled, notConfigured, failed }

/// The two Pro billing periods the `default` offering sells:
/// `$rc_monthly` (product `pro_monthly`) and `$rc_annual` (product
/// `pro_annual`), both granting the `pro` entitlement.
enum ProPlan { monthly, annual }

/// The Pro packages the current offering carries, keyed by [ProPlan].
/// Either side may be missing: the screen offers only the plans that are
/// here, so a purchase can never target a package the buyer was not shown.
class ProPlanOptions {
  const ProPlanOptions({this.monthly, this.annual});

  final Package? monthly;
  final Package? annual;

  Package? packageFor(ProPlan plan) =>
      plan == ProPlan.annual ? annual : monthly;

  /// Annual first: it is the plan the screen recommends.
  List<ProPlan> get plans => [
        if (annual != null) ProPlan.annual,
        if (monthly != null) ProPlan.monthly,
      ];

  ProPlan? get defaultPlan => plans.isEmpty ? null : plans.first;

  /// Whole percent the annual plan saves over twelve monthly payments, from
  /// the two store prices, or null when either side is missing or the two
  /// are priced in different currencies.
  int? get savingPercent {
    final m = monthly?.storeProduct;
    final a = annual?.storeProduct;
    if (m == null || a == null || m.currencyCode != a.currencyCode) {
      return null;
    }
    return annualSavingPercent(m.price, a.price);
  }
}

/// Percent saved by paying [annualPrice] once instead of [monthlyPrice]
/// twelve times, rounded DOWN so the copy never overstates the saving.
/// Null when there is no saving of at least 1% to state.
int? annualSavingPercent(double monthlyPrice, double annualPrice) {
  if (monthlyPrice <= 0 || annualPrice <= 0) return null;
  final yearOfMonths = monthlyPrice * 12;
  if (annualPrice >= yearOfMonths) return null;
  // The epsilon keeps binary rounding from flooring an exact 25.0 to 24.
  final percent =
      ((yearOfMonths - annualPrice) / yearOfMonths * 100 + 1e-9).floor();
  return percent >= 1 ? percent : null;
}

Package? _packageMatching(
  List<Package> packages,
  PackageType type,
  RegExp identifier,
) {
  for (final p in packages) {
    if (p.packageType == type) return p;
  }
  for (final p in packages) {
    if (identifier.hasMatch(p.identifier)) return p;
  }
  return null;
}

/// Sort the current offering's packages into plans: by RevenueCat's
/// package type first, then by identifier. An offering whose packages are
/// neither keeps the pre-annual behaviour of selling its first package as
/// the monthly plan.
ProPlanOptions proPlanOptions(Offerings offerings) {
  final packages = offerings.current?.availablePackages ?? const <Package>[];
  if (packages.isEmpty) return const ProPlanOptions();
  final monthly = _packageMatching(packages, PackageType.monthly,
      RegExp(r'monthly|month', caseSensitive: false));
  final annual = _packageMatching(packages, PackageType.annual,
      RegExp(r'annual|year', caseSensitive: false));
  if (monthly == null && annual == null) {
    return ProPlanOptions(monthly: packages.first);
  }
  return ProPlanOptions(monthly: monthly, annual: annual);
}

/// The package [startProCheckout] buys for [plan], or null when the
/// offering does not carry that plan. Deliberately no cross-plan fallback:
/// silently buying a year when the buyer chose a month is worse than a
/// failed purchase.
@visibleForTesting
Package? pickProPackage(Offerings offerings, ProPlan plan) =>
    proPlanOptions(offerings).packageFor(plan);

/// Present the native Pro checkout sheet for [userId], buying [plan].
Future<PurchaseResult> startProCheckout(
  String userId, {
  required ProPlan plan,
  String? keyOverride,
}) async {
  if (!await configureRevenueCat(userId, keyOverride: keyOverride)) {
    return PurchaseResult.notConfigured;
  }
  try {
    final offerings = await Purchases.getOfferings();
    final pkg = pickProPackage(offerings, plan);
    if (pkg == null) {
      debugPrint('RevenueCat: no Pro ${plan.name} package available');
      return PurchaseResult.failed;
    }
    await Purchases.purchase(PurchaseParams.package(pkg));
    return PurchaseResult.purchased;
  } on PlatformException catch (e) {
    final code = PurchasesErrorHelper.getErrorCode(e);
    if (code == PurchasesErrorCode.purchaseCancelledError) {
      return PurchaseResult.cancelled;
    }
    debugPrint('RevenueCat purchase failed: $code / ${e.message}');
    return PurchaseResult.failed;
  } catch (e) {
    debugPrint('RevenueCat purchase failed: $e');
    return PurchaseResult.failed;
  }
}

/// The Pro plans the current offering sells for [userId], each carrying its
/// store-localised price. Null when the SDK isn't configured or the offering
/// can't be fetched: the screen then falls back to the USD list price.
/// Apple Guideline 3.1.1 + Play subscription policy require the displayed
/// price to come from the store, since it varies by territory.
Future<ProPlanOptions?> loadProPlans(
  String userId, {
  String? keyOverride,
}) async {
  if (!await configureRevenueCat(userId, keyOverride: keyOverride)) {
    return null;
  }
  try {
    final options = proPlanOptions(await Purchases.getOfferings());
    return options.plans.isEmpty ? null : options;
  } catch (e) {
    debugPrint('RevenueCat offerings fetch failed: $e');
    return null;
  }
}

/// The store operations the Pro screen drives. [RevenueCatProStore] is the
/// live one; widget tests substitute a fake, since the native SDK has no
/// host-test platform channel.
abstract class ProStore {
  bool get configured;
  Future<ProPlanOptions?> loadPlans();
  Future<PurchaseResult> purchase(ProPlan plan);
}

class RevenueCatProStore implements ProStore {
  const RevenueCatProStore(this.currentUserId);

  /// Read lazily so an unconfigured build never touches the auth client.
  final String? Function() currentUserId;

  @override
  bool get configured => isRevenueCatConfigured();

  @override
  Future<ProPlanOptions?> loadPlans() async {
    if (!configured) return null;
    final userId = currentUserId();
    if (userId == null) return null;
    return loadProPlans(userId);
  }

  @override
  Future<PurchaseResult> purchase(ProPlan plan) async {
    final userId = configured ? currentUserId() : null;
    if (userId == null) return PurchaseResult.notConfigured;
    return startProCheckout(userId, plan: plan);
  }
}

/// Restore purchases — drives RC's restore flow so a user who has
/// already paid (different install, different device, switched
/// store account) gets their entitlements back. Required by Apple
/// App Store Review Guideline 3.1.1 + Play subscription policy:
/// every subscription app must surface a "Restore purchases"
/// button. audit/app-store-privacy (May 2026).
Future<PurchaseResult> restorePurchases(
  String userId, {
  String? keyOverride,
}) async {
  if (!await configureRevenueCat(userId, keyOverride: keyOverride)) {
    return PurchaseResult.notConfigured;
  }
  try {
    final info = await Purchases.restorePurchases();
    // RC restorePurchases returns the latest CustomerInfo. Distinguish
    // "found an active entitlement" from "no entitlement to restore"
    // so the UI can show the right message — both are legitimate
    // outcomes; only the former is a success.
    final hasActive = info.entitlements.active.isNotEmpty;
    return hasActive
        ? PurchaseResult.purchased
        : PurchaseResult.cancelled; // "nothing to restore" — benign
  } catch (e) {
    debugPrint('RevenueCat restorePurchases failed: $e');
    return PurchaseResult.failed;
  }
}

/// Subscription-management URL — RC's hosted portal where the user
/// can change card / cancel. Returns null when the SDK isn't
/// configured or the user has no active subscription.
Future<String?> managementUrl(
  String userId, {
  String? keyOverride,
}) async {
  if (!await configureRevenueCat(userId, keyOverride: keyOverride)) {
    return null;
  }
  try {
    final info = await Purchases.getCustomerInfo();
    return info.managementURL;
  } catch (e) {
    debugPrint('RevenueCat managementUrl failed: $e');
    return null;
  }
}

/// Where "manage subscription" should open for [userId]: the page of the
/// store the subscription was actually bought through when the SDK knows it,
/// else the platform fallback — which on iOS is Apple's page, never the web
/// page that sells Pro.
Future<String> resolveManageSubscriptionUrl(
  String? userId, {
  String? keyOverride,
}) async {
  if (userId != null && isRevenueCatConfigured(keyOverride: keyOverride)) {
    final url = await managementUrl(userId, keyOverride: keyOverride);
    if (url != null) return url;
  }
  return manageSubscriptionFallbackUrl();
}

/// Test-only reset — clears the cached configuration so a second test
/// run sees `isConfigured == false` again.
@visibleForTesting
void resetRevenueCatStateForTest() {
  _configured = false;
  _configuredUserId = null;
}

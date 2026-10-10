import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Whether the running deploy actually has a Pro perk to deliver.
///
/// Web decides this from its own env — `proSellable = coachEnabled() ||
/// routeGenEnabled()` in `settings/upgrade/+page.svelte` — and shows a
/// "coming soon" teaser instead of a purchase CTA when both are off. A
/// Flutter binary has no server-rendered env, so it reads the same two
/// flags from `/app-capabilities.json`, the manifest the web build
/// prerenders from those same gate functions (decisions §466).
///
/// Every failure path resolves to [ProPerks.none]: unreachable host,
/// timeout, non-200, malformed body, a missing or non-boolean field. A
/// client that cannot establish that a perk is live must not take a
/// payment, so "unknown" and "nothing live" are deliberately the same
/// answer.
class ProPerks {
  /// The AI Coach is live on this deploy (web's `PUBLIC_COACH_ENABLED`).
  final bool coach;

  /// Server-side route generation is live (web's `PUBLIC_ROUTE_GEN_ENABLED`).
  final bool routeGen;

  /// The web deploy can take a Pro payment (`webCheckoutAvailable()` on web).
  /// Not a perk: it decides only whether the web page is somewhere to send a
  /// buyer this build cannot sell to itself (decisions § 1826).
  final bool webCheckout;

  const ProPerks({
    required this.coach,
    required this.routeGen,
    this.webCheckout = false,
  });

  static const ProPerks none = ProPerks(coach: false, routeGen: false);

  bool get sellable => coach || routeGen;
}

/// Whether this build can offer Pro for sale right now: a perk must be live,
/// and there must be somewhere to pay — the store SDK, or a web checkout this
/// platform may link to that the web deploy actually has. Without the last
/// condition an Android build with no RevenueCat key sent buyers to a web
/// page that could only point them at the iPhone app (decisions § 1826).
bool proPurchasable(
  ProPerks? perks, {
  required bool storeConfigured,
  required bool webLinksAllowed,
}) {
  if (perks == null || !perks.sellable) return false;
  return storeConfigured || (webLinksAllowed && perks.webCheckout);
}

/// Give up rather than hang the Pro screen on a dead network. The screen
/// renders the teaser until this resolves, so a slow answer costs the user
/// nothing but a late-appearing purchase tile.
const Duration kProPerksTimeout = Duration(seconds: 6);

/// Parse the manifest body. Anything that isn't a JSON object with an
/// explicit `true` under a known key reads as off.
@visibleForTesting
ProPerks parseProPerks(String raw) {
  try {
    final json = jsonDecode(raw);
    if (json is! Map) return ProPerks.none;
    return ProPerks(
      coach: json['coach'] == true,
      routeGen: json['route_gen'] == true,
      webCheckout: json['web_checkout'] == true,
    );
  } catch (_) {
    return ProPerks.none;
  }
}

/// Base URL of the web deploy this build belongs to, matching the
/// resolution in `route_describe_client.dart` and `coach_screen.dart`.
String _webBase() =>
    ((dotenv.isInitialized ? dotenv.maybeGet('WEB_BASE_URL') : null) ??
            'https://threkir.com')
        .replaceAll(RegExp(r'/$'), '');

/// Fetch the deploy's live-perk manifest. Never throws.
Future<ProPerks> fetchProPerks() async {
  final uri = Uri.parse('${_webBase()}/app-capabilities.json');
  final client = HttpClient()..connectionTimeout = kProPerksTimeout;
  try {
    final req = await client.getUrl(uri).timeout(kProPerksTimeout);
    final res = await req.close().timeout(kProPerksTimeout);
    final body =
        await res.transform(utf8.decoder).join().timeout(kProPerksTimeout);
    if (res.statusCode != 200) return ProPerks.none;
    return parseProPerks(body);
  } catch (e) {
    debugPrint('pro_sellable: capability fetch failed: $e');
    return ProPerks.none;
  } finally {
    client.close(force: true);
  }
}

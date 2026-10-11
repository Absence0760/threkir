import 'package:flutter_test/flutter_test.dart';

import '../lib/pro_sellable.dart';

/// The mobile half of the hollow-subscription gate (decisions §466). Every
/// unreadable answer must resolve to "nothing live" — a client that cannot
/// establish a perk is live must not take a payment.
void main() {
  group('parseProPerks', () {
    test('reads both flags off the manifest', () {
      final p = parseProPerks('{"coach":true,"route_gen":false}');
      expect(p.coach, isTrue);
      expect(p.routeGen, isFalse);
      expect(p.sellable, isTrue);
    });

    test('sellable when either perk is live, not when neither is', () {
      expect(parseProPerks('{"coach":false,"route_gen":true}').sellable, isTrue);
      expect(parseProPerks('{"coach":true,"route_gen":true}').sellable, isTrue);
      expect(
          parseProPerks('{"coach":false,"route_gen":false}').sellable, isFalse);
    });

    test('missing keys read as off', () {
      final p = parseProPerks('{}');
      expect(p.coach, isFalse);
      expect(p.routeGen, isFalse);
      expect(p.sellable, isFalse);
    });

    test('non-boolean truthy values read as off', () {
      // A string "true", 1, or a nested object must not sell a subscription.
      expect(parseProPerks('{"coach":"true"}').sellable, isFalse);
      expect(parseProPerks('{"coach":1}').sellable, isFalse);
      expect(parseProPerks('{"route_gen":{"on":true}}').sellable, isFalse);
    });

    test('malformed, empty, and non-object bodies read as off', () {
      for (final body in ['', 'not json', '<html>404</html>', '[true]', 'true', 'null']) {
        expect(parseProPerks(body).sellable, isFalse, reason: 'body: $body');
      }
    });

    test('reads web_checkout, fail-closed like the perks', () {
      expect(parseProPerks('{"coach":true,"web_checkout":true}').webCheckout,
          isTrue);
      expect(parseProPerks('{"coach":true,"web_checkout":false}').webCheckout,
          isFalse);
      // An older web build emits no field: no web checkout.
      expect(parseProPerks('{"coach":true}').webCheckout, isFalse);
      expect(parseProPerks('{"web_checkout":"true"}').webCheckout, isFalse);
      expect(parseProPerks('{"web_checkout":1}').webCheckout, isFalse);
      expect(parseProPerks('{"webCheckout":true}').webCheckout, isFalse);
      // Web checkout is somewhere to pay, not a perk: it sells nothing alone.
      expect(parseProPerks('{"web_checkout":true}').sellable, isFalse);
    });

    test('a snake_case-only contract — camelCase does not enable selling', () {
      // The web manifest emits `route_gen`; accepting `routeGen` too would
      // let a drifted server shape silently re-enable the storefront.
      expect(parseProPerks('{"routeGen":true}').sellable, isFalse);
    });
  });

  test('ProPerks.none is the fail-closed default', () {
    expect(ProPerks.none.coach, isFalse);
    expect(ProPerks.none.routeGen, isFalse);
    expect(ProPerks.none.webCheckout, isFalse);
    expect(ProPerks.none.sellable, isFalse);
  });

  group('proPurchasable', () {
    const coachOnly = ProPerks(coach: true, routeGen: false);
    const coachAndWeb = ProPerks(coach: true, routeGen: false, webCheckout: true);

    test('unknown or no live perk is never purchasable', () {
      for (final store in [true, false]) {
        for (final web in [true, false]) {
          expect(
              proPurchasable(null, storeConfigured: store, webLinksAllowed: web),
              isFalse);
          expect(
              proPurchasable(
                  const ProPerks(coach: false, routeGen: false, webCheckout: true),
                  storeConfigured: store,
                  webLinksAllowed: web),
              isFalse);
        }
      }
    });

    test('a configured store sells whatever the web checkout', () {
      // iOS with the RevenueCat key: In-App Purchase, web irrelevant.
      expect(
          proPurchasable(coachOnly, storeConfigured: true, webLinksAllowed: false),
          isTrue);
      expect(
          proPurchasable(coachOnly, storeConfigured: true, webLinksAllowed: true),
          isTrue);
    });

    test('without the store, only a live web checkout this platform may link to sells', () {
      // Android with no RevenueCat key and no web checkout: the dead end
      // decisions § 1826 closes.
      expect(
          proPurchasable(coachOnly, storeConfigured: false, webLinksAllowed: true),
          isFalse);
      expect(
          proPurchasable(coachAndWeb, storeConfigured: false, webLinksAllowed: true),
          isTrue);
      // iOS may never link out to pay (decisions § 1700).
      expect(
          proPurchasable(coachAndWeb,
              storeConfigured: false, webLinksAllowed: false),
          isFalse);
    });
  });
}

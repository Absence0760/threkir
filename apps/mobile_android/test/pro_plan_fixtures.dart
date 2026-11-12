import 'package:purchases_flutter/purchases_flutter.dart'
    show
        Offering,
        Offerings,
        Package,
        PackageType,
        PresentedOfferingContext,
        StoreProduct;

Package proPackage(
  String identifier,
  PackageType type, {
  required double price,
  required String priceString,
  String productId = 'pro_monthly',
  String currencyCode = 'USD',
}) =>
    Package(
      identifier,
      type,
      StoreProduct(productId, 'Pro', 'Pro', price, priceString, currencyCode),
      const PresentedOfferingContext('default', null, null),
    );

final Package proMonthlyPackage = proPackage(
  r'$rc_monthly',
  PackageType.monthly,
  price: 9.99,
  priceString: r'$9.99',
);

final Package proAnnualPackage = proPackage(
  r'$rc_annual',
  PackageType.annual,
  productId: 'pro_annual',
  price: 79.99,
  priceString: r'$79.99',
);

Offerings proOfferings(List<Package> packages) => Offerings(
      {'default': Offering('default', 'Pro', const {}, packages)},
      current: Offering('default', 'Pro', const {}, packages),
    );

import 'package:integration_test/integration_test_driver.dart';

// Host-side entry for `flutter drive`, the only runner that builds these
// suites in --profile (AOT, assertions off). `flutter test integration_test`
// needs no driver but always builds debug, which is the one mode a device
// pass must not stop at. The file is not named `*_test.dart`, so
// `flutter test integration_test` never loads it as a suite.
Future<void> main() => integrationDriver();

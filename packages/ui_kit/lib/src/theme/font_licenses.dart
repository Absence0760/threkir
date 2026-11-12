import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds the bundled Manrope's SIL Open Font License to the app's licence page.
///
/// OFL 1.1 lets the font ship inside the app on condition that its licence
/// travels with it; [LicenseRegistry] is where Flutter's own "Licences"
/// screen reads from. Call once, before `runApp`.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('packages/ui_kit/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['Manrope'], text);
  });
}

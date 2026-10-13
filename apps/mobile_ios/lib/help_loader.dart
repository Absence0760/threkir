import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'help_guides.dart';
import 'l10n/locale_support.dart';

/// Where `scripts/gen_help_guides.mjs` writes the guides in [localeTag]: one
/// file per app locale, each guide already translated or, where it has no
/// translation, in English with `lang: "en"`.
String helpGuidesAsset(String localeTag) => 'assets/help/guides.$localeTag.json';

/// The asset tag for the app locale [locale] (`de`, `pt-PT`, `pt-BR`).
String helpLocaleTag(Locale locale) =>
    localeToTag(negotiateLocale(localeToTag(locale), const []));

Future<HelpLibrary?> _read(AssetBundle bundle, String asset) async {
  try {
    final library = HelpLibrary.parse(await bundle.loadString(asset));
    if (library == null) debugPrint('help: $asset is not a guide array');
    return library;
  } catch (e) {
    debugPrint('help: could not load $asset: $e');
    return null;
  }
}

/// Reads the guides in [localeTag] from the asset bundle, falling back to the
/// English file when that locale's is missing, unreadable or empty. Null when
/// English fails too — the Help screens show an "unavailable" state with a
/// retry for that, and nothing else in the app is affected.
Future<HelpLibrary?> loadHelpLibraryFromAssets({
  AssetBundle? bundle,
  String localeTag = 'en',
}) async {
  final source = bundle ?? rootBundle;
  if (localeTag != 'en') {
    final library = await _read(source, helpGuidesAsset(localeTag));
    if (library != null && library.guides.isNotEmpty) return library;
  }
  return _read(source, helpGuidesAsset('en'));
}

final Map<String, Future<HelpLibrary?>> _cached = {};

/// The guides in [localeTag], read once per process and locale. A failed
/// read is not cached, so the screen's retry reads the asset again.
Future<HelpLibrary?> loadHelpLibraryCached(String localeTag) {
  final pending = _cached[localeTag] ??= loadHelpLibraryFromAssets(
    localeTag: localeTag,
  );
  return pending.then((library) {
    if (library == null && identical(_cached[localeTag], pending)) {
      _cached.remove(localeTag);
    }
    return library;
  });
}

/// The loader every Help screen calls with the app's locale tag. A seam so a
/// widget test can hand the screens a fixture without registering the
/// generated assets.
Future<HelpLibrary?> Function(String localeTag) helpLibraryLoader =
    loadHelpLibraryCached;

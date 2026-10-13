import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'help_guides.dart';

/// Where `scripts/gen_help_guides.mjs` writes the guides for this app.
const helpGuidesAsset = 'assets/help/guides.en.json';

/// Reads the guides from the asset bundle. Null when the asset is missing,
/// unreadable or not a guide array — the Help screens show an "unavailable"
/// state with a retry for that, and nothing else in the app is affected.
Future<HelpLibrary?> loadHelpLibraryFromAssets({AssetBundle? bundle}) async {
  try {
    final raw = await (bundle ?? rootBundle).loadString(helpGuidesAsset);
    final library = HelpLibrary.parse(raw);
    if (library == null) {
      debugPrint('help: $helpGuidesAsset is not a guide array');
    }
    return library;
  } catch (e) {
    debugPrint('help: could not load $helpGuidesAsset: $e');
    return null;
  }
}

Future<HelpLibrary?>? _cached;

/// The guides, read once per process. A failed read is not cached, so the
/// screen's retry reads the asset again.
Future<HelpLibrary?> loadHelpLibraryCached() {
  final pending = _cached ??= loadHelpLibraryFromAssets();
  return pending.then((library) {
    if (library == null && identical(_cached, pending)) _cached = null;
    return library;
  });
}

/// The loader every Help screen calls. A seam so a widget test can hand the
/// screens a fixture without registering the generated asset.
Future<HelpLibrary?> Function() helpLibraryLoader = loadHelpLibraryCached;

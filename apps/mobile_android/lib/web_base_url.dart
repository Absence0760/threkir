import 'package:flutter_dotenv/flutter_dotenv.dart';

const kDefaultWebBaseUrl = 'https://threkir.com';

/// The web origin a phone surface links or posts to, with no trailing slash.
///
/// [override] wins, then `WEB_BASE_URL` from dotenv, then production. An
/// unloaded dotenv and a blank value both fall back rather than throwing or
/// producing a relative URL: `dotenv.env` throws before `dotenv.load`, and a
/// build that sets `WEB_BASE_URL=` would otherwise send requests to `/api/…`.
String resolveWebBaseUrl({String? override}) {
  var base =
      (override ??
              (dotenv.isInitialized ? dotenv.maybeGet('WEB_BASE_URL') : null) ??
              '')
          .trim();
  if (base.isEmpty) base = kDefaultWebBaseUrl;
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  return base;
}

/// [path] (which starts with `/`) on the configured web origin.
String webPageUrl(String path, {String? override}) =>
    '${resolveWebBaseUrl(override: override)}$path';

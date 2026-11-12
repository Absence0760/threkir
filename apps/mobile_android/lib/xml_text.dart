/// Text for an XML document the app writes (GPX, KML).
///
/// The five reserved characters are escaped, with the apostrophe as the
/// numeric `&#39;` so the bytes match the web's `escapeXml`
/// (`util/html_escape.ts`, decisions § 1450). Code points XML 1.0 cannot
/// carry at all — C0 controls other than tab / LF / CR, lone surrogates,
/// U+FFFE / U+FFFF — become U+FFFD first: no entity spells them, so one in a
/// route name made every reader refuse the whole file.
String escapeXmlText(String str) {
  final out = StringBuffer();
  for (final r in str.runes) {
    final legal = r == 0x9 ||
        r == 0xA ||
        r == 0xD ||
        (r >= 0x20 && r <= 0xD7FF) ||
        (r >= 0xE000 && r <= 0xFFFD) ||
        (r >= 0x10000 && r <= 0x10FFFF);
    out.writeCharCode(legal ? r : 0xFFFD);
  }
  return out
      .toString()
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

import 'package:flutter_test/flutter_test.dart';
import '../lib/xml_text.dart';

// Mirrors the escapeXml cases in apps/web/src/lib/util/html_escape.test.ts:
// a GPX or KML file exported from either client must carry the same bytes.
// XML 1.0's Char production: #x9 | #xA | #xD | [#x20-#xD7FF] |
// [#xE000-#xFFFD] | [#x10000-#x10FFFF]; each edge is checked.
void main() {
  String ch(int codePoint) => String.fromCharCode(codePoint);

  test('replaces exactly the code points XML 1.0 cannot carry', () {
    const forbidden = [
      0x0000, 0x0008, 0x000B, 0x000C, 0x000E, 0x001F, //
      0xFFFE, 0xFFFF, 0xD800, 0xDFFF,
    ];
    for (final cp in forbidden) {
      expect(escapeXmlText('a${ch(cp)}b'), 'a�b',
          reason: 'U+${cp.toRadixString(16)} is not an XML 1.0 Char');
    }
    const legal = [
      0x0009, 0x000A, 0x000D, 0x0020, 0xD7FF, 0xE000, 0xFFFD, //
      0x10000, 0x10FFFF,
    ];
    for (final cp in legal) {
      expect(escapeXmlText('a${ch(cp)}b'), 'a${ch(cp)}b',
          reason: 'U+${cp.toRadixString(16)} is legal');
    }
  });

  test('escapes the five reserved characters, the apostrophe numerically', () {
    expect(escapeXmlText('<a href="x">\'&\'</a>'),
        '&lt;a href=&quot;x&quot;&gt;&#39;&amp;&#39;&lt;/a&gt;');
  });

  test('a surrogate pair is one legal character; an unpaired half is not', () {
    expect(escapeXmlText('\u{1F3D4}'), '\u{1F3D4}');
    expect(escapeXmlText('\uDFD4\uD83C'), '��');
  });

  test('escapes text that already looks escaped, once', () {
    expect(escapeXmlText('&lt;'), '&amp;lt;');
    expect(escapeXmlText('&#39;'), '&amp;#39;');
  });

  test('leaves plain text and an empty string alone', () {
    expect(escapeXmlText(''), '');
    expect(escapeXmlText('Morning loop 5K'), 'Morning loop 5K');
    expect(escapeXmlText('Côte d’Azur — 10 km'), 'Côte d’Azur — 10 km');
  });
}

// ignore_for_file: avoid_relative_lib_imports
// Mirrors apps/web/src/lib/social/dm_link.test.ts case-for-case.
import 'package:flutter_test/flutter_test.dart';

import '../lib/dm_link.dart';

void main() {
  test('a domain is the lower-cased host without www or port', () {
    expect(dmLinkDomain('https://www.Example.com/a?b#c'), 'example.com');
    expect(dmLinkDomain('http://sub.example.co.uk:8080/x'), 'sub.example.co.uk');
    expect(dmLinkDomain('HTTPS://EXAMPLE.ORG'), 'example.org');
  });

  test('anything that could pass for another domain stays text', () {
    expect(dmLinkDomain('https://google.com@evil.example/'), isNull);
    expect(dmLinkDomain('https://user:pw@example.com/'), isNull);
    expect(dmLinkDomain('https://xn--80ak6aa92e.com/'), 'xn--80ak6aa92e.com');
    expect(dmLinkDomain('https://аррӏе.com/'), isNull);
    expect(dmLinkDomain('javascript:alert(1)'), isNull);
    expect(dmLinkDomain('ftp://example.com'), isNull);
    expect(dmLinkDomain('https://localhost/'), isNull);
    expect(dmLinkDomain('https://example..com/'), isNull);
    expect(dmLinkDomain('https://.example.com/'), isNull);
  });

  test('text is cut into runs and links in order', () {
    expect(dmTextSegments('see https://example.com/route, then reply'), const [
      DmTextRun('see '),
      DmLink(
        'https://example.com/route',
        href: 'https://example.com/route',
        domain: 'example.com',
      ),
      DmTextRun(', then reply'),
    ]);
    expect(dmTextSegments('no links here'), const [DmTextRun('no links here')]);
    expect(dmTextSegments(''), isEmpty);
  });

  test('trailing punctuation and an unbalanced paren are not part of the link',
      () {
    final segs = dmTextSegments('(at https://example.com/a_(b)) ok.');
    expect(
      segs[1],
      const DmLink(
        'https://example.com/a_(b)',
        href: 'https://example.com/a_(b)',
        domain: 'example.com',
      ),
    );
    expect(dmTextSegments('Go: https://example.com!')[1].text,
        'https://example.com');
  });

  test('a refused URL stays inside the plain text', () {
    expect(dmTextSegments('x https://a@b.com y https://ok.example z'), const [
      DmTextRun('x https://a@b.com y '),
      DmLink('https://ok.example',
          href: 'https://ok.example', domain: 'ok.example'),
      DmTextRun(' z'),
    ]);
  });

  test('no markup survives as markup: segments are plain strings', () {
    final segs =
        dmTextSegments('<img src=x onerror=alert(1)> https://example.com/<b>');
    expect(segs[0], isA<DmTextRun>());
    expect((segs[1] as DmLink).href, 'https://example.com/');
  });

  test(
      'a link stops at the first non-ASCII character, so text with no spaces around it stays text',
      () {
    expect(dmTextSegments('https://example.com/route路線を見て'), const [
      DmLink('https://example.com/route',
          href: 'https://example.com/route', domain: 'example.com'),
      DmTextRun('路線を見て'),
    ]);
    expect(dmTextSegments('見て https://example.com。')[1].text,
        'https://example.com');
  });
}

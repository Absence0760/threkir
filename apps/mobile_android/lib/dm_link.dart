/// Links in a direct message (issue #1216). A link is drawn as its text plus
/// a chip naming its domain, worked out here from the text alone: nothing is
/// fetched, so there is no server-side request to aim at an internal address
/// and no request that tells a third party who opened the message.
///
/// Only an http(s) URL with an ASCII host and no user-info becomes a link. A
/// host in another script stays text, because a look-alike domain is the
/// phishing case a domain chip exists to expose, and `user@` before a host
/// is the old way of making one domain read as another. Web twin:
/// `apps/web/src/lib/social/dm_link.ts`.
library;

sealed class DmTextSegment {
  const DmTextSegment(this.text);
  final String text;
}

class DmTextRun extends DmTextSegment {
  const DmTextRun(super.text);

  @override
  bool operator ==(Object other) => other is DmTextRun && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'DmTextRun($text)';
}

class DmLink extends DmTextSegment {
  const DmLink(super.text, {required this.href, required this.domain});

  final String href;
  final String domain;

  @override
  bool operator ==(Object other) =>
      other is DmLink &&
      other.text == text &&
      other.href == href &&
      other.domain == domain;

  @override
  int get hashCode => Object.hash(text, href, domain);

  @override
  String toString() => 'DmLink($text, $domain)';
}

// The scheme's case is spelled out rather than matched case-insensitively:
// with unicode: true, an ignore-case class excluding U+0080 and up also
// excludes ASCII letters that fold to a non-ASCII one ('k' to the Kelvin sign).
final RegExp _urlRe = RegExp(
  r'''[Hh][Tt][Tt][Pp][Ss]?://[^\s<>"'`\u{80}-\u{10FFFF}]+''',
  unicode: true,
);
final RegExp _trailing = RegExp(r'''[.,;:!?'"\]}>]+$''');
final RegExp _asciiHost = RegExp(r'^[a-z0-9.-]+$');
final RegExp _authority = RegExp(r'^(https?)://([^/?#]*)', caseSensitive: false);
final RegExp _port = RegExp(r':\d*$');

String _trimTrailing(String candidate) {
  var url = candidate.replaceAll(_trailing, '');
  int count(String s, String ch) => ch.allMatches(s).length;
  while (url.endsWith(')') && count(url, '(') < count(url, ')')) {
    url = url.substring(0, url.length - 1).replaceAll(_trailing, '');
  }
  return url;
}

/// The domain a chip shows for [url], or null when it must stay text: not
/// http(s), user-info present, a host outside [a-z0-9.-], or no dot in it.
/// A leading `www.` is dropped.
String? dmLinkDomain(String url) {
  final m = _authority.firstMatch(url);
  if (m == null) return null;
  final authority = m.group(2)!;
  if (authority.contains('@')) return null;
  final host = authority.replaceAll(_port, '').toLowerCase();
  if (!_asciiHost.hasMatch(host) || !host.contains('.')) return null;
  if (host.startsWith('.') || host.endsWith('.') || host.contains('..')) {
    return null;
  }
  return host.startsWith('www.') ? host.substring(4) : host;
}

/// The message text cut into plain runs and links, in order.
List<DmTextSegment> dmTextSegments(String body) {
  final out = <DmTextSegment>[];
  var at = 0;
  for (final match in _urlRe.allMatches(body)) {
    final start = match.start;
    final url = _trimTrailing(match.group(0)!);
    final domain = dmLinkDomain(url);
    if (domain == null) continue;
    if (start > at) out.add(DmTextRun(body.substring(at, start)));
    out.add(DmLink(url, href: url, domain: domain));
    at = start + url.length;
  }
  if (at < body.length) out.add(DmTextRun(body.substring(at)));
  return out;
}

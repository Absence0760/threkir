/// Share-link attribution on the phone (decisions § 2268). A creator's own
/// share links carry `?ref=<code>`, an opaque ten-character code from
/// `my_share_ref`; a link the app opens hands its ref to the join or the copy
/// it leads to. Anything that is not a well-formed code is dropped. Web:
/// `lib/share/share_ref.ts`, which also carries the sign-up and bot helpers
/// only the browser needs.
library;

final RegExp _shareRef = RegExp(r'^[a-z0-9]{10}$');

/// The query parameter a share link carries its ref in.
const String shareRefParam = 'ref';

/// A well-formed ref code, or null.
String? parseShareRef(Object? value) =>
    value is String && _shareRef.hasMatch(value) ? value : null;

/// [url] with [ref] set as its `ref` parameter, keeping any other query. The
/// url unchanged when [ref] is not a well-formed code.
String withShareRef(String url, String? ref) {
  final code = parseShareRef(ref);
  if (code == null) return url;
  final uri = Uri.parse(url);
  return uri.replace(
    queryParameters: {...uri.queryParameters, shareRefParam: code},
  ).toString();
}

/// One of the creator's links, over the last 90 days (`my_share_stats`).
class ShareStat {
  final String kind;
  final String entityId;
  final String? title;
  final int visits;
  final int refVisits;
  final int botVisits;
  final int signups;
  final int starts;
  final int refStarts;
  final int joins;
  final int refJoins;

  const ShareStat({
    required this.kind,
    required this.entityId,
    this.title,
    this.visits = 0,
    this.refVisits = 0,
    this.botVisits = 0,
    this.signups = 0,
    this.starts = 0,
    this.refStarts = 0,
    this.joins = 0,
    this.refJoins = 0,
  });

  static const kinds = {'plan', 'challenge', 'profile', 'session', 'workout'};

  /// Null for a row whose kind this build does not know.
  static ShareStat? fromRow(Map<String, dynamic> r) {
    final kind = r['kind'];
    final id = r['entity_id'];
    if (kind is! String || !kinds.contains(kind) || id is! String) return null;
    int n(String k) => (r[k] as num?)?.toInt() ?? 0;
    return ShareStat(
      kind: kind,
      entityId: id,
      title: r['title'] as String?,
      visits: n('visits'),
      refVisits: n('ref_visits'),
      botVisits: n('bot_visits'),
      signups: n('signups'),
      starts: n('starts'),
      refStarts: n('ref_starts'),
      joins: n('joins'),
      refJoins: n('ref_joins'),
    );
  }
}

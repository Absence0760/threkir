// The subscribable plan calendar feed (migration 20270910000001, the
// plan-calendar Edge Function). Mirrors apps/web/src/lib/training/
// plan_calendar_feed.ts: the URL is the credential, so a token is shown once
// when minted and only the feed's two timestamps can be read afterwards.

final _token = RegExp(r'^[0-9a-f]{96}$');

bool isPlanCalendarFeedToken(String token) => _token.hasMatch(token);

/// The https URL a calendar subscribes to, or null for anything that is not
/// a token `rotate_plan_calendar_feed` could have minted.
String? planCalendarFeedUrl(String? supabaseUrl, String token) {
  if (supabaseUrl == null || !isPlanCalendarFeedToken(token)) return null;
  final base = Uri.tryParse(supabaseUrl);
  if (base == null ||
      !(base.scheme == 'https' || base.scheme == 'http') ||
      base.host.isEmpty) {
    return null;
  }
  final path = base.path.replaceAll(RegExp(r'/+$'), '');
  return '${base.origin}$path/functions/v1/plan-calendar/$token.ics';
}

/// The feed as a `webcal:` link, which a calendar app opens as a
/// subscription. Only an https feed converts.
String? webcalUrl(String httpsUrl) => httpsUrl.startsWith('https://')
    ? 'webcal://${httpsUrl.substring('https://'.length)}'
    : null;

class PlanCalendarFeedStatus {
  final DateTime createdAt;
  final DateTime? lastFetchedAt;

  const PlanCalendarFeedStatus({required this.createdAt, this.lastFetchedAt});

  static PlanCalendarFeedStatus? fromRow(Map<String, dynamic>? row) {
    final created = DateTime.tryParse('${row?['created_at'] ?? ''}');
    if (created == null) return null;
    final fetched = row?['last_fetched_at'];
    return PlanCalendarFeedStatus(
      createdAt: created,
      lastFetchedAt: fetched is String ? DateTime.tryParse(fetched) : null,
    );
  }
}

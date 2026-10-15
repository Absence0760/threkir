/// Who a live share runs for, and whether the run start opens one by itself
/// (docs/features/safety.md, decisions § 1964).
///
/// The safety net only watches a live stub, and until the safety-contacts
/// audience existed the only stub was a public one, so auto-live-share had to
/// stay an explicit opt-in. With the server's `safety_audience` gate open the
/// automatic share runs on the runner's confirmed safety contacts instead —
/// private, never flipped public, and readable by a contact only through the
/// link an alert carries — so it can follow the runner's own safety-net
/// choice rather than wait for a second switch.
library;

/// The audience a live stub is created for.
enum LiveShareAudience {
  /// `is_public = true` for the live window: the manual "Share live link",
  /// and every automatic share while the safety audience is off.
  public,

  /// Private, `safety_audience = true`: the runner's confirmed safety
  /// contacts, through the per-contact link an escalation mints.
  safetyContacts,
}

/// The audience the AUTOMATIC share runs on. Fail closed toward the stricter
/// one: with the gate open the automatic share is never public.
LiveShareAudience autoLiveShareAudience({required bool safetyAudienceEnabled}) =>
    safetyAudienceEnabled
        ? LiveShareAudience.safetyContacts
        : LiveShareAudience.public;

/// Whether the runner has armed an escalation that needs a live stub to watch:
/// the overdue silence window (`safety_overdue_minutes`, at least the scan's
/// 10-minute floor) or the off-route alert (`safety_off_route_alerts`).
bool safetyNetArmed({Object? overdueMinutes, Object? offRouteAlerts}) {
  final armedOverdue = overdueMinutes is num &&
      overdueMinutes.isFinite &&
      overdueMinutes >= 10;
  return armedOverdue || offRouteAlerts == true;
}

/// The effective `auto_live_share`. An explicit device choice always wins,
/// either way. Unset, it defaults ON only when the share would be on the
/// safety-contacts audience AND the runner armed an escalation that is blind
/// without one — never ON into a public share.
bool effectiveAutoLiveShare({
  required bool? explicitPref,
  required bool safetyAudienceEnabled,
  required bool safetyNetArmed,
}) =>
    explicitPref ?? (safetyAudienceEnabled && safetyNetArmed);

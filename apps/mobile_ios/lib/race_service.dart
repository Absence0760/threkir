import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart'
    show RouteMarkerRow, Waypoint, parseImportCompleteness;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'geocoding.dart';
import 'race_match.dart';

/// A discoverable race calendar entry (the `search_race_listings` projection:
/// listing cols + `distance_m_away` when a center was supplied). Mirrors the
/// web `RaceListingResult`.
class RaceListingView {
  final String id;
  final String provider;
  final String? providerRaceId;
  final String name;
  final String raceDate;
  final int? distanceM;
  final String? locationLabel;
  final String? entryUrl;
  final String? resultsUrl;
  final bool isVerified;
  final double? distanceMAway;

  /// The linked course's summary. The view fills it only while the route is
  /// public, so null covers "no course" and "a course nobody may see" alike
  /// (decisions § 2157). Calendar search rows never carry it.
  final RaceListingCourse? course;

  /// The verified club that claimed the race (decisions § 2381). Null while
  /// unclaimed, and while the club is private or moderated away. Calendar
  /// search rows never carry it.
  final String? organiserClubId;
  final String? organiserClubName;

  /// The claiming club is verified, public and unhidden right now
  /// (`organiser_is_official`, decisions § 2406). Search rows carry it too.
  final bool organiserIsOfficial;

  const RaceListingView({
    required this.id,
    required this.provider,
    required this.providerRaceId,
    required this.name,
    required this.raceDate,
    required this.distanceM,
    required this.locationLabel,
    required this.entryUrl,
    required this.resultsUrl,
    required this.isVerified,
    required this.distanceMAway,
    this.course,
    this.organiserClubId,
    this.organiserClubName,
    this.organiserIsOfficial = false,
  });

  factory RaceListingView.fromJson(Map<String, dynamic> j) => RaceListingView(
        id: j['id'] as String,
        provider: j['provider'] as String,
        providerRaceId: j['provider_race_id'] as String?,
        name: j['name'] as String,
        raceDate: j['race_date'] as String,
        distanceM: (j['distance_m'] as num?)?.toInt(),
        locationLabel: j['location_label'] as String?,
        entryUrl: j['entry_url'] as String?,
        resultsUrl: j['results_url'] as String?,
        isVerified: j['is_verified'] as bool? ?? false,
        distanceMAway: (j['distance_m_away'] as num?)?.toDouble(),
        course: RaceListingCourse.fromViewRow(j),
        organiserClubId: j['organiser_club_name'] == null
            ? null
            : j['organiser_club_id'] as String?,
        organiserClubName: j['organiser_club_id'] == null
            ? null
            : j['organiser_club_name'] as String?,
        organiserIsOfficial: j['organiser_is_official'] as bool? ?? false,
      );

  /// The same listing with no course, which the race screen shows while a
  /// course removal waits out its undo window.
  RaceListingView withoutCourse() => RaceListingView(
        id: id,
        provider: provider,
        providerRaceId: providerRaceId,
        name: name,
        raceDate: raceDate,
        distanceM: distanceM,
        locationLabel: locationLabel,
        entryUrl: entryUrl,
        resultsUrl: resultsUrl,
        isVerified: isVerified,
        distanceMAway: distanceMAway,
        organiserClubId: organiserClubId,
        organiserClubName: organiserClubName,
        organiserIsOfficial: organiserIsOfficial,
      );
}

/// The CHECK'd vocabulary of `race_listings.course_source` (decisions § 2381);
/// web's `RaceCourseSource`.
const kRaceCourseSources = ['official', 'traced'];

class RaceListingCourse {
  final double? distanceM;
  final double? ascentM;
  final String? surface;

  /// The view's `course_route_id`: set only while the course route is public
  /// and not shadow-hidden (decisions § 2253), so it names a route anyone can
  /// already open. Its line is read through `clip_route_for_viewer`, never
  /// from this view.
  final String? routeId;

  /// `official` or `traced` (decisions § 2381); null on a course linked
  /// before claims existed.
  final String? source;
  final String? checkedAt;

  /// Set when the route's line changed after the club last checked it.
  final String? updatedAt;

  const RaceListingCourse({
    this.distanceM,
    this.ascentM,
    this.surface,
    this.routeId,
    this.source,
    this.checkedAt,
    this.updatedAt,
  });

  /// Null when the row carries none of the view's course columns.
  static RaceListingCourse? fromViewRow(Map<String, dynamic> j) {
    final distance = (j['course_distance_m'] as num?)?.toDouble();
    final ascent = (j['course_elevation_m'] as num?)?.toDouble();
    final surface = j['course_surface'] as String?;
    final routeId = j['course_route_id'] as String?;
    if (distance == null && ascent == null && surface == null && routeId == null) {
      return null;
    }
    final source = j['course_source'] as String?;
    return RaceListingCourse(
      distanceM: distance,
      ascentM: ascent,
      surface: surface,
      routeId: routeId,
      source: kRaceCourseSources.contains(source) ? source : null,
      checkedAt: j['course_checked_at'] as String?,
      updatedAt: j['course_updated_at'] as String?,
    );
  }
}

/// The CHECK'd vocabulary of `course_alerts.kind` (decisions § 2407); web's
/// `CourseAlertKind`.
const kCourseAlertKinds = ['reroute', 'closure', 'direction', 'notice'];

/// An organiser's course alert on a race it claimed or a route its club
/// owns (decisions § 2407). Readable only while the club is still verified;
/// who typed it is never readable. Mirrors web's `CourseAlert`.
class CourseAlertView {
  final String id;
  final String clubId;
  final String? listingId;
  final String? routeId;

  /// One of [kCourseAlertKinds]; an unknown value reads as `notice`.
  final String kind;
  final String message;
  final String createdAt;

  const CourseAlertView({
    required this.id,
    required this.clubId,
    required this.listingId,
    required this.routeId,
    required this.kind,
    required this.message,
    required this.createdAt,
  });

  factory CourseAlertView.fromJson(Map<String, dynamic> j) {
    final kind = j['kind'] as String?;
    return CourseAlertView(
      id: j['id'] as String,
      clubId: j['club_id'] as String,
      listingId: j['listing_id'] as String?,
      routeId: j['route_id'] as String?,
      kind: kCourseAlertKinds.contains(kind) ? kind! : 'notice',
      message: j['message'] as String,
      createdAt: j['created_at'] as String,
    );
  }
}

/// A club the signed-in runner can claim races or link courses for.
class OrganiserClub {
  final String id;
  final String name;
  const OrganiserClub({required this.id, required this.name});
}

/// A route offered in the link or suggest picker.
class CourseRouteOption {
  final String id;
  final String name;
  const CourseRouteOption({required this.id, required this.name});
}

/// A pending course suggestion a reviewer may act on. It never names who
/// suggested it. Mirrors web's `RaceCourseSuggestion`.
class RaceCourseSuggestion {
  final String id;
  final String routeId;
  final String routeName;

  /// The club that owns the suggested route, when it is a club route.
  final String? routeClubId;
  final String? note;
  const RaceCourseSuggestion({
    required this.id,
    required this.routeId,
    required this.routeName,
    this.routeClubId,
    this.note,
  });
}

/// Which race-course actions the runner is offered (decisions § 2381). The
/// RPCs are the gate; this only picks the buttons. Mirrors web's
/// `raceCourseAccess` in `integrations/race_course_access.ts`.
class RaceCourseAccess {
  final bool canClaim;
  final bool canManage;
  final bool canSuggest;
  const RaceCourseAccess({
    required this.canClaim,
    required this.canManage,
    required this.canSuggest,
  });
}

RaceCourseAccess raceCourseAccess({
  required bool signedIn,
  required String? organiserClubId,
  required List<OrganiserClub> myOrganiserClubs,
}) {
  if (!signedIn) {
    return const RaceCourseAccess(
        canClaim: false, canManage: false, canSuggest: false);
  }
  final canManage = organiserClubId != null &&
      myOrganiserClubs.any((c) => c.id == organiserClubId);
  final canClaim = organiserClubId == null && myOrganiserClubs.isNotEmpty;
  return RaceCourseAccess(
      canClaim: canClaim, canManage: canManage, canSuggest: !canManage);
}

/// The matched-race view for a run: the run's owner-only race metadata + its
/// linked listing. Mirrors the web `RaceResultForRun`.
class RaceResultForRun {
  final RaceListingView? listing;
  final String? raceName;
  final String? bib;
  final String? chipTime;
  final String? gunTime;
  final int? overallPlace;
  final int? ageGroupPlace;
  final String? ageGroup;

  /// The award division (masters, overall top N, weight class) that lifted
  /// the runner out of their age group, with their place in it.
  final int? divisionAwardPlace;
  final String? divisionAward;

  const RaceResultForRun({
    required this.listing,
    required this.raceName,
    required this.bib,
    required this.chipTime,
    required this.gunTime,
    required this.overallPlace,
    required this.ageGroupPlace,
    required this.ageGroup,
    this.divisionAwardPlace,
    this.divisionAward,
  });

  bool get hasResult =>
      chipTime != null || gunTime != null || overallPlace != null || raceName != null;
}

/// A single result row pasted by the runner (the manual import path).
class PastedRaceResult {
  final String? bib;
  final String? chipTime;
  final String? gunTime;
  final int? overallPlace;

  const PastedRaceResult({this.bib, this.chipTime, this.gunTime, this.overallPlace});

  Map<String, dynamic> toJson() => {
        if (bib != null) 'bib': bib,
        if (chipTime != null) 'chip_time': chipTime,
        if (gunTime != null) 'gun_time': gunTime,
        if (overallPlace != null) 'overall_place': overallPlace,
      };
}

class ImportRaceResultOutcome {
  final int imported;
  final int skipped;
  final int enriched;

  /// Whether the function read the finisher field to its end. Only an explicit
  /// claim earns it — see `parseImportCompleteness`.
  final bool complete;

  const ImportRaceResultOutcome({
    required this.imported,
    required this.skipped,
    required this.enriched,
    this.complete = false,
  });
}

/// Thrown when the RunSignUp leg is unconfigured server-side (503), so the UI
/// can show the unavailable explainer rather than a generic failure.
class RunSignUpUnavailable implements Exception {
  const RunSignUpUnavailable();
}

/// Thrown when the ChronoTrack leg is unconfigured server-side (503), so the UI
/// can show the unavailable explainer rather than a generic failure.
/// The upstream finisher list was truncated before the runner was found, so
/// the function refused rather than report "you are not in these results".
///
/// A distinct type because "we read the whole field and you are not in it" and
/// "we read the first 2,000 finishers and you were not among them" are
/// different sentences, and the second is not an import failure the runner can
/// fix by retrying — the manual paste form beside it is the answer.
class RaceResultsTruncated implements Exception {
  const RaceResultsTruncated();
}

class ChronoTrackUnavailable implements Exception {
  const ChronoTrackUnavailable();
}

/// One race-results provider with a built leg in `race-results-import`, keyed
/// by the token that function takes.
///
/// This list is the only provider vocabulary the app holds: the probe and the
/// fail-closed exception both hang off it, so a leg added server-side reaches
/// every mobile surface by being named here once.
///
/// `paste` is deliberately absent — it is the universal manual fallback rather
/// than a listing provider, needs no credential and no probe, and stays offered
/// beside every entry here. So are `ultrasignup`, `manual` and `raceresult`,
/// which are listing providers with no import leg at all.
///
/// Every leg here is scoped by the runner's bib, which narrows the finisher
/// field to their own row. An unscoped pull returns the whole field and every
/// row of it is inserted as the caller's own run (issue #360), so the client
/// refuses one too.
class RaceImportProvider {
  final String provider;

  /// Thrown on the 503 `provider_not_configured` so a surface shows THIS
  /// provider's explainer and never a peer's.
  final Exception unavailable;

  final String probeFunction;
  final Map<String, dynamic> probeBody;

  const RaceImportProvider({
    required this.provider,
    required this.unavailable,
    required this.probeFunction,
    required this.probeBody,
  });
}

const List<RaceImportProvider> raceImportProviders = [
  RaceImportProvider(
    provider: 'runsignup',
    unavailable: RunSignUpUnavailable(),
    // The RESULTS leg, as for chronotrack. It probed `race-listings-sync`
    // until § 1041, on the reasoning that both legs read the same two env vars
    // so either would answer — but the tile is a claim about whether an IMPORT
    // will work, and the sync owns a different leg. The move waited on
    // `race-results-import` gaining its own probe bucket: while a probe was
    // charged to the 8/hour import allowance, a third probe per settings load
    // would have cost a free runner the ability to import at all (§ 1008).
    probeFunction: 'race-results-import',
    probeBody: <String, dynamic>{'provider': 'runsignup', 'probe': true},
  ),
  RaceImportProvider(
    provider: 'chronotrack',
    unavailable: ChronoTrackUnavailable(),
    probeFunction: 'race-results-import',
    probeBody: <String, dynamic>{'provider': 'chronotrack', 'probe': true},
  ),
];

final Map<String, RaceImportProvider> _providerByToken = {
  for (final p in raceImportProviders) p.provider: p,
};

/// The spec for a listing's provider, or null when that provider has no import
/// leg. A null is not a gap: manual paste still applies to every listing.
RaceImportProvider? raceImportProviderFor(String provider) =>
    _providerByToken[provider];

final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false);

/// One of the runner's own runs linked to a race listing (race detail screen).
class RaceListingRun {
  final String id;
  final String startedAt;
  final double distanceM;
  final int durationS;
  final String? chipTime;

  const RaceListingRun({
    required this.id,
    required this.startedAt,
    required this.distanceM,
    required this.durationS,
    required this.chipTime,
  });

  factory RaceListingRun.fromJson(Map<String, dynamic> j) {
    final meta = j['metadata'];
    final chip = meta is Map ? meta['chip_time'] : null;
    return RaceListingRun(
      id: j['id'] as String,
      startedAt: j['started_at'] as String,
      distanceM: (j['distance_m'] as num).toDouble(),
      durationS: (j['duration_s'] as num).toInt(),
      chipTime: chip is String ? chip : null,
    );
  }
}

/// All Supabase calls for the race calendar + results import (race_calendar.md).
/// Each method mirrors the like-named export in `apps/web/src/lib/core/data.ts`
/// — `searchRaceListings`, `fetchRaceListing`, `fetchMyRunsAtRace`,
/// `submitRaceListing`, `fetchRaceResultForRun`,
/// `findRaceMatchCandidates` and `importRaceResult` — with
/// `isProviderConfigured` standing in for its `isRaceImportProviderConfigured`.
/// Wire-level methods are exercisable against a real local Supabase via the
/// `withClient` seam.
class RaceService extends ChangeNotifier {
  final SupabaseClient? _override;
  final ApiClient? _apiOverride;

  /// [api] serves the course reads behind Drive this course; every race
  /// surface already holds this service, so they ride on it rather than on a
  /// second dependency each sheet would have to be handed.
  RaceService({ApiClient? api})
      : _override = null,
        _apiOverride = api;

  @visibleForTesting
  RaceService.withClient(SupabaseClient client, {ApiClient? api})
      : _override = client,
        _apiOverride = api;

  late final ApiClient _api = _apiOverride ?? ApiClient();

  SupabaseClient get _c {
    final override = _override;
    if (override != null) return override;
    if (!ApiClient.isInitialized) {
      throw StateError('RaceService called before Supabase.initialize() resolved.');
    }
    return Supabase.instance.client;
  }

  bool get isReady => _override != null || ApiClient.isInitialized;

  String? get _uid => _c.auth.currentUser?.id;

  /// Race discovery (security invoker, public listings). Mirrors
  /// `searchRaceListings` — proximity by the listing's geocoded location.
  Future<List<RaceListingView>> searchRaceListings({
    String? query,
    String? distance,
    String? from,
    String? to,
    String? nearPlace,
    String? mapTilerKey,
    Future<GeocodedPlace?> Function(String)? geocoder,
    int limit = 60,
    bool newestFirst = false,
  }) async {
    final params = <String, dynamic>{'p_limit': limit};
    if (newestFirst) params['p_newest_first'] = true;
    final term = query?.trim();
    if (term != null && term.isNotEmpty) params['p_query'] = term;
    if (distance != null && distance.isNotEmpty) params['p_distance'] = distance;
    if (from != null) params['p_from'] = from;
    if (to != null) params['p_to'] = to;

    final place = nearPlace?.trim();
    if (place != null && place.isNotEmpty && mapTilerKey != null) {
      final geo = await (geocoder ?? (q) => geocodePlace(q, apiKey: mapTilerKey))(place);
      if (geo != null) {
        params['p_center_lng'] = geo.lng;
        params['p_center_lat'] = geo.lat;
        params['p_radius_m'] = geo.radiusM;
      }
    }

    try {
      final raw =
          await _c.rpc('search_race_listings', params: params, get: true);
      return ((raw ?? <dynamic>[]) as List)
          .whereType<Map<String, dynamic>>()
          .map(RaceListingView.fromJson)
          .toList();
    } catch (e, s) {
      debugPrint('RaceService.searchRaceListings RPC failed: $e\n$s');
      return const [];
    }
  }

  /// A race course's line and markers for Drive this course
  /// (docs/features/course_drive.md): the privacy-clipped line and the
  /// viewer-redacted markers, the same reads the route screen makes for a
  /// non-owner. Throws on a failed read so the screen can offer a retry.
  Future<({List<Waypoint> line, List<RouteMarkerRow> markers})>
      fetchCourseForDrive(String routeId) async {
    final line = await _api.clipRouteForViewer(routeId);
    final markers = await _api.fetchRouteMarkers(routeId);
    return (line: line, markers: markers);
  }

  /// One calendar listing, for the race detail screen. Read through the
  /// redacted `public_race_listings` view, the projection a logged-out visitor
  /// gets. A malformed id or a missing row is null; a failed read throws, so
  /// the screen can tell "this race is gone" from "we could not load it".
  Future<RaceListingView?> fetchRaceListing(String id) async {
    if (!_uuid.hasMatch(id)) return null;
    final row = await _c
        .from('public_race_listings')
        .select(
            'id, provider, provider_race_id, name, race_date, distance_m, location_label, entry_url, results_url, is_verified, course_distance_m, course_elevation_m, course_surface, course_route_id, course_source, course_checked_at, course_updated_at, organiser_club_id, organiser_club_name, organiser_is_official')
        .eq('id', id)
        .maybeSingle();
    if (row == null ||
        row['id'] == null ||
        row['name'] == null ||
        row['race_date'] == null ||
        row['provider'] == null) {
      return null;
    }
    return RaceListingView.fromJson(row);
  }

  /// The signed-in runner's own runs linked to a listing, newest first, with
  /// the official chip time when the import stamped one.
  Future<List<RaceListingRun>> fetchMyRunsAtRace(String listingId) async {
    final uid = _uid;
    if (uid == null || !_uuid.hasMatch(listingId)) return const [];
    final rows = await _c
        .from('runs')
        .select('id, started_at, distance_m, duration_s, metadata')
        .eq('race_listing_id', listingId)
        .eq('user_id', uid)
        .order('started_at', ascending: false)
        .limit(20);
    return (rows as List)
        .whereType<Map<String, dynamic>>()
        .map(RaceListingRun.fromJson)
        .toList();
  }

  bool get isSignedIn => isReady && _uid != null;

  /// The clubs the runner is an active owner/admin of that are verified,
  /// public and not hidden: the facts `private.is_official_publisher` reads.
  Future<List<OrganiserClub>> fetchMyOrganiserClubs() async {
    final uid = _uid;
    if (uid == null) return const [];
    final rows = await _c
        .from('club_members')
        .select('club_id, role, status, clubs!inner(id, name, is_verified, is_public, shadow_hidden)')
        .eq('user_id', uid)
        .eq('status', 'active')
        .inFilter('role', ['owner', 'admin']);
    final out = <OrganiserClub>[];
    for (final r in (rows as List).whereType<Map<String, dynamic>>()) {
      final c = r['clubs'];
      if (c is! Map) continue;
      if (c['is_verified'] == true &&
          c['is_public'] == true &&
          c['shadow_hidden'] != true) {
        out.add(OrganiserClub(id: c['id'] as String, name: c['name'] as String));
      }
    }
    return out;
  }

  /// A club's public routes, for the link picker.
  Future<List<CourseRouteOption>> fetchClubPublicRoutes(String clubId) async {
    final rows = await _c
        .from('routes')
        .select('id, name')
        .eq('club_id', clubId)
        .eq('is_public', true)
        .eq('shadow_hidden', false)
        .order('created_at', ascending: false)
        .limit(200);
    return [
      for (final r in (rows as List).whereType<Map<String, dynamic>>())
        CourseRouteOption(id: r['id'] as String, name: r['name'] as String),
    ];
  }

  /// The runner's own public routes, for the suggest picker.
  Future<List<CourseRouteOption>> fetchMyPublicRoutes() async {
    final uid = _uid;
    if (uid == null) return const [];
    final rows = await _c
        .from('routes')
        .select('id, name')
        .eq('user_id', uid)
        .eq('is_public', true)
        .eq('shadow_hidden', false)
        .order('created_at', ascending: false)
        .limit(200);
    return [
      for (final r in (rows as List).whereType<Map<String, dynamic>>())
        CourseRouteOption(id: r['id'] as String, name: r['name'] as String),
    ];
  }

  /// The route of the runner's own open suggestion for a race, or null.
  Future<String?> fetchMyRaceCourseSuggestionRouteId(String listingId) async {
    if (_uid == null || !_uuid.hasMatch(listingId)) return null;
    final row = await _c
        .from('race_course_suggestions')
        .select('route_id')
        .eq('listing_id', listingId)
        .eq('status', 'pending')
        .maybeSingle();
    return row?['route_id'] as String?;
  }

  /// A race's or a route's course alerts, newest first. Mirrors web's
  /// `fetchCourseAlerts`.
  Future<List<CourseAlertView>> fetchCourseAlerts({
    String? listingId,
    String? routeId,
    int limit = 20,
  }) async {
    final id = listingId ?? routeId;
    if (id == null || !_uuid.hasMatch(id)) return const [];
    final rows = await _c
        .from('course_alerts')
        .select('id, club_id, listing_id, route_id, kind, message, created_at')
        .eq(listingId != null ? 'listing_id' : 'route_id', id)
        .order('created_at', ascending: false)
        .limit(limit);
    return [
      for (final r in (rows as List).whereType<Map<String, dynamic>>())
        CourseAlertView.fromJson(r),
    ];
  }

  /// Where an alert points, for a tapped course-alert notification; null
  /// when the alert is gone or its club no longer vouches for it.
  Future<({String? listingId, String? routeId})?> fetchCourseAlertTarget(
      String alertId) async {
    if (!_uuid.hasMatch(alertId)) return null;
    final row = await _c
        .from('course_alerts')
        .select('listing_id, route_id')
        .eq('id', alertId)
        .maybeSingle();
    if (row == null) return null;
    return (
      listingId: row['listing_id'] as String?,
      routeId: row['route_id'] as String?,
    );
  }

  /// Posts an alert as the organiser club; the RPC is the gate and tells the
  /// runners training for the race or who saved its course. Mirrors web's
  /// `postCourseAlert`.
  Future<void> postCourseAlert({
    String? listingId,
    String? routeId,
    required String kind,
    required String message,
  }) async {
    await _c.rpc('post_course_alert', params: {
      'p_listing_id': listingId,
      'p_route_id': routeId,
      'p_kind': kind,
      'p_message': message.trim(),
    });
  }

  /// Mirrors web's `deleteCourseAlert`.
  Future<void> deleteCourseAlert(String alertId) async {
    await _c.rpc('delete_course_alert', params: {'p_alert_id': alertId});
  }

  /// Mirrors web's `claimRaceListing`.
  Future<void> claimRaceListing(String listingId, String clubId) async {
    await _c.rpc('claim_race_listing',
        params: {'p_listing_id': listingId, 'p_club_id': clubId});
  }

  /// Mirrors web's `linkRaceCourse`; linking the same route again re-checks it.
  Future<void> linkRaceCourse(
      String listingId, String? routeId, String? source) async {
    await _c.rpc('link_race_course', params: {
      'p_listing_id': listingId,
      'p_route_id': routeId,
      'p_source': source,
    });
  }

  /// Mirrors web's `suggestRaceCourse`.
  Future<void> suggestRaceCourse(
      String listingId, String routeId, String? note) async {
    final trimmed = note?.trim();
    await _c.rpc('suggest_race_course', params: {
      'p_listing_id': listingId,
      'p_route_id': routeId,
      'p_note': (trimmed == null || trimmed.isEmpty) ? null : trimmed,
    });
  }

  /// The pending suggestions a reviewer may act on; empty for anyone who is
  /// not one. Mirrors web's `fetchRaceCourseSuggestionsForReview`.
  Future<List<RaceCourseSuggestion>> fetchRaceCourseSuggestionsForReview(
      String listingId) async {
    if (_uid == null || !_uuid.hasMatch(listingId)) return const [];
    final rows = await _c.rpc('race_course_suggestions_for_review',
        params: {'p_listing_id': listingId}, get: true);
    return [
      for (final r in (rows as List).whereType<Map<String, dynamic>>())
        RaceCourseSuggestion(
          id: r['id'] as String,
          routeId: r['route_id'] as String,
          routeName: r['route_name'] as String,
          routeClubId: r['route_club_id'] as String?,
          note: r['note'] as String?,
        ),
    ];
  }

  /// Approve (linking [routeId], the club's own public copy) or reject a
  /// suggestion. Mirrors web's `reviewRaceCourseSuggestion`.
  Future<void> reviewRaceCourseSuggestion(String suggestionId, bool approve,
      {String? routeId, String source = 'official'}) async {
    await _c.rpc('review_race_course_suggestion', params: {
      'p_suggestion_id': suggestionId,
      'p_approve': approve,
      'p_route_id': routeId,
      'p_source': source,
    });
  }

  /// Submit a crowd-sourced manual listing. `is_verified` is forced false by
  /// the DB trigger; `submitted_by` is stamped to the caller (RLS requires it).
  Future<RaceListingView> submitRaceListing({
    required String name,
    required String raceDate,
    int? distanceM,
    String? locationLabel,
    String? entryUrl,
    String? resultsUrl,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    final row = await _c
        .from('race_listings')
        .insert({
          'provider': 'manual',
          'name': name.trim(),
          'race_date': raceDate,
          'distance_m': distanceM,
          'location_label': _blankToNull(locationLabel),
          'entry_url': _blankToNull(entryUrl),
          'results_url': _blankToNull(resultsUrl),
          'submitted_by': uid,
        })
        .select()
        .single();
    return RaceListingView.fromJson(row);
  }

  /// The owner-only race metadata + linked listing for a run. Mirrors
  /// `fetchRaceResultForRun`.
  Future<RaceResultForRun?> fetchRaceResultForRun(String runId) async {
    final row = await _c
        .from('runs')
        .select('metadata, race_listing_id')
        .eq('id', runId)
        .maybeSingle();
    if (row == null) return null;
    final meta = (row['metadata'] as Map<String, dynamic>?) ?? const {};
    RaceListingView? listing;
    final listingId = row['race_listing_id'] as String?;
    if (listingId != null) {
      final l = await _c
          .from('public_race_listings')
          .select()
          .eq('id', listingId)
          .maybeSingle();
      if (l != null) listing = RaceListingView.fromJson(l);
    }
    return RaceResultForRun(
      listing: listing,
      raceName: meta['race_name'] as String?,
      bib: meta['bib'] as String?,
      chipTime: meta['chip_time'] as String?,
      gunTime: meta['gun_time'] as String?,
      overallPlace: (meta['overall_place'] as num?)?.toInt(),
      ageGroupPlace: (meta['age_group_place'] as num?)?.toInt(),
      ageGroup: meta['age_group'] as String?,
      divisionAwardPlace: (meta['division_award_place'] as num?)?.toInt(),
      divisionAward: meta['division_award'] as String?,
    );
  }

  /// The auto-match seam: same-day listings to offer "Is this your race?".
  /// The caller scores them by proximity + distance band via [raceMatchScore].
  Future<List<RaceListingView>> findRaceMatchCandidates(String runId) async {
    final run = await _c
        .from('runs')
        .select('started_at')
        .eq('id', runId)
        .maybeSingle();
    final startedAt = run?['started_at'] as String?;
    if (startedAt == null) return const [];
    final day = startedAt.substring(0, 10);
    return searchRaceListings(from: day, to: day, limit: 20);
  }

  /// Invoke `race-results-import`. Throws the provider's own
  /// [RaceImportProvider.unavailable] on the 503 `provider_not_configured` so
  /// the UI can show that provider's explainer. Mirrors web's
  /// `importRaceResult`.
  Future<ImportRaceResultOutcome> importRaceResult({
    required String provider, // a [raceImportProviders] token, or 'paste'
    required String listingId,
    String? bib,
    String? matchRunId,
    PastedRaceResult? result,
  }) async {
    try {
      final res = await _c.functions.invoke('race-results-import', body: {
        'provider': provider,
        'listingId': listingId,
        if (bib != null) 'bib': bib,
        if (matchRunId != null) 'matchRunId': matchRunId,
        if (result != null) 'result': result.toJson(),
      });
      final data = (res.data as Map<String, dynamic>?) ?? const {};
      return ImportRaceResultOutcome(
        imported: (data['imported'] as num?)?.toInt() ?? 0,
        skipped: (data['skipped'] as num?)?.toInt() ?? 0,
        enriched: (data['enriched'] as num?)?.toInt() ?? 0,
        // A field read only as far as the cap still imports the rows it found,
        // so the success path has to carry the claim or a truncated import
        // renders exactly like a whole one (decisions § 1014).
        complete: parseImportCompleteness(data).complete,
      );
    } on FunctionException catch (e) {
      final spec = raceImportProviderFor(provider);
      if (spec != null && e.status == 503 && _isProviderNotConfigured(e.details)) {
        throw spec.unavailable;
      }
      if (e.status == 502 && _detailsSay(e.details, 'upstream_results_truncated')) {
        throw const RaceResultsTruncated();
      }
      rethrow;
    }
  }

  /// Probe whether [provider]'s import leg is configured server-side, over the
  /// probe that provider's [RaceImportProvider] names. Answers false without a
  /// call for a listing provider that has no import leg at all, so a caller can
  /// ask about any listing and get an honest answer rather than a peer's.
  ///
  /// **Configured iff the invoke did not throw** — web's `probeSaysConfigured`
  /// rule (`core/provider_probe.ts`), because a probe asks one question and
  /// only a 200 answers it. `functions_client` throws `FunctionException` for
  /// every status outside 200-299, so "did not throw" is exactly "2xx", and the
  /// probe branch of `race-results-import` has exactly one affirmative answer:
  /// `{configured: true}`. Everything else it can say is a refusal.
  ///
  /// This replaced a grader that reported a readable non-429 4xx as CONFIGURED,
  /// on the theory that such a status proved the function ran past its
  /// credential gate. Reading the endpoint rather than the theory refutes it
  /// twice (decisions § 1073): the function answers **401 before it reads any
  /// provider credential at all**, so a signed-out or expired session lit every
  /// card as live; and it answers **400 `unknown_provider`** for a leg it does
  /// not dispatch, which its own comment introduces as "not configured" — the
  /// function and the client had opposite readings of one response.
  ///
  /// Total by construction, so a caller cannot lose the fail-closed answer by
  /// forgetting to catch. The two screens keep their own L4 try/catch anyway —
  /// a probe is the layering contract's named example of an auxiliary network
  /// effect, and web's callers of the same probes carry the same backstop.
  ///
  /// **Deliberately single-sourced per platform, not a registered parity
  /// pair** (decisions § 1095). Web states the same rule as
  /// `apps/web/src/lib/core/provider_probe.ts#probeSaysConfigured`, but the two
  /// client libraries hand a failure over differently — `@supabase/
  /// functions-js` RETURNS `{data, error}`, so web's half is one expression
  /// over a nullable error, while `functions_client` 2.5.0 THROWS, so this one
  /// is control flow. A Dart twin would take an error value no Dart caller
  /// holds. What a pair would have bought — the two halves read against each
  /// other — is bought instead by a source guard in `race_providers_test.dart`
  /// that reads web's grader directly.
  Future<bool> isProviderConfigured(String provider) async {
    final spec = raceImportProviderFor(provider);
    if (spec == null) return false;
    try {
      await _c.functions.invoke(spec.probeFunction, body: spec.probeBody);
      return true;
    } catch (e) {
      debugPrint('RaceService: $provider probe reports unavailable: $e');
      return false;
    }
  }

  bool _isProviderNotConfigured(dynamic details) =>
      _detailsSay(details, 'provider_not_configured');

  bool _detailsSay(dynamic details, String code) {
    if (details is Map && details['error'] == code) return true;
    return details.toString().contains(code);
  }

  String? _blankToNull(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' show parseImportCompleteness;
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
      );
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

/// Thrown when the UltraSignup leg is unconfigured server-side (503), so the UI
/// can show the unavailable explainer rather than a generic failure.
class UltraSignUpUnavailable implements Exception {
  const UltraSignUpUnavailable();
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

/// An UltraSignup import was asked for before the runner picked themselves in
/// Settings, so there is nobody to import for. Refused before the call, as on
/// web (`ULTRASIGNUP_NOT_LINKED`).
class UltraSignUpNotLinked implements Exception {
  const UltraSignUpNotLinked();
}

/// The function no longer finds the linked person under their name (404
/// `ultrasignup_person_not_found`). That is a link to redo, not a race with no
/// result in it.
class UltraSignUpPersonNotFound implements Exception {
  const UltraSignUpPersonNotFound();
}

/// The one scoping value a provider's leg needs before it may be called.
enum RaceImportScope {
  /// The runner's bib narrows the finisher field to their own row. An unscoped
  /// pull returns the whole field and every row of it is inserted as the
  /// caller's own run (issue #360), so the client refuses one too.
  bib,

  /// WHO the runner is on the provider scopes the pull: the person they picked
  /// once in Settings (decisions § 1841), so the import asks for nothing and
  /// sends the stored link.
  linkedPerson,
}

/// One race-results provider with a built leg in `race-results-import`, keyed
/// by the token that function takes.
///
/// This list is the only provider vocabulary the app holds: the probe, the
/// fail-closed exception and what a caller must supply all hang off it, so a
/// leg added server-side reaches every mobile surface by being named here once.
///
/// `paste` is deliberately absent — it is the universal manual fallback rather
/// than a listing provider, needs no credential and no probe, and stays offered
/// beside every entry here. So are `parkrun`, `manual` and `raceresult`, which
/// are listing providers with no bib-import leg at all.
class RaceImportProvider {
  final String provider;
  final RaceImportScope scope;

  /// Thrown on the 503 `provider_not_configured` so a surface shows THIS
  /// provider's explainer and never a peer's.
  final Exception unavailable;

  final String probeFunction;
  final Map<String, dynamic> probeBody;

  const RaceImportProvider({
    required this.provider,
    required this.scope,
    required this.unavailable,
    required this.probeFunction,
    required this.probeBody,
  });
}

const List<RaceImportProvider> raceImportProviders = [
  RaceImportProvider(
    provider: 'runsignup',
    scope: RaceImportScope.bib,
    unavailable: RunSignUpUnavailable(),
    // The RESULTS leg, as for the other two. It probed `race-listings-sync`
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
    provider: 'ultrasignup',
    scope: RaceImportScope.linkedPerson,
    unavailable: UltraSignUpUnavailable(),
    // The RESULTS leg, not the listings sync. The two are separately gated:
    // `race-listings-sync` answers on ULTRASIGNUP_API_KEY alone, while the
    // results leg reads a keyless feed and answers on the deployment's
    // ULTRASIGNUP_RESULTS_ENABLED opt-in (decisions § 1841). Probing the sync
    // would advertise an import the results leg then refuses.
    //
    // `ultraSignUpFlow: 'person'` says this client speaks the person flow. A
    // client that does not is told the leg is unavailable, which is what kept
    // the builds still sending the retired athlete id dark.
    probeFunction: 'race-results-import',
    probeBody: <String, dynamic>{
      'provider': 'ultrasignup',
      'probe': true,
      'ultraSignUpFlow': 'person',
    },
  ),
  RaceImportProvider(
    provider: 'chronotrack',
    scope: RaceImportScope.bib,
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
/// `findRaceMatchCandidates`, `importRaceResult`, and the UltraSignup person
/// calls `fetchUltraSignUpLink` / `linkUltraSignUpPerson` /
/// `unlinkUltraSignUpPerson` / `lookupUltraSignUpPeople` — with
/// `isProviderConfigured` standing in for its `isRaceImportProviderConfigured`.
/// Wire-level methods are exercisable against a real local Supabase via the
/// `withClient` seam.
class RaceService extends ChangeNotifier {
  final SupabaseClient? _override;
  final ApiClient? _apiOverride;

  /// [api] is where the UltraSignup person link is read and written; every
  /// race surface already holds this service, so the link rides on it rather
  /// than on a second dependency each sheet would have to be handed.
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

  /// One calendar listing, for the race detail screen. Read through the
  /// redacted `public_race_listings` view, the projection a logged-out visitor
  /// gets. A malformed id or a missing row is null; a failed read throws, so
  /// the screen can tell "this race is gone" from "we could not load it".
  Future<RaceListingView?> fetchRaceListing(String id) async {
    if (!_uuid.hasMatch(id)) return null;
    final row = await _c
        .from('public_race_listings')
        .select(
            'id, provider, provider_race_id, name, race_date, distance_m, location_label, entry_url, results_url, is_verified')
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
  /// the UI can show that provider's explainer.
  ///
  /// An UltraSignup import is scoped by the person the runner picked in
  /// Settings (decisions § 1841): [ultraSignUpPerson] when the caller holds
  /// it, otherwise the stored link is read, and with neither this throws
  /// [UltraSignUpNotLinked] before reaching the function. Mirrors web's
  /// `importRaceResult`.
  Future<ImportRaceResultOutcome> importRaceResult({
    required String provider, // a [raceImportProviders] token, or 'paste'
    required String listingId,
    String? bib,
    UltraSignUpPersonLink? ultraSignUpPerson,
    String? matchRunId,
    PastedRaceResult? result,
  }) async {
    UltraSignUpPersonLink? person;
    if (provider == ultraSignUpProvider) {
      person = ultraSignUpPerson ?? await fetchUltraSignUpLink();
      if (person == null) throw const UltraSignUpNotLinked();
    }
    try {
      final res = await _c.functions.invoke('race-results-import', body: {
        'provider': provider,
        'listingId': listingId,
        if (bib != null) 'bib': bib,
        if (person != null) ...{
          'ultraSignUpPersonId': person.personId,
          'ultraSignUpFirstName': person.firstName,
          'ultraSignUpLastName': person.lastName,
        },
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
      if (e.status == 404 && _detailsSay(e.details, 'ultrasignup_person_not_found')) {
        throw const UltraSignUpPersonNotFound();
      }
      rethrow;
    }
  }

  /// The runner's stored UltraSignup person, or null when they have not linked
  /// one. See [ApiClient.fetchUltraSignUpLink].
  Future<UltraSignUpPersonLink?> fetchUltraSignUpLink() =>
      _api.fetchUltraSignUpLink();

  /// Store the person the runner picked. See [ApiClient.linkUltraSignUpPerson].
  Future<void> linkUltraSignUpPerson(UltraSignUpPersonLink link) =>
      _api.linkUltraSignUpPerson(link);

  /// Forget the stored person. See [ApiClient.unlinkUltraSignUpPerson].
  Future<void> unlinkUltraSignUpPerson() => _api.unlinkUltraSignUpPerson();

  /// The people UltraSignup knows by this name, for the runner to pick
  /// themselves from. Throws [UltraSignUpUnavailable] on the 503
  /// `provider_not_configured` (the leg is off on this deployment), and the
  /// function's own refusal otherwise.
  Future<List<UltraSignUpCandidate>> lookupUltraSignUpPeople(
    String firstName,
    String lastName,
  ) async {
    try {
      return await _api.lookupUltraSignUpPeople(firstName, lastName);
    } on FunctionException catch (e) {
      if (e.status == 503 && _isProviderNotConfigured(e.details)) {
        throw const UltraSignUpUnavailable();
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

  /// Whether the parkrun import leg is reachable on this deployment.
  ///
  /// parkrun needs no credential, so unlike the three race-results legs above
  /// this asks only whether the Edge Function is deployed — the question a
  /// minimal deployment answers no to and every client used to skip, offering
  /// an import tile for a function that is not there. Same fail-closed shape:
  /// only a call that does not throw counts.
  ///
  /// Lives here rather than on `ApiClient` so the settings screen reaches every
  /// probe it draws through one seam, which is what lets its widget test inject
  /// a stub for all of them at once.
  Future<bool> isParkrunConfigured() async {
    try {
      await _c.functions.invoke('parkrun-import', body: {'probe': true});
      return true;
    } catch (e) {
      debugPrint('RaceService: parkrun probe reports unavailable: $e');
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

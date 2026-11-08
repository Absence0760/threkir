import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/gen/app_localizations.dart';
import '../preferences.dart'
    show
        activeDistanceUnit,
        formatDistanceForPref,
        formatEffortTime,
        formatElevationForPref;
import '../pro_sellable.dart' show fetchAiPlanAvailable;
import '../race_plan_prefill.dart';
import '../race_plan_preset.dart';
import '../race_predictor.dart' show predictRaceLadder;
import '../race_service.dart';
import '../route_surface_label.dart';
import '../share_sheet.dart';
import '../training.dart' show toIsoDate;
import '../training_service.dart';
import '../web_base_url.dart';
import '../widgets/error_state.dart';
import '../widgets/top_banner.dart';
import '../widgets/loading_skeletons.dart';
import 'plan_new_screen.dart';
import 'races_screen.dart' show showRaceImportSheet;

/// Who listed a race. Provider names are brands and stay untranslated;
/// `manual` (or anything unknown) is a hand-added listing, credited to the
/// verified club that claimed it when there is one (decisions § 2381).
/// Mirrors web's `raceSourceLabel`.
const _providerNames = {
  'runsignup': 'RunSignUp',
  'ultrasignup': 'UltraSignup',
  'chronotrack': 'ChronoTrack',
  'raceresult': 'RaceResult',
  'parkrun': 'parkrun',
};

@visibleForTesting
String raceSourceLabel(AppLocalizations l, String provider,
    [String? organiserName]) {
  final name = _providerNames[provider];
  if (name != null) return l.racesSourceProvider(name);
  return organiserName == null
      ? l.racesSourceManual
      : l.racesSourceClub(organiserName);
}

/// Where a linked course came from. Mirrors web's `raceCourseSourceLabel`.
@visibleForTesting
String? raceCourseSourceLabel(
    AppLocalizations l, String? source, String? organiserName) {
  if (source == null || organiserName == null) return null;
  return source == 'official'
      ? l.raceCourseSourceOfficial(organiserName)
      : l.raceCourseSourceTraced(organiserName);
}

/// Public share URL for a race — the `/share/race/{id}` page. Mirrors web's
/// `buildRaceShareCanonical`.
String raceShareUrl(String listingId, {String? webBase}) {
  return '${resolveWebBaseUrl(override: webBase)}/share/race/$listingId';
}

/// The race detail screen (race_calendar.md), the twin of web's
/// `/races/[id]`. Opened from a calendar card's name: the race's facts, who
/// lists it, train / race page / results / share, the import from race day
/// on, and the runner's own runs linked to it. A verified club's admin can
/// claim the race and link its course, and any runner can suggest a course
/// (decisions § 2381); reviewing suggestions stays on web. Runners' photos
/// stay on web — the phone has no reader for `race_listing_photos` yet.
class RaceDetailScreen extends StatefulWidget {
  final RaceService service;
  final String listingId;

  /// Test-only DI seam for the plan wizard the train action opens.
  final TrainingService? training;

  /// Test-only DI seam for whether the AI plan assistant is live.
  final Future<bool> Function()? loadAiPlanAvailable;

  const RaceDetailScreen({
    super.key,
    required this.service,
    required this.listingId,
    this.training,
    this.loadAiPlanAvailable,
  });

  @override
  State<RaceDetailScreen> createState() => _RaceDetailScreenState();
}

class _RaceDetailScreenState extends State<RaceDetailScreen> {
  RaceListingView? _race;
  bool _loading = true;
  bool _loadFailed = false;
  List<RaceListingRun> _runs = const [];
  bool _runsFailed = false;
  List<RacePlanOwnPlan> _ownPlans = const [];
  RacePlanEffort? _recentEffort;
  // Fail-closed: the AI action stays hidden until the deploy says the
  // assistant is live.
  bool _aiPlan = false;
  List<OrganiserClub> _myClubs = const [];
  String? _mySuggestionRouteId;
  bool _busy = false;

  late final TrainingService _training = widget.training ?? TrainingService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    RaceListingView? race;
    var failed = false;
    try {
      race = await widget.service.fetchRaceListing(widget.listingId);
    } catch (e) {
      debugPrint('RaceDetailScreen: listing load failed: $e');
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _race = race;
      _loadFailed = failed;
      _loading = false;
    });
    if (race != null) {
      unawaited(_loadPlanContext());
      unawaited(_loadCourseContext());
      await _loadRuns();
    }
  }

  // Auxiliary: a failed read hides the course tools, never breaks the screen.
  Future<void> _loadCourseContext() async {
    if (!widget.service.isSignedIn) return;
    try {
      final clubs = await widget.service.fetchMyOrganiserClubs();
      if (mounted) setState(() => _myClubs = clubs);
    } catch (e) {
      debugPrint('RaceDetailScreen: organiser clubs read failed: $e');
    }
    try {
      final routeId =
          await widget.service.fetchMyRaceCourseSuggestionRouteId(widget.listingId);
      if (mounted) setState(() => _mySuggestionRouteId = routeId);
    } catch (e) {
      debugPrint('RaceDetailScreen: own suggestion read failed: $e');
    }
  }

  // Re-reads the listing after a claim or course change without the loading
  // skeleton, so the screen stays put.
  Future<void> _refreshRace() async {
    try {
      final race = await widget.service.fetchRaceListing(widget.listingId);
      if (mounted && race != null) setState(() => _race = race);
    } catch (e) {
      debugPrint('RaceDetailScreen: listing refresh failed: $e');
    }
  }

  Future<void> _runCourseAction(
      Future<void> Function() action, String done, String failed) async {
    if (_busy) return;
    setState(() => _busy = true);
    var ok = false;
    try {
      await action();
      ok = true;
    } catch (e) {
      debugPrint('RaceDetailScreen: course action failed: $e');
    }
    if (!mounted) return;
    setState(() => _busy = false);
    showTopBanner(context, ok ? done : failed);
    if (ok) await _refreshRace();
  }

  Future<void> _claim(RaceListingView race) async {
    final l = AppLocalizations.of(context);
    var clubId = _myClubs.first.id;
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(l.raceCourseClaimTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.raceCourseClaimBody),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('race-course-claim-club'),
                initialValue: clubId,
                isExpanded: true,
                decoration: InputDecoration(labelText: l.raceCourseClaimClub),
                items: [
                  for (final c in _myClubs)
                    DropdownMenuItem(
                        value: c.id,
                        child: Text(c.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setLocal(() => clubId = v ?? clubId),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l.commonCancel)),
            FilledButton(
              key: const Key('race-course-claim-confirm'),
              onPressed: () => Navigator.pop(ctx, clubId),
              child: Text(l.raceCourseClaimConfirm),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _runCourseAction(
      () => widget.service.claimRaceListing(race.id, picked),
      l.raceCourseClaimed,
      l.raceCourseClaimFailed,
    );
  }

  Future<void> _link(RaceListingView race) async {
    final l = AppLocalizations.of(context);
    final clubId = race.organiserClubId;
    if (clubId == null) return;
    List<CourseRouteOption> routes;
    try {
      routes = await widget.service.fetchClubPublicRoutes(clubId);
    } catch (e) {
      debugPrint('RaceDetailScreen: club routes read failed: $e');
      if (mounted) showTopBanner(context, l.raceCourseLinkFailed);
      return;
    }
    if (!mounted) return;
    final current = race.course?.routeId;
    String? routeId = routes.any((r) => r.id == current)
        ? current
        : (routes.isEmpty ? null : routes.first.id);
    var source = race.course?.source ?? 'official';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(l.raceCourseLinkTitle),
          content: routes.isEmpty
              ? Text(l.raceCourseLinkNoRoutes,
                  key: const Key('race-course-link-empty'))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      key: const Key('race-course-link-route'),
                      initialValue: routeId,
                      isExpanded: true,
                      decoration:
                          InputDecoration(labelText: l.raceCourseLinkRoute),
                      items: [
                        for (final r in routes)
                          DropdownMenuItem(
                              value: r.id,
                              child: Text(r.name,
                                  overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setLocal(() => routeId = v),
                    ),
                    const SizedBox(height: 12),
                    Text(l.raceCourseLinkSourceLabel),
                    RadioGroup<String>(
                      groupValue: source,
                      onChanged: (v) => setLocal(() => source = v ?? source),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RadioListTile<String>(
                            value: 'official',
                            contentPadding: EdgeInsets.zero,
                            title: Text(l.raceCourseSourceOptionOfficial),
                          ),
                          RadioListTile<String>(
                            key: const Key('race-course-source-traced'),
                            value: 'traced',
                            contentPadding: EdgeInsets.zero,
                            title: Text(l.raceCourseSourceOptionTraced),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l.commonCancel)),
            if (routes.isNotEmpty)
              FilledButton(
                key: const Key('race-course-link-confirm'),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l.raceCourseLinkConfirm),
              ),
          ],
        ),
      ),
    );
    final chosen = routeId;
    if (ok != true || chosen == null || !mounted) return;
    await _runCourseAction(
      () => widget.service.linkRaceCourse(race.id, chosen, source),
      l.raceCourseLinked,
      l.raceCourseLinkFailed,
    );
  }

  Future<void> _markChecked(RaceListingView race) async {
    final l = AppLocalizations.of(context);
    final routeId = race.course?.routeId;
    if (routeId == null) return;
    await _runCourseAction(
      () => widget.service
          .linkRaceCourse(race.id, routeId, race.course?.source ?? 'official'),
      l.raceCourseCheckedDone,
      l.raceCourseLinkFailed,
    );
  }

  Future<void> _suggest(RaceListingView race) async {
    final l = AppLocalizations.of(context);
    List<CourseRouteOption> routes;
    try {
      routes = await widget.service.fetchMyPublicRoutes();
    } catch (e) {
      debugPrint('RaceDetailScreen: own routes read failed: $e');
      routes = const [];
    }
    if (!mounted) return;
    final initial = routes.any((r) => r.id == _mySuggestionRouteId)
        ? _mySuggestionRouteId
        : (routes.isEmpty ? null : routes.first.id);
    final picked = await showDialog<({String routeId, String note})>(
      context: context,
      builder: (_) => _SuggestCourseDialog(routes: routes, initialRouteId: initial),
    );
    if (picked == null || !mounted) return;
    final chosen = picked.routeId;
    final text = picked.note;
    if (_busy) return;
    setState(() => _busy = true);
    var sent = false;
    try {
      await widget.service.suggestRaceCourse(race.id, chosen, text);
      sent = true;
    } catch (e) {
      debugPrint('RaceDetailScreen: suggestion failed: $e');
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (sent) _mySuggestionRouteId = chosen;
    });
    showTopBanner(
        context, sent ? l.raceCourseSuggested : l.raceCourseSuggestFailed);
  }

  Widget _courseTools(
      BuildContext context, AppLocalizations l, RaceListingView race) {
    final access = raceCourseAccess(
      signedIn: widget.service.isSignedIn,
      organiserClubId: race.organiserClubId,
      myOrganiserClubs: _myClubs,
    );
    if (!access.canClaim && !access.canManage && !access.canSuggest) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final hasCourse = race.course?.routeId != null;
    return Column(
      key: const Key('race-course-tools'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(l.raceCourseToolsHeading, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (access.canClaim)
              OutlinedButton(
                key: const Key('race-course-claim'),
                onPressed: _busy ? null : () => _claim(race),
                child: Text(l.raceCourseClaim),
              ),
            if (access.canManage)
              OutlinedButton(
                key: const Key('race-course-link'),
                onPressed: _busy ? null : () => _link(race),
                child: Text(hasCourse
                    ? l.raceCourseChangeCourse
                    : l.raceCourseLinkCourse),
              ),
            if (access.canManage && hasCourse)
              OutlinedButton(
                key: const Key('race-course-mark-checked'),
                onPressed: _busy ? null : () => _markChecked(race),
                child: Text(l.raceCourseMarkChecked),
              ),
            if (access.canSuggest)
              OutlinedButton(
                key: const Key('race-course-suggest'),
                onPressed: _busy ? null : () => _suggest(race),
                child: Text(l.raceCourseSuggest),
              ),
          ],
        ),
        if (access.canSuggest && _mySuggestionRouteId != null)
          Padding(
            key: const Key('race-course-suggest-pending'),
            padding: const EdgeInsets.only(top: 8),
            child:
                Text(l.raceCourseSuggestPending, style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }

  // Auxiliary to the race-to-plan actions: a failed read leaves the plain
  // "Build a plan" action, never an error on the race screen.
  Future<void> _loadPlanContext() async {
    try {
      final plans = await _training.fetchMyPlans();
      if (!mounted) return;
      setState(() => _ownPlans = [
            for (final p in plans)
              RacePlanOwnPlan(
                id: p.id,
                name: p.name,
                status: p.status,
                endDateIso: toIsoDate(p.endDate),
                goalDistanceM: p.goalDistanceM,
                goalTimeSeconds: p.goalTimeSeconds,
              ),
          ]);
    } catch (e) {
      debugPrint('RaceDetailScreen: plan read failed: $e');
    }
    var ai = false;
    try {
      ai = await (widget.loadAiPlanAvailable ?? fetchAiPlanAvailable)();
    } catch (e) {
      debugPrint('RaceDetailScreen: AI plan capability lookup failed: $e');
    }
    if (!mounted || !ai) return;
    setState(() => _aiPlan = true);
    try {
      final history = await _training.fetchPlanRunHistory();
      final anchor =
          history == null ? null : predictRaceLadder(history.efforts)?.anchor;
      if (!mounted || anchor == null) return;
      setState(() => _recentEffort = RacePlanEffort(
            distanceM: anchor.distanceM,
            durationS: anchor.durationS,
            ageDays: anchor.ageDays,
          ));
    } catch (e) {
      debugPrint('RaceDetailScreen: recent-effort read failed: $e');
    }
  }

  Future<void> _loadRuns() async {
    setState(() => _runsFailed = false);
    try {
      final runs = await widget.service.fetchMyRunsAtRace(widget.listingId);
      if (!mounted) return;
      setState(() => _runs = runs);
    } catch (e) {
      debugPrint('RaceDetailScreen: runs load failed: $e');
      if (!mounted) return;
      setState(() => _runsFailed = true);
    }
  }

  Future<void> _trainFor(
    RaceListingView race, {
    String? notBeforeIso,
    String? describe,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlanNewScreen(
          training: _training,
          raceDateIso: race.raceDate,
          raceName: race.name,
          raceDistanceM: race.distanceM,
          raceListingId: race.id,
          notBeforeIso: notBeforeIso,
          initialDescription: describe,
          loadAiPlanAvailable: widget.loadAiPlanAvailable,
        ),
      ),
    );
  }

  Future<void> _import(RaceListingView race) async {
    final done = await showRaceImportSheet(
      context,
      service: widget.service,
      race: race,
    );
    if (done == true && mounted) {
      showTopBanner(context, AppLocalizations.of(context).racesImported);
      await _loadRuns();
    }
  }

  Future<void> _share(BuildContext context, RaceListingView race) async {
    try {
      await shareTextFrom(context, text: raceShareUrl(race.id), subject: race.name);
    } catch (e) {
      debugPrint('RaceDetailScreen: share failed: $e');
    }
  }

  Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url);
    var ok = false;
    if (uri != null) {
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          ok = true;
        } else {
          debugPrint('RaceDetailScreen: no handler available for $url');
        }
      } catch (e) {
        debugPrint('RaceDetailScreen: launch failed for $url: $e');
      }
    }
    if (!ok && mounted) {
      showTopBanner(context, AppLocalizations.of(context).racesCouldNotOpenLink);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final race = _race;
    return Scaffold(
      appBar: AppBar(title: Text(race?.name ?? l.racesTitle)),
      body: _loading
          ? SectionedDetailSkeleton(
              label: l.commonLoading,
              statCells: 3,
              hasAction: true,
              rows: 3,
            )
          : _loadFailed
              ? ErrorState(message: l.racesDetailLoadFailed, onRetry: _load)
              : race == null
                  ? _message(l.racesDetailNotFound)
                  : _body(context, l, race),
    );
  }

  // The screen shows race dates as their ISO day (`race.raceDate`), so the
  // course dates follow suit.
  static String _isoDay(String timestamp) =>
      timestamp.length >= 10 ? timestamp.substring(0, 10) : timestamp;

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center),
        ),
      );

  Widget _body(BuildContext context, AppLocalizations l, RaceListingView race) {
    final theme = Theme.of(context);
    final today = toIsoDate(DateTime.now());
    // A result exists only from race day on; before that the screen says when
    // the import opens rather than offer one that can only come back empty.
    final canImport = race.raceDate.compareTo(today) <= 0;
    final canTrainFor = racePlanPreset(
      raceDateIso: race.raceDate,
      distanceM: race.distanceM,
      todayIso: today,
    ).ok;
    final planRace = RacePlanRace(
      name: race.name,
      raceDateIso: race.raceDate,
      distanceM: race.distanceM,
    );
    // A plan ending before this race: the new plan queues behind it rather
    // than replacing or trimming it (decisions § 2008, § 2154).
    final chain = canTrainFor ? racePlanChain(_ownPlans, planRace, today) : null;
    final course = race.course;
    final describe = canTrainFor && _aiPlan
        ? racePlanDescribe(
            race: planRace,
            goalTimeS: racePlanGoalTimeS(_ownPlans, race.raceDate),
            recentEffort: _recentEffort,
            course: course == null
                ? null
                : RacePlanCourse(
                    ascentM: course.ascentM,
                    surface: course.surface,
                  ),
            unit: activeDistanceUnit,
          )
        : null;
    final courseParts = <String>[
      if (course != null) ...[
        if ((course.distanceM ?? 0) > 0)
          formatDistanceForPref(course.distanceM!),
        if ((course.ascentM ?? 0) > 0)
          l.racesCourseGain(formatElevationForPref(course.ascentM)),
        if ((course.surface ?? '').isNotEmpty)
          routeSurfaceLabel(l, course.surface!),
      ],
    ];
    final courseSource = course == null
        ? null
        : raceCourseSourceLabel(l, course.source, race.organiserClubName);
    final meta = <String>[
      race.raceDate,
      if (race.distanceM != null) formatDistanceForPref(race.distanceM!.toDouble()),
      if (race.locationLabel != null) race.locationLabel!,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(race.name, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(meta.join(' · '), style: theme.textTheme.bodyMedium),
        const SizedBox(height: 4),
        Text(
          raceSourceLabel(l, race.provider, race.organiserClubName),
          key: const Key('race-detail-source'),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (!race.isVerified)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(l.racesUnverified, style: theme.textTheme.labelSmall),
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (chain != null)
              FilledButton(
                key: const Key('race-detail-add-to-season'),
                onPressed: () =>
                    _trainFor(race, notBeforeIso: chain.notBeforeIso),
                child: Text(l.racesAddToSeason),
              ),
            if (canTrainFor && chain != null)
              OutlinedButton(
                key: const Key('race-detail-train'),
                onPressed: () => _trainFor(race),
                child: Text(l.racesBuildPlan),
              )
            else if (canTrainFor)
              FilledButton(
                key: const Key('race-detail-train'),
                onPressed: () => _trainFor(race),
                child: Text(l.racesBuildPlan),
              ),
            if (describe != null)
              OutlinedButton(
                key: const Key('race-detail-tailor-ai'),
                onPressed: () => _trainFor(race,
                    notBeforeIso: chain?.notBeforeIso, describe: describe),
                child: Text(l.racesTailorWithAi),
              ),
            if (race.entryUrl != null)
              OutlinedButton(
                onPressed: () => _launch(race.entryUrl!),
                child: Text(l.racesRegister),
              ),
            if (race.resultsUrl != null)
              OutlinedButton(
                onPressed: () => _launch(race.resultsUrl!),
                child: Text(l.racesViewResults),
              ),
            Builder(
              builder: (btnContext) => OutlinedButton(
                onPressed: () => _share(btnContext, race),
                child: Text(l.racesDetailShare),
              ),
            ),
            if (canImport)
              FilledButton(
                onPressed: () => _import(race),
                child: Text(l.racesImportResult),
              ),
          ],
        ),
        if (chain != null)
          Padding(
            key: const Key('race-detail-season-hint'),
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l.racesAddToSeasonHint(
                  chain.planName, chain.planEndIso, '${chain.recoveryDays}'),
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (!canImport)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l.racesDetailImportAfterRace(race.raceDate),
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (courseParts.isNotEmpty) ...[
          const SizedBox(height: 24),
          Column(
            key: const Key('race-detail-course'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.racesCourseHeading, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(courseParts.join(' · '), style: theme.textTheme.bodyMedium),
              if (courseSource != null) ...[
                const SizedBox(height: 4),
                Text(
                  [
                    courseSource,
                    if (course?.checkedAt != null)
                      l.raceCourseChecked(_isoDay(course!.checkedAt!)),
                  ].join(' · '),
                  key: const Key('race-detail-course-source'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
              if (course?.updatedAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  l.raceCourseUpdated(_isoDay(course!.updatedAt!)),
                  key: const Key('race-detail-course-updated'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ],
        _courseTools(context, l, race),
        const SizedBox(height: 24),
        Text(l.racesDetailYourRuns, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_runsFailed)
          Row(
            children: [
              Expanded(child: Text(l.racesDetailRunsFailed)),
              TextButton(onPressed: _loadRuns, child: Text(l.errorStateRetry)),
            ],
          )
        else if (_runs.isEmpty)
          Text(l.racesDetailNoRuns, style: theme.textTheme.bodySmall)
        else
          for (final r in _runs)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(r.startedAt.length >= 10 ? r.startedAt.substring(0, 10) : r.startedAt),
                subtitle: Text(
                  '${formatDistanceForPref(r.distanceM)} · '
                  '${r.chipTime != null ? '${l.racesChipTime} ${r.chipTime}' : formatEffortTime(r.durationS.toDouble())}',
                ),
              ),
            ),
      ],
    );
  }
}

/// The "Suggest a course" dialog. Its own State owns the note controller, so
/// the controller outlives the dialog's exit animation.
class _SuggestCourseDialog extends StatefulWidget {
  final List<CourseRouteOption> routes;
  final String? initialRouteId;

  const _SuggestCourseDialog({required this.routes, required this.initialRouteId});

  @override
  State<_SuggestCourseDialog> createState() => _SuggestCourseDialogState();
}

class _SuggestCourseDialogState extends State<_SuggestCourseDialog> {
  late String? _routeId = widget.initialRouteId;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final routes = widget.routes;
    return AlertDialog(
      title: Text(l.raceCourseSuggestTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.raceCourseSuggestBody),
            const SizedBox(height: 12),
            if (routes.isEmpty)
              Text(l.raceCourseSuggestNoRoutes,
                  key: const Key('race-course-suggest-empty'))
            else ...[
              DropdownButtonFormField<String>(
                key: const Key('race-course-suggest-route'),
                initialValue: _routeId,
                isExpanded: true,
                decoration: InputDecoration(labelText: l.raceCourseSuggestRoute),
                items: [
                  for (final r in routes)
                    DropdownMenuItem(
                        value: r.id,
                        child: Text(r.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _routeId = v),
              ),
              TextField(
                key: const Key('race-course-suggest-note'),
                controller: _note,
                maxLength: 500,
                maxLines: 3,
                minLines: 1,
                decoration: InputDecoration(labelText: l.raceCourseSuggestNote),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.commonCancel)),
        if (routes.isNotEmpty)
          FilledButton(
            key: const Key('race-course-suggest-confirm'),
            onPressed: _routeId == null
                ? null
                : () => Navigator.pop(context, (routeId: _routeId!, note: _note.text)),
            child: Text(l.raceCourseSuggestConfirm),
          ),
      ],
    );
  }
}

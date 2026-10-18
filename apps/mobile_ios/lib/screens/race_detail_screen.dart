import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show ActivityLoaderKind, FullBodyLoader;
import 'package:url_launcher/url_launcher.dart';

import '../l10n/gen/app_localizations.dart';
import '../preferences.dart' show formatDistanceForPref, formatEffortTime;
import '../pro_sellable.dart' show fetchAiPlanAvailable;
import '../race_plan_prefill.dart';
import '../race_plan_preset.dart';
import '../race_predictor.dart' show predictRaceLadder;
import '../race_service.dart';
import '../share_sheet.dart';
import '../training.dart' show toIsoDate;
import '../training_service.dart';
import '../web_base_url.dart';
import '../widgets/error_state.dart';
import '../widgets/top_banner.dart';
import 'plan_new_screen.dart';
import 'races_screen.dart' show showRaceImportSheet;

/// Who listed a race. Provider names are brands and stay untranslated;
/// `manual` (or anything unknown) is a runner's own submission. Mirrors web's
/// `raceSourceLabel`.
const _providerNames = {
  'runsignup': 'RunSignUp',
  'ultrasignup': 'UltraSignup',
  'chronotrack': 'ChronoTrack',
  'raceresult': 'RaceResult',
  'parkrun': 'parkrun',
};

@visibleForTesting
String raceSourceLabel(AppLocalizations l, String provider) {
  final name = _providerNames[provider];
  return name == null ? l.racesSourceManual : l.racesSourceProvider(name);
}

/// Public share URL for a race — the `/share/race/{id}` page. Mirrors web's
/// `buildRaceShareCanonical`.
String raceShareUrl(String listingId, {String? webBase}) {
  return '${resolveWebBaseUrl(override: webBase)}/share/race/$listingId';
}

/// The race detail screen (race_calendar.md), the twin of web's
/// `/races/[id]`. Opened from a calendar card's name: the race's facts, who
/// lists it, train / race page / results / share, the import from race day
/// on, and the runner's own runs linked to it. Runners' photos stay on web —
/// the phone has no reader for `race_listing_photos` yet.
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
      await _loadRuns();
    }
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
          ? FullBodyLoader(kind: ActivityLoaderKind.run, label: l.commonLoading)
          : _loadFailed
              ? ErrorState(message: l.racesDetailLoadFailed, onRetry: _load)
              : race == null
                  ? _message(l.racesDetailNotFound)
                  : _body(context, l, race),
    );
  }

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
    final describe = canTrainFor && _aiPlan
        ? racePlanDescribe(
            race: planRace,
            goalTimeS: racePlanGoalTimeS(_ownPlans, race.raceDate),
            recentEffort: _recentEffort,
          )
        : null;
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
          raceSourceLabel(l, race.provider),
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

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';

import '../backend_timeout.dart';
import '../goal_time.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../plan_request_client.dart';
import '../preferences.dart' show activeDistanceUnit, formatDistanceForPref;
import '../pro_sellable.dart' show fetchAiPlanAvailable;
import '../season_plan.dart';
import '../season_request_client.dart';
import '../season_types.dart';
import '../training.dart';
import '../training_service.dart';
import '../typed_decimal.dart';
import '../widgets/ai_disclosure_notice.dart';
import '../widgets/plan_overlap_dialog.dart';
import 'plan_detail_screen.dart';

const int _kSeasonDescriptionMaxChars = 1200;
const double _kMetresPerMile = 1609.344;

class _RaceRow {
  final int key;
  final TextEditingController name;
  final TextEditingController distance;
  final TextEditingController goal;
  String? date;
  SeasonRacePriority priority;

  _RaceRow({
    required this.key,
    String name = '',
    String distance = '',
    String goal = '',
    this.date,
    required this.priority,
  })  : name = TextEditingController(text: name),
        distance = TextEditingController(text: distance),
        goal = TextEditingController(text: goal);

  void dispose() {
    name.dispose();
    distance.dispose();
    goal.dispose();
  }
}

/// The season planner (issue #1181): a race list, entered by hand or found in
/// a description, confirmed by the runner and built by [buildSeason] into one
/// chained plan per A race. Mirrors web `/plans/season`.
class SeasonPlanScreen extends StatefulWidget {
  final TrainingService training;

  /// Used to open the AI disclosure when the season request is refused for
  /// consent. Null resolves the global client at tap time.
  final ApiClient? apiClient;

  /// Test seams: whether the deploy has the AI assistant, the request
  /// itself, and the runner's calendar day.
  final Future<bool> Function()? loadAiAvailable;
  final Future<SeasonRequestResult> Function(String request, String todayIso)?
      requestSeasonRacesFn;
  final String Function()? todayIso;

  const SeasonPlanScreen({
    super.key,
    required this.training,
    this.apiClient,
    this.loadAiAvailable,
    this.requestSeasonRacesFn,
    this.todayIso,
  });

  @override
  State<SeasonPlanScreen> createState() => _SeasonPlanScreenState();
}

class _SeasonPlanScreenState extends State<SeasonPlanScreen> {
  final _describeCtrl = TextEditingController();
  final List<_RaceRow> _rows = [];
  int _nextKey = 0;
  int _daysPerWeek = 4;

  bool _aiAvailable = false;
  bool _aiBusy = false;
  PlanRequestErrorKind? _aiError;
  bool _aiFound = false;
  List<String> _aiAssumptions = const [];

  TrainingGender _viewerGender;
  int? _viewerAge;

  String? _rowError;
  SeasonBuildResult? _built;
  String? _builtFor;

  bool _creating = false;
  final List<({int index, String id})> _created = [];
  int? _failedIndex;
  String? _createError;

  double get _perUnit =>
      activeDistanceUnit == DistanceUnit.mi ? _kMetresPerMile : 1000;

  String _today() => widget.todayIso?.call() ?? toIsoDate(DateTime.now());

  @override
  void initState() {
    super.initState();
    _loadAiAvailability();
    widget.training.fetchViewerGender().then((g) {
      if (mounted) setState(() => _viewerGender = g);
    }).catchError((Object e) {
      debugPrint('SeasonPlanScreen: gender lookup failed: $e');
    });
    widget.training.fetchViewerAge().then((a) {
      if (mounted) setState(() => _viewerAge = a);
    }).catchError((Object e) {
      debugPrint('SeasonPlanScreen: age lookup failed: $e');
    });
  }

  @override
  void dispose() {
    _describeCtrl.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAiAvailability() async {
    var available = false;
    try {
      available = await (widget.loadAiAvailable ?? fetchAiPlanAvailable)();
    } catch (e) {
      debugPrint('SeasonPlanScreen: AI capability lookup failed: $e');
    }
    if (mounted && available) setState(() => _aiAvailable = true);
  }

  String _currentKey() => [
        _daysPerWeek,
        for (final r in _rows)
          '${r.key}|${r.name.text}|${r.date}|${r.distance.text}|${r.priority.name}|${r.goal.text}',
      ].join('\n');

  SeasonBuildResult? get _preview =>
      _built != null && _builtFor == _currentKey() ? _built : null;

  void _changed() => setState(() {});

  _RaceRow _rowFrom(SeasonRace race) {
    final km = race.distanceM / _perUnit;
    final goal = race.goalTimeSec;
    return _RaceRow(
      key: _nextKey++,
      name: race.name.length > kSeasonRaceNameMax
          ? race.name.substring(0, kSeasonRaceNameMax)
          : race.name,
      distance: formatDistanceInput(km),
      goal: goal == null ? '' : formatRaceGoalTimeS(goal),
      date: race.date,
      priority: race.priority,
    );
  }

  static String formatDistanceInput(double v) {
    final rounded = (v * 100).round() / 100;
    return rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toString();
  }

  void _addRace() {
    setState(() {
      _rows.add(_RaceRow(
        key: _nextKey++,
        priority:
            _rows.isEmpty ? SeasonRacePriority.a : SeasonRacePriority.b,
      ));
    });
  }

  void _removeRace(_RaceRow row) {
    setState(() => _rows.remove(row));
    row.dispose();
  }

  Future<void> _findRaces() async {
    final text = _describeCtrl.text.trim();
    if (text.isEmpty || _aiBusy) return;
    setState(() {
      _aiBusy = true;
      _aiError = null;
      _aiFound = false;
      _aiAssumptions = const [];
    });
    try {
      final result = await (widget.requestSeasonRacesFn ?? requestSeasonRaces)(
          text, _today());
      if (!mounted) return;
      if (result.races.isEmpty) {
        setState(() {
          _aiAssumptions = result.assumptions;
          _aiError = PlanRequestErrorKind.notUnderstood;
          if (_rows.isEmpty) {
            _rows.add(
                _RaceRow(key: _nextKey++, priority: SeasonRacePriority.a));
          }
        });
        return;
      }
      setState(() {
        for (final r in _rows) {
          r.dispose();
        }
        _rows
          ..clear()
          ..addAll(result.races.map(_rowFrom));
        _aiFound = true;
        _aiAssumptions = result.assumptions;
      });
    } catch (e) {
      if (e is! PlanRequestError) {
        debugPrint('SeasonPlanScreen: season request failed: $e');
      }
      if (!mounted) return;
      setState(() {
        _aiError =
            e is PlanRequestError ? e.kind : PlanRequestErrorKind.unavailable;
        if (_rows.isEmpty) {
          _rows.add(_RaceRow(key: _nextKey++, priority: SeasonRacePriority.a));
        }
      });
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _reviewAiDisclosure() async {
    try {
      final api =
          widget.apiClient ?? (ApiClient.isInitialized ? ApiClient() : null);
      if (api == null) return;
      final recorded = await showAiDisclosureDialog(context, api);
      if (recorded == null || !mounted) return;
      setState(() => _aiError = null);
      await _findRaces();
    } catch (e) {
      debugPrint('SeasonPlanScreen: AI disclosure review failed: $e');
    }
  }

  Future<void> _pickDate(_RaceRow row) async {
    final today = parseIsoDate(_today());
    final initial = row.date != null
        ? parseIsoDate(row.date!)
        : today.add(const Duration(days: 84));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(today) ? today : initial,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365 * 3)),
    );
    if (picked != null && mounted) setState(() => row.date = toIsoDate(picked));
  }

  List<SeasonRace>? _racesFromRows(AppLocalizations l10n) {
    final races = <SeasonRace>[];
    for (var i = 0; i < _rows.length; i++) {
      final r = _rows[i];
      final distance = parseTypedDecimal(r.distance.text);
      final goalText = r.goal.text.trim();
      final goal = goalText.isEmpty ? null : parseRaceGoalTimeS(goalText);
      if (r.name.text.trim().isEmpty ||
          r.date == null ||
          distance == null ||
          distance <= 0 ||
          (goalText.isNotEmpty && goal == null)) {
        _rowError = l10n.seasonPlanRowInvalid(i + 1);
        return null;
      }
      races.add(SeasonRace(
        name: r.name.text.trim(),
        date: r.date!,
        distanceM: distance * _perUnit,
        priority: r.priority,
        goalTimeSec: goal,
      ));
    }
    return races;
  }

  void _confirm(AppLocalizations l10n) {
    setState(() {
      _rowError = null;
      _createError = null;
      _created.clear();
      _failedIndex = null;
      final races = _racesFromRows(l10n);
      if (races == null) {
        _built = null;
        return;
      }
      _built = buildSeason(
        races: races,
        todayIso: _today(),
        daysPerWeek: _daysPerWeek,
        gender: _viewerGender,
        age: _viewerAge,
      );
      _builtFor = _currentKey();
    });
  }

  /// Writes the drafted plans in order, as web `createSeasonPlans` does: the
  /// first plan alone may overlap an active plan and goes through the overlap
  /// dialog; the later ones are checked before anything is written, and a
  /// failure part-way keeps the plans created and offers to create the rest.
  Future<void> _create(AppLocalizations l10n) async {
    final preview = _preview;
    if (preview == null || !preview.ok || _creating) return;
    final drafts = preview.plans;
    final from = _failedIndex ?? 0;
    setState(() {
      _creating = true;
      _createError = null;
    });
    try {
      var firstAction = PlanOverlapAction.refuse;
      if (from == 0) {
        final active =
            await widget.training.fetchActivePlans().timeout(kBackendLoadTimeout);
        for (var i = 1; i < drafts.length; i++) {
          final hits = overlappingActivePlans(
              active, drafts[i].startDate, drafts[i].endDate);
          if (hits.isNotEmpty) {
            if (mounted) {
              setState(() => _createError = l10n.seasonPlanBlocked(
                  drafts[i].name, hits.map((p) => p.name).join(', ')));
            }
            return;
          }
        }
        if (!mounted) return;
        final action = await confirmPlanOverlap(context, widget.training,
            startIso: drafts.first.startDate, endIso: drafts.first.endDate);
        if (action == null) return;
        firstAction = action;
      }
      for (var i = from; i < drafts.length; i++) {
        final d = drafts[i];
        try {
          final plan = await widget.training
              .createPlan(
                name: d.name,
                goalEvent: d.goalEvent,
                goalDistanceM: d.goalDistanceM,
                goalTimeSec: d.goalTimeSec,
                startDate: parseIsoDate(d.startDate),
                daysPerWeek: d.daysPerWeek,
                generated: d.generated,
                onOverlap: i == 0 ? firstAction : PlanOverlapAction.refuse,
              )
              .timeout(kBackendLoadTimeout);
          _created.add((index: i, id: plan.id));
        } catch (e) {
          debugPrint('SeasonPlanScreen: create of plan $i failed: $e');
          if (!mounted) return;
          final error = planOverlapErrorText(context, e) ?? e.toString();
          setState(() {
            _failedIndex = i;
            _createError = _created.isEmpty
                ? l10n.seasonPlanFailedNone(error)
                : l10n.seasonPlanFailedPartial(
                    _created.map((c) => drafts[c.index].name).join(', '),
                    drafts.sublist(i).map((p) => p.name).join(', '),
                    error,
                  );
          });
          return;
        }
      }
      if (!mounted) return;
      final firstId = _created.firstWhere((c) => c.index == 0).id;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              PlanDetailScreen(training: widget.training, planId: firstId),
        ),
      );
    } catch (e) {
      debugPrint('SeasonPlanScreen: season create failed: $e');
      if (mounted) {
        setState(() => _createError = l10n.seasonPlanFailedNone(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  String _priorityLabel(AppLocalizations l10n, SeasonRacePriority p) =>
      switch (p) {
        SeasonRacePriority.a => l10n.seasonPlanPriorityA,
        SeasonRacePriority.b => l10n.seasonPlanPriorityB,
        SeasonRacePriority.c => l10n.seasonPlanPriorityC,
      };

  String _aiErrorText(AppLocalizations l10n, PlanRequestErrorKind kind) =>
      switch (kind) {
        PlanRequestErrorKind.consent => l10n.seasonPlanErrorConsent,
        PlanRequestErrorKind.dailyLimit => l10n.seasonPlanErrorDailyLimit,
        PlanRequestErrorKind.notUnderstood => l10n.seasonPlanErrorNotUnderstood,
        PlanRequestErrorKind.invalid => l10n.seasonPlanErrorInvalid,
        PlanRequestErrorKind.notAuthenticated => l10n.seasonPlanErrorSignIn,
        PlanRequestErrorKind.unavailable => l10n.seasonPlanErrorUnavailable,
      };

  String _refusalText(AppLocalizations l10n, SeasonBuildResult r) {
    final races = r.races.join(', ');
    return switch (r.reason!) {
      SeasonRefusal.empty => l10n.seasonPlanRefusedEmpty,
      SeasonRefusal.invalidRace => l10n.seasonPlanRefusedInvalid(races),
      SeasonRefusal.raceNotAhead => l10n.seasonPlanRefusedNotAhead(races),
      SeasonRefusal.noARace => l10n.seasonPlanRefusedNoA,
      SeasonRefusal.firstTooSoon => l10n.seasonPlanRefusedFirstTooSoon(races),
      SeasonRefusal.aRacesTooClose => l10n.seasonPlanRefusedTooClose(races),
    };
  }

  String _unplacedText(
          AppLocalizations l10n, SeasonUnplaced u, String Function(String) day) =>
      switch (u.reason) {
        SeasonUnplacedReason.beforeFirstPlan =>
          l10n.seasonPlanUnplacedBefore(u.race.name, day(u.race.date)),
        SeasonUnplacedReason.betweenPlans =>
          l10n.seasonPlanUnplacedBetween(u.race.name, day(u.race.date)),
        SeasonUnplacedReason.afterLastPlan =>
          l10n.seasonPlanUnplacedAfter(u.race.name, day(u.race.date)),
        SeasonUnplacedReason.sameDay =>
          l10n.seasonPlanUnplacedSameDay(u.race.name, day(u.race.date)),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    String day(String iso) => formatDateMed(parseIsoDate(iso), tag);
    final preview = _preview;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final unit = activeDistanceUnit == DistanceUnit.mi ? 'mi' : 'km';
    return Scaffold(
      appBar: AppBar(title: Text(l10n.seasonPlanTitle)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 32 + bottomInset),
        children: [
          Text(
            l10n.seasonPlanIntro,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (_aiAvailable) ...[
            _describeCard(theme, l10n),
            const SizedBox(height: 16),
          ],
          Text(l10n.seasonPlanRacesTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            l10n.seasonPlanRacesHint,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          if (_rows.isEmpty)
            Text(l10n.seasonPlanNoRaces, key: const Key('season-no-races')),
          for (var i = 0; i < _rows.length; i++)
            _raceCard(theme, l10n, _rows[i], i, unit, day),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('season-add-race'),
              onPressed: _addRace,
              icon: const Icon(Icons.add),
              label: Text(l10n.seasonPlanAddRace),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            key: const Key('season-days'),
            initialValue: _daysPerWeek,
            decoration: InputDecoration(
              labelText: l10n.seasonPlanDaysPerWeek,
              helperText: l10n.seasonPlanDaysPerWeekHint,
              helperMaxLines: 3,
            ),
            items: [
              for (final d in [3, 4, 5, 6, 7])
                DropdownMenuItem(value: d, child: Text('$d')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _daysPerWeek = v);
            },
          ),
          if (_rowError != null) ...[
            const SizedBox(height: 8),
            Text(_rowError!,
                key: const Key('season-row-error'),
                style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('season-preview'),
            onPressed: _rows.isEmpty ? null : () => _confirm(l10n),
            child: Text(l10n.seasonPlanPreviewButton),
          ),
          if (preview != null) ...[
            const SizedBox(height: 20),
            _previewSection(theme, l10n, preview, day),
          ],
        ],
      ),
    );
  }

  Widget _describeCard(ThemeData theme, AppLocalizations l10n) {
    final cs = theme.colorScheme;
    final error = _aiError;
    final assumptions = [
      for (final a in _aiAssumptions)
        if (seasonAssumptionLabel(l10n, a) case final label?) label,
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.seasonPlanDescribeTitle,
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(l10n.seasonPlanDescribeHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            TextField(
              key: const Key('season-describe'),
              controller: _describeCtrl,
              minLines: 2,
              maxLines: 5,
              maxLength: _kSeasonDescriptionMaxChars,
              enabled: !_aiBusy,
              decoration: InputDecoration(
                labelText: l10n.seasonPlanDescribeTitle,
                hintText: l10n.seasonPlanDescribePlaceholder,
                hintMaxLines: 3,
              ),
              onChanged: (_) => _changed(),
            ),
            FilledButton.tonal(
              key: const Key('season-find-races'),
              onPressed: (_aiBusy || _describeCtrl.text.trim().isEmpty)
                  ? null
                  : _findRaces,
              child: Text(_aiBusy
                  ? l10n.seasonPlanDescribeWorking
                  : l10n.seasonPlanDescribeButton),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Container(
                  key: const Key('season-ai-error'),
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_aiErrorText(l10n, error),
                          style: TextStyle(color: cs.onErrorContainer)),
                      if (error == PlanRequestErrorKind.consent)
                        TextButton(
                          onPressed: _reviewAiDisclosure,
                          child: Text(l10n.seasonPlanReviewDisclosure),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (_aiFound || assumptions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Container(
                  key: const Key('season-ai-found'),
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_aiFound)
                        Text(l10n.seasonPlanDescribeFound,
                            style: TextStyle(color: cs.onSecondaryContainer)),
                      for (final line in assumptions)
                        Text('• $line',
                            style: TextStyle(color: cs.onSecondaryContainer)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _raceCard(ThemeData theme, AppLocalizations l10n, _RaceRow row, int i,
      String unit, String Function(String) day) {
    return Card(
      key: ValueKey('season-race-${row.key}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(l10n.seasonPlanRaceLegend(i + 1),
                      style: theme.textTheme.titleSmall),
                ),
                IconButton(
                  key: Key('season-remove-$i'),
                  tooltip: l10n.seasonPlanRemoveRace(i + 1),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _removeRace(row),
                ),
              ],
            ),
            TextField(
              key: Key('season-name-$i'),
              controller: row.name,
              maxLength: kSeasonRaceNameMax,
              decoration: InputDecoration(labelText: l10n.seasonPlanRaceName),
              onChanged: (_) => _changed(),
            ),
            ListTile(
              key: Key('season-date-$i'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(l10n.seasonPlanRaceDate),
              subtitle: Text(
                  row.date == null ? l10n.seasonPlanRaceDatePick : day(row.date!)),
              onTap: () => _pickDate(row),
            ),
            TextField(
              key: Key('season-distance-$i'),
              controller: row.distance,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: l10n.seasonPlanRaceDistance(unit)),
              onChanged: (_) => _changed(),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<SeasonRacePriority>(
              key: Key('season-priority-$i-${row.priority.name}'),
              initialValue: row.priority,
              decoration:
                  InputDecoration(labelText: l10n.seasonPlanRacePriority),
              items: [
                for (final p in SeasonRacePriority.values)
                  DropdownMenuItem(
                      value: p, child: Text(_priorityLabel(l10n, p))),
              ],
              onChanged: (v) {
                if (v != null) setState(() => row.priority = v);
              },
            ),
            TextField(
              key: Key('season-goal-$i'),
              controller: row.goal,
              keyboardType: TextInputType.datetime,
              decoration: InputDecoration(
                labelText: l10n.seasonPlanRaceGoal,
                helperText: l10n.seasonPlanRaceGoalHint,
              ),
              onChanged: (_) => _changed(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewSection(ThemeData theme, AppLocalizations l10n,
      SeasonBuildResult preview, String Function(String) day) {
    final cs = theme.colorScheme;
    if (!preview.ok) {
      return Semantics(
        liveRegion: true,
        child: Text(
          _refusalText(l10n, preview),
          key: const Key('season-refusal'),
          style: TextStyle(color: cs.error),
        ),
      );
    }
    return Column(
      key: const Key('season-preview-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.seasonPlanPreviewTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(l10n.seasonPlanPreviewHint(preview.plans.length),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        for (var i = 0; i < preview.plans.length; i++) ...[
          Card(
            key: Key('season-plan-$i'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(preview.plans[i].name,
                      style: theme.textTheme.titleSmall),
                  Text(l10n.seasonPlanPlanWindow(
                      day(preview.plans[i].startDate),
                      day(preview.plans[i].endDate),
                      preview.plans[i].weeks)),
                  Text(l10n.seasonPlanPlanGoal(
                      formatDistanceForPref(preview.plans[i].goalDistanceM),
                      day(preview.plans[i].endDate))),
                  if (preview.plans[i].goalTimeSec != null)
                    Text(l10n.seasonPlanPlanGoalTime(
                        formatRaceGoalTimeS(preview.plans[i].goalTimeSec!))),
                  if (preview.plans[i].races.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(l10n.seasonPlanPlanRaces,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    for (final r in preview.plans[i].races)
                      Text(l10n.seasonPlanPlanRaceLine(
                        seasonPriorityLetter(r.priority),
                        r.name,
                        formatDistanceForPref(r.distanceM),
                        day(r.date),
                      )),
                  ],
                  if (_created.any((c) => c.index == i))
                    Text(l10n.seasonPlanPlanCreated,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          if (i < preview.gaps.length)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                l10n.seasonPlanRecoveryLine(
                  preview.gaps[i].afterRace,
                  preview.gaps[i].days,
                  day(preview.gaps[i].from),
                  day(preview.gaps[i].to),
                ),
                key: Key('season-gap-$i'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
        ],
        if (preview.unplaced.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            key: const Key('season-unplaced'),
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.seasonPlanUnplacedTitle,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: cs.onSecondaryContainer)),
                for (final u in preview.unplaced)
                  Text(_unplacedText(l10n, u, day),
                      style: TextStyle(color: cs.onSecondaryContainer)),
                Text(l10n.seasonPlanUnplacedHint,
                    style: TextStyle(color: cs.onSecondaryContainer)),
              ],
            ),
          ),
        ],
        if (_createError != null) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(_createError!,
                key: const Key('season-create-error'),
                style: TextStyle(color: cs.error)),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('season-create'),
          onPressed: _creating ? null : () => _create(l10n),
          child: Text(_creating
              ? l10n.seasonPlanCreating
              : _failedIndex != null
                  ? l10n.seasonPlanRetry
                  : l10n.seasonPlanCreateButton(preview.plans.length)),
        ),
      ],
    );
  }
}

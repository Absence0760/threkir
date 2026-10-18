import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui_kit/ui_kit.dart';

import '../column_limits.dart';
import '../comeback.dart';
import '../preferences.dart' show activeDistanceUnit;
import '../backend_timeout.dart';
import '../auth_error.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../l10n/number_format.dart';
import '../metrics.dart';
import '../plan_ramp.dart';
import '../plan_overlap.dart';
import '../plan_races.dart' show raceGoalMaxHours;
import '../plan_request_client.dart';
import '../plan_start.dart';
import '../pro_sellable.dart';
import '../race_plan_preset.dart';
import '../race_predictor.dart' show EffortForPrediction, goalAheadOfRecentRuns;
import '../social_service.dart' show ClubView, SocialService;
import '../plan_labels.dart';
import '../starter_plans.dart';
import '../training.dart';
import '../training_labels.dart';
import '../training_service.dart';
import '../widgets/ai_disclosure_notice.dart';
import '../widgets/metric_label.dart';
import '../widgets/plan_import_sheet.dart';
import '../widgets/plan_overlap_dialog.dart';
import '../widgets/top_banner.dart';
import 'plan_detail_screen.dart';
import 'season_plan_screen.dart';

/// The wizard's first question. It decides which fields apply: a runner who
/// has never run gets the walk-run plan and none of the race fields; a runner
/// building up picks a distance but no goal time; a runner training for a race
/// sees everything. Mirrors `StartingPoint` in web PlanEditor.
enum _StartingPoint { newRunner, building, race }

/// A club plan template paired with the owning club's display name, for the
/// "Start from a club template" picker. Mirrors the web `/plans/new`
/// template-picker option shape.
class _TemplateOption {
  final TrainingPlanRow template;
  final String clubName;
  const _TemplateOption(this.template, this.clubName);
}

/// The description box's input budget, matching web's `maxlength`.
const int kPlanDescriptionMaxChars = 600;

/// What the last AI fill did to the form, kept as facts and localized at
/// build time.
class _AiApplied {
  final List<PlanRequestAssumption> assumptions;
  final bool recent5kFilled;

  /// Set when the description named a race date the dates were sized to.
  final DateTime? raceDate;

  /// Set when the description named a race date the dates could not be sized
  /// to; the start date was left alone.
  final RacePlanRefusal? raceRefusal;

  const _AiApplied({
    required this.assumptions,
    required this.recent5kFilled,
    this.raceDate,
    this.raceRefusal,
  });
}

/// Wizard: goal race + goal time + recent 5K + days/week. Live preview of
/// paces + week outline updates as inputs change. Mirrors the web page.
class PlanNewScreen extends StatefulWidget {
  final TrainingService training;

  /// Optional SocialService injection so tests can drive the club-template
  /// picker with a fake. Production callsites pass `null` and the screen
  /// constructs its own against the global Supabase client.
  final SocialService? social;

  /// Preselect the goal + beginner toggle on mount (the onboarding
  /// "create my training plan" nudge keys these off the runner's
  /// primary_goal). Null → the normal defaults.
  final GoalEvent? initialGoal;
  final bool initialBeginnerWalkRun;

  /// The race the wizard was opened from ("train for this race" on the races
  /// screen), as the listing's own facts rather than as derived dates — the
  /// arithmetic has one home in [racePlanPreset] and is re-derived against
  /// today here, so a screen built from a stale list cannot resurrect a start
  /// date that has since passed (decisions § 606).
  final String? raceDateIso;
  final String? raceName;
  final num? raceDistanceM;

  /// A plain-English description to prefill the "Describe the plan you want"
  /// box with (the Coach's "Build this plan" link). When the box is
  /// available it fills the form once after the first frame.
  final String? initialDescription;

  /// A measured 5K to fill the recent-5K field with (Home's recent-5K
  /// suggestion). Filled, never confirmed: it sets no paces until the runner
  /// turns on the confirm switch.
  final int? initialRecent5kSec;

  /// A start to open on (the plan recap's "Build your next plan", past the
  /// race's recovery). Snapped to a Sunday like a picked date, and ignored
  /// when it is earlier than the wizard's own default. Web: `?start=`.
  final DateTime? initialStartDate;

  /// Used to open the AI disclosure when the plan assistant is refused for
  /// consent. Null resolves the global client at tap time.
  final ApiClient? apiClient;

  /// Test seams for the AI plan assistant: whether the deploy has it live,
  /// and the request itself. Production uses the capability manifest and
  /// [requestPlanInputs].
  final Future<bool> Function()? loadAiPlanAvailable;
  final Future<PlanRequestInputs> Function(String request, String todayIso)?
  requestPlanInputsFn;

  const PlanNewScreen({
    super.key,
    required this.training,
    this.social,
    this.initialGoal,
    this.initialBeginnerWalkRun = false,
    this.raceDateIso,
    this.raceName,
    this.raceDistanceM,
    this.initialDescription,
    this.initialRecent5kSec,
    this.initialStartDate,
    this.apiClient,
    this.loadAiPlanAvailable,
    this.requestPlanInputsFn,
  });

  @override
  State<PlanNewScreen> createState() => _PlanNewScreenState();
}

class _PlanNewScreenState extends State<PlanNewScreen> {
  final _nameCtrl = TextEditingController();
  // Persistent controllers for the numeric fields — creating them inside
  // build() (as the first pass did) resets the cursor every character and
  // makes the boxes nearly unusable. State-owned + disposed below.
  final _goalHoursCtrl = TextEditingController();
  final _goalMinutesCtrl = TextEditingController();
  final _goalSecondsCtrl = TextEditingController();
  final _recent5kMinCtrl = TextEditingController();
  final _recent5kSecCtrl = TextEditingController();
  final _weekOverrideCtrl = TextEditingController();
  final _aiCtrl = TextEditingController();
  final _ultraDistanceCtrl = TextEditingController();

  GoalEvent _goal = GoalEvent.distanceHalf;
  // An ultra goal is stored as `custom` plus its distance — the distance is
  // what the generator plans from — and `_ultraChoice` remembers which entry
  // the runner picked (a [kUltraPresets] id or [_kUltraOther]). Mirrors web
  // PlanEditor.
  String? _ultraChoice;
  double? _ultraDistanceM;
  DateTime _startDate = defaultPlanStart(DateTime.now(), walkRun: false);
  int _daysPerWeek = 4;

  int? _goalHours, _goalMinutes, _goalSeconds;
  int? _recent5kMin, _recent5kSec;
  // Returning runners type an old PR; the engine would treat it as current
  // fitness and prescribe paces that are too fast (injury risk — comeback
  // persona #24). The time only anchors paces once confirmed current;
  // otherwise paces stay on the conservative goal-based fallback.
  bool _recent5kConfirmed = false;
  // Beginner / return-to-run: generate a C25K-style walk-run plan (persona #22).
  bool _beginnerWalkRun = false;
  _StartingPoint _startingPoint = _StartingPoint.race;
  int? _weekOverride;
  bool _busy = false;
  String? _error;
  // Persona-hunt Round 3 finding Woman #3. Pulled lazily on mount
  // and threaded into `generatePlan` so the pace bands reflect the
  // gender-aware calibration when present. Null → unmodified
  // (male-curve) paces, matching pre-fix behaviour.
  TrainingGender _viewerGender;
  // Persona-hunt finding Older #30. Pulled lazily on mount and threaded
  // into `generatePlan` so 50+ runners get the masters recovery
  // calibration (72h hard-day spacing + 3-week cycle). Null → standard
  // schedule.
  int? _viewerAge;
  // The runner's chronic weekly volume, so the preview can say whether the
  // plan's opening week is a step their current training supports. Null until
  // loaded (and on failure) — the note self-hides rather than grading against
  // a base it doesn't have.
  RecentVolume? _recentVolume;
  // The break a returning runner is coming back from, read off the same
  // history. Null when there is none, and until loaded.
  ReturnFromBreak? _returning;
  // A returning runner's plan is eased in unless they turn it off.
  bool _easeBack = true;
  // The last 90 days' qualifying efforts, for checking a goal time against
  // what the runner has actually run. Empty until loaded, and on failure.
  List<EffortForPrediction> _efforts = const [];
  // Null when the wizard was not opened from a race. A refusal is kept rather
  // than discarded: silently falling back to the usual defaults is the one
  // thing that could not explain itself.
  RacePlanPresetResult? _racePreset;

  late final SocialService _social = widget.social ?? SocialService();
  List<_TemplateOption> _templates = const [];
  bool _cloning = false;
  bool _creatingStarter = false;
  // True while an overlap lookup is in flight. It is a network read, so every
  // create path stays disabled across it and a second tap cannot start a
  // second create.
  bool _checkingOverlap = false;
  bool _nameDefaulted = false;
  // The runner's own plan name always beats the extracted one.
  bool _nameTouched = false;

  // "Describe the plan you want". The AI is the interface, never the planner:
  // it only fills the fields below, and the generator builds the plan from
  // them exactly as it does for a hand-filled form. Every failure leaves the
  // manual form as it was.
  bool _aiPlanAvailable = false;
  bool _aiBusy = false;
  PlanRequestErrorKind? _aiError;
  _AiApplied? _aiApplied;
  // The start date the last AI fill derived from a race date. A later fill
  // without a race date puts it back, so the plan stops being sized for a
  // race the new description no longer mentions; a date the runner picked by
  // hand is left alone.
  DateTime? _aiRaceStart;
  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  bool get _startIsDefault =>
      _startDate == defaultPlanStart(_today(), walkRun: _beginnerWalkRun);

  static const _kDayOptions = [3, 4, 5, 6, 7];
  static final _kWalkRunDayOptions = [
    for (var d = 2; d <= kWalkRunMaxDaysPerWeek; d++) d,
  ];
  List<int> get _dayOptions =>
      _beginnerWalkRun ? _kWalkRunDayOptions : _kDayOptions;

  static int _clampDays(int days, bool walkRun) {
    final options = walkRun ? _kWalkRunDayOptions : _kDayOptions;
    return days.clamp(options.first, options.last);
  }

  bool get _showGoalRace => _startingPoint != _StartingPoint.newRunner;
  bool get _showGoalTime =>
      _startingPoint == _StartingPoint.race && !_beginnerWalkRun;
  bool get _showRecent5k =>
      _startingPoint != _StartingPoint.newRunner && !_beginnerWalkRun;

  /// The one place the walk-run choice changes, so the fields that depend on
  /// it follow: the goal drops to 5K, the training days fit a walk-run week,
  /// and a start date the runner never touched moves to the new default.
  /// Mirrors `setWalkRun` in web PlanEditor.
  void _setWalkRun(bool on) {
    final wasDefault = _startIsDefault;
    _beginnerWalkRun = on;
    if (on && _goalDistanceM > kGoalDistancesM[GoalEvent.distance5k]!) {
      _goal = GoalEvent.distance5k;
      _ultraChoice = null;
    }
    _daysPerWeek = _clampDays(_daysPerWeek, on);
    _startDate = wasDefault
        ? defaultPlanStart(_today(), walkRun: on)
        : alignPlanStart(_startDate, walkRun: on);
  }

  void _setStartingPoint(_StartingPoint next) {
    final was = _startingPoint;
    _startingPoint = next;
    if (next == _StartingPoint.newRunner) {
      _setWalkRun(true);
    } else if (was == _StartingPoint.newRunner) {
      _setWalkRun(false);
    }
  }

  static const _kUltraOther = 'ultra_other';
  static const _kUltraLabels = {
    'ultra_50k': '50 km',
    'ultra_56k': '56 km',
    'ultra_90k': '90 km',
    'ultra_100mi': '100 mi',
  };
  static const _kMetresPerMile = 1609.344;

  double get _metresPerUnit =>
      activeDistanceUnit == DistanceUnit.mi ? _kMetresPerMile : 1000;

  /// The preset a distance is, to the metre, or null.
  static String? _ultraPresetFor(double distanceM) {
    for (final p in kUltraPresets) {
      if ((p.distanceM - distanceM).abs() < 1) return p.id;
    }
    return null;
  }

  double get _goalDistanceM => _goal != GoalEvent.custom
      ? kGoalDistancesM[_goal]!
      : _ultraChoice != null
      ? (_ultraDistanceM ?? 0)
      : 10000;

  // An ultra entry whose typed distance is not past the marathon plans
  // nothing: the generator would quietly build a road plan under an ultra
  // label.
  bool get _ultraDistanceInvalid =>
      _ultraChoice != null && !isUltraDistance(_goalDistanceM);

  void _selectUltra(String choice, double distanceM) {
    _ultraChoice = choice;
    _goal = GoalEvent.custom;
    _ultraDistanceM = distanceM;
    final shown = ((distanceM / _metresPerUnit) * 10).round() / 10;
    _ultraDistanceCtrl.text = shown == shown.roundToDouble()
        ? shown.round().toString()
        : shown.toString();
  }

  void _onGoalChanged(String value) {
    if (value == _kUltraOther) {
      _selectUltra(value, _ultraDistanceM ?? 70000);
      return;
    }
    for (final p in kUltraPresets) {
      if (p.id == value) {
        _selectUltra(value, p.distanceM);
        return;
      }
    }
    _ultraChoice = null;
    _goal = goalEventFromDb(value);
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialGoal != null) _goal = widget.initialGoal!;
    _beginnerWalkRun = widget.initialBeginnerWalkRun;
    if (_beginnerWalkRun) {
      _startingPoint = _StartingPoint.newRunner;
      _daysPerWeek = _clampDays(_daysPerWeek, true);
      _startDate = defaultPlanStart(_today(), walkRun: true);
    }
    final linkedStart = widget.initialStartDate;
    if (linkedStart != null) {
      final aligned = alignPlanStart(linkedStart, walkRun: false);
      if (aligned.isAfter(defaultPlanStart(_today(), walkRun: false))) {
        _startDate = aligned;
      }
    }
    _applyRacePreset();
    final suggested = widget.initialRecent5kSec;
    if (suggested != null) {
      _recent5kMin = suggested ~/ 60;
      _recent5kSec = suggested % 60;
      _recent5kMinCtrl.text = '$_recent5kMin';
      _recent5kSecCtrl.text = '$_recent5kSec';
    }
    final description = widget.initialDescription?.trim();
    if (description != null && description.isNotEmpty) {
      _aiCtrl.text = description.length > kPlanDescriptionMaxChars
          ? description.substring(0, kPlanDescriptionMaxChars)
          : description;
    }
    _loadAiPlanAvailability();
    widget.training.fetchViewerGender().then((g) {
      if (!mounted) return;
      setState(() => _viewerGender = g);
    });
    widget.training.fetchViewerAge().then((a) {
      if (!mounted) return;
      setState(() => _viewerAge = a);
    });
    widget.training.fetchPlanRunHistory().then((h) {
      if (!mounted || h == null) return;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      setState(() {
        _recentVolume = recentRunVolume(h.runs, nowMs);
        _returning = returningFromBreak(h.runs, nowMs);
        _efforts = h.efforts;
      });
    });
    _loadTemplates();
  }

  Future<void> _loadAiPlanAvailability() async {
    var available = false;
    try {
      available = await (widget.loadAiPlanAvailable ?? fetchAiPlanAvailable)();
    } catch (e) {
      debugPrint('PlanNewScreen: AI plan capability lookup failed: $e');
    }
    if (!mounted || !available) return;
    setState(() => _aiPlanAvailable = true);
    if (_aiCtrl.text.trim().isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fillFromDescription();
    });
  }

  Future<void> _fillFromDescription() async {
    final text = _aiCtrl.text.trim();
    if (text.isEmpty || _aiBusy) return;
    setState(() {
      _aiBusy = true;
      _aiError = null;
      _aiApplied = null;
    });
    PlanRequestInputs inputs;
    try {
      inputs = await (widget.requestPlanInputsFn ?? requestPlanInputs)(
        text,
        toIsoDate(DateTime.now()),
      );
    } catch (e) {
      if (e is! PlanRequestError) {
        debugPrint('PlanNewScreen: plan assistant request failed: $e');
      }
      if (!mounted) return;
      setState(() {
        _aiError = e is PlanRequestError
            ? e.kind
            : PlanRequestErrorKind.unavailable;
        _aiBusy = false;
      });
      return;
    }
    if (!mounted) return;
    // Its own catch: a fill that throws part-way must not take the wizard
    // down with it — the fields already set stay, the runner edits the rest.
    try {
      _applyPlanInputs(inputs);
    } catch (e) {
      debugPrint('PlanNewScreen: applying plan assistant inputs failed: $e');
      _aiError = PlanRequestErrorKind.unavailable;
    }
    setState(() => _aiBusy = false);
  }

  void _setWeekOverride(int? weeks) {
    _weekOverride = weeks;
    _weekOverrideCtrl.text = weeks == null ? '' : '$weeks';
  }

  /// Mirrors web PlanEditor's `applyPlanInputs`. Mutates state without a
  /// `setState`; the caller rebuilds once afterwards.
  void _applyPlanInputs(PlanRequestInputs inputs) {
    // The fill replaces the plan's shape, so a note about the race the wizard
    // was opened from would now describe dates it no longer holds.
    _racePreset = null;
    final wasDefaultStart = _startIsDefault;
    _beginnerWalkRun = inputs.beginnerWalkRun;
    // A walk-run description is a runner who has never run; a goal time is a
    // race, and has to land somewhere the runner can see it.
    if (inputs.beginnerWalkRun) {
      _startingPoint = _StartingPoint.newRunner;
    } else if (_startingPoint == _StartingPoint.newRunner ||
        inputs.goalTimeSec != null) {
      _startingPoint = _StartingPoint.race;
    }
    _goal = inputs.goalEvent;
    _ultraChoice = null;
    // An ultra arrives as custom plus its distance and selects the matching
    // Ultra entry, so the distance field shows what was heard.
    final ultraM = inputs.goalDistanceM;
    if (inputs.goalEvent == GoalEvent.custom && ultraM != null) {
      _selectUltra(_ultraPresetFor(ultraM) ?? _kUltraOther, ultraM);
    }
    _daysPerWeek = _clampDays(inputs.daysPerWeek, inputs.beginnerWalkRun);
    // A fill replaces the shape of the plan, not just the fields this
    // description happened to name: a second fill must not inherit the first
    // one's length, race start or goal time.
    _setWeekOverride(inputs.weeks);
    if ((inputs.raceDate == null &&
            _aiRaceStart != null &&
            _startDate == _aiRaceStart) ||
        wasDefaultStart) {
      _startDate = defaultPlanStart(_today(), walkRun: _beginnerWalkRun);
    }
    _aiRaceStart = null;
    final goal = inputs.goalTimeSec;
    _goalHours = goal == null ? null : goal ~/ 3600;
    _goalMinutes = goal == null ? null : (goal % 3600) ~/ 60;
    _goalSeconds = goal == null ? null : goal % 60;
    _goalHoursCtrl.text = _goalHours?.toString() ?? '';
    _goalMinutesCtrl.text = _goalMinutes?.toString() ?? '';
    _goalSecondsCtrl.text = _goalSeconds?.toString() ?? '';
    final recent = inputs.recent5kSec;
    if (recent != null) {
      _recent5kMin = recent ~/ 60;
      _recent5kSec = recent % 60;
      _recent5kMinCtrl.text = '$_recent5kMin';
      _recent5kSecCtrl.text = '$_recent5kSec';
      // Never ticked for the runner: whether the time reflects their fitness
      // today is theirs to confirm, and an unconfirmed time leaves the paces
      // on the goal time (or the cautious default without one).
      _recent5kConfirmed = false;
    }
    final planName = inputs.planName?.trim();
    if (planName != null &&
        planName.isNotEmpty &&
        (!_nameTouched || _nameCtrl.text.trim().isEmpty)) {
      final cap = columnLength('training_plans.name');
      _nameCtrl.text = planName.length > cap
          ? planName.substring(0, cap)
          : planName;
    }
    final raceDate = inputs.raceDate;
    RacePlanRefusal? refusal;
    if (raceDate != null) refusal = _applyAiRaceDate(raceDate, inputs.weeks);
    _aiApplied = _AiApplied(
      assumptions: inputs.assumptions,
      recent5kFilled: recent != null,
      raceDate: raceDate != null && refusal == null
          ? DateTime.tryParse(raceDate)
          : null,
      raceRefusal: refusal,
    );
  }

  /// Presets the start date + length so race week contains race day, or
  /// returns why it could not (leaving the dates alone).
  RacePlanRefusal? _applyAiRaceDate(String raceDate, int? requestedWeeks) {
    final result = racePlanPreset(
      raceDateIso: raceDate,
      distanceM: _goalDistanceM,
      todayIso: toIsoDate(DateTime.now()),
    );
    final preset = result.preset;
    if (preset == null) return result.reason ?? RacePlanRefusal.invalid;
    final parsed = DateTime.tryParse(preset.startDate);
    if (parsed == null) return RacePlanRefusal.invalid;
    var start = DateTime(parsed.year, parsed.month, parsed.day);
    var weeks = preset.weeks;
    // A shorter plan the runner asked for still ends on race week: start
    // later rather than earlier. A longer one cannot fit, so the preset wins.
    if (requestedWeeks != null && requestedWeeks < weeks) {
      start = DateTime(
        start.year,
        start.month,
        start.day + (weeks - requestedWeeks) * 7,
      );
      weeks = requestedWeeks;
    }
    _startDate = start;
    _aiRaceStart = start;
    _setWeekOverride(weeks);
    return null;
  }

  /// Opens the AI disclosure from the consent error and, when the runner
  /// accepts, re-runs the fill they were refused. A cancelled or failed
  /// dialog leaves the error and the manual form as they were.
  Future<void> _reviewAiDisclosure() async {
    try {
      final api =
          widget.apiClient ?? (ApiClient.isInitialized ? ApiClient() : null);
      if (api == null) return;
      final recorded = await showAiDisclosureDialog(context, api);
      if (recorded == null || !mounted) return;
      setState(() => _aiError = null);
      await _fillFromDescription();
    } catch (e) {
      debugPrint('PlanNewScreen: AI disclosure review failed: $e');
    }
  }

  /// Size the wizard around the race it was opened from. A distance matching
  /// no standard rung leaves the goal on the wizard's own default and presets
  /// only the dates — the goal dropdown has no custom-distance entry, so
  /// snapping a 50k to the marathon rung would preselect a different race.
  void _applyRacePreset() {
    final raceDateIso = widget.raceDateIso;
    if (raceDateIso == null) return;
    final result = racePlanPreset(
      raceDateIso: raceDateIso,
      distanceM: widget.raceDistanceM,
      todayIso: toIsoDate(DateTime.now()),
    );
    _racePreset = result;
    final preset = result.preset;
    if (preset == null) return;
    if (preset.goalEvent != null) {
      _goal = preset.goalEvent!;
    } else {
      final d = widget.raceDistanceM?.toDouble();
      if (d != null && isUltraDistance(d)) {
        _selectUltra(_ultraPresetFor(d) ?? _kUltraOther, d);
      }
    }
    final start = DateTime.tryParse(preset.startDate);
    if (start != null)
      _startDate = DateTime(start.year, start.month, start.day);
    _weekOverride = preset.weeks;
    _weekOverrideCtrl.text = '${preset.weeks}';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // When the wizard opens preselected to a goal (the onboarding "create my
    // training plan" nudge) the name field would otherwise be empty, leaving
    // the Create button silently disabled on arrival — a dead-end tap. Seed a
    // sensible, editable default so the preset lands ready to create. Needs a
    // localized string, so it runs here (context-ready) not in initState.
    if (_nameDefaulted || _nameCtrl.text.isNotEmpty) return;
    // A race the wizard could not build for gets no name either: the name is
    // the one field that would still claim the race after the dates fell back.
    final raceName = widget.raceName?.trim();
    if (_racePreset?.ok == true && raceName != null && raceName.isNotEmpty) {
      _nameDefaulted = true;
      // The field is capped; a programmatic write bypasses that, so clamp
      // what the listing hands us to the same budget.
      final cap = columnLength('training_plans.name');
      _nameCtrl.text = raceName.length > cap
          ? raceName.substring(0, cap)
          : raceName;
      return;
    }
    if (widget.initialGoal != null || widget.initialBeginnerWalkRun) {
      _nameDefaulted = true;
      final l10n = AppLocalizations.of(context);
      final goal = goalEventLabel(l10n, _goal);
      _nameCtrl.text = _beginnerWalkRun
          ? l10n.planNewDefaultNameBeginner(goal)
          : l10n.planNewDefaultName(goal);
    }
  }

  /// Best-effort fetch of every plan template the viewer can adopt across
  /// their clubs (mirrors web `/plans/new`'s onMount). A failure leaves the
  /// picker hidden — generating from scratch is always available.
  Future<void> _loadTemplates() async {
    try {
      final clubs = await _social.fetchMyClubs().timeout(kBackendLoadTimeout);
      final options = <_TemplateOption>[];
      for (final ClubView c in clubs) {
        final list = await widget.training
            .fetchClubTemplates(c.row.id)
            .timeout(kBackendLoadTimeout);
        for (final t in list) {
          options.add(_TemplateOption(t, c.row.name));
        }
      }
      if (!mounted) return;
      setState(() => _templates = options);
    } catch (_) {
      /* L4 best-effort — leave the picker hidden on any failure. */
    }
  }

  /// Asks what to do with any active plan the new `[_startDate, endIso]`
  /// window overlaps — see [confirmPlanOverlap]. Null means keep them and
  /// don't create.
  Future<PlanOverlapAction?> _confirmOverlap(
    String endIso, {
    DateTime? start,
  }) async {
    setState(() => _checkingOverlap = true);
    try {
      return await confirmPlanOverlap(
        context,
        widget.training,
        startIso: toIsoDate(start ?? _startDate),
        endIso: endIso,
      );
    } finally {
      if (mounted) setState(() => _checkingOverlap = false);
    }
  }

  String _createError(AppLocalizations l10n, Object e) =>
      planOverlapErrorText(context, e) ?? friendlyError(l10n, e);

  /// One sheet for every ready-made plan: the built-in starters and the
  /// templates the runner's clubs have published.
  Future<void> _openReadyMade() async {
    if (_cloning || _creatingStarter || _checkingOverlap) return;
    final picked = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          _ReadyMadePicker(starters: starterPlans, templates: _templates),
    );
    if (!mounted) return;
    if (picked is StarterPlan) await _createStarter(picked);
    if (picked is _TemplateOption) await _cloneTemplate(picked);
  }

  Future<void> _cloneTemplate(_TemplateOption picked) async {
    final l10n = AppLocalizations.of(context);
    final action = await _confirmOverlap(
      clonedPlanEndIso(
        picked.template,
        toIsoDate(_startDate),
        start: planRowStartIso,
        end: planRowEndIso,
      ),
    );
    if (action == null || !mounted) return;
    setState(() => _cloning = true);
    try {
      final newId = await widget.training
          .clonePlanTemplate(
            templateId: picked.template.id,
            startDate: _startDate,
            onOverlap: action,
          )
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              PlanDetailScreen(training: widget.training, planId: newId),
        ),
      );
    } catch (e) {
      debugPrint('Template clone failed: $e');
      if (mounted) {
        setState(() => _cloning = false);
        showTopBanner(
          context,
          planOverlapErrorText(context, e) ?? l10n.planNewTemplateCloneFailed,
        );
      }
    }
  }

  /// A starter begins on its own default unless the runner picked a date, in
  /// which case that date is used, moved to a Sunday unless the starter is
  /// walk-run.
  Future<void> _createStarter(StarterPlan picked) async {
    final l10n = AppLocalizations.of(context);
    final start = _startIsDefault
        ? starterStartDate(picked.id, _today())
        : alignPlanStart(_startDate, walkRun: picked.beginnerWalkRun);
    final generated = instantiateStarter(picked.id, start, age: _viewerAge);
    if (generated == null) return;
    final action = await _confirmOverlap(
      toIsoDate(generated.endDate),
      start: start,
    );
    if (action == null || !mounted) return;
    setState(() => _creatingStarter = true);
    try {
      final plan = await widget.training
          .createPlan(
            name: starterPlanName(l10n, picked.id),
            goalEvent: picked.goalEvent,
            goalDistanceM: generated.goalDistanceM,
            startDate: start,
            daysPerWeek: picked.daysPerWeek,
            generated: generated,
            onOverlap: action,
          )
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              PlanDetailScreen(training: widget.training, planId: plan.id),
        ),
      );
    } catch (e) {
      debugPrint('Starter plan create failed: $e');
      if (mounted) {
        setState(() => _creatingStarter = false);
        showTopBanner(
          context,
          planOverlapErrorText(context, e) ?? l10n.planNewStarterCreateFailed,
        );
      }
    }
  }

  void _openSeason() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SeasonPlanScreen(
          training: widget.training,
          apiClient: widget.apiClient,
          loadAiAvailable: widget.loadAiPlanAvailable,
        ),
      ),
    );
  }

  Future<void> _importPlan() async {
    final planId = await showPlanImportSheet(context, widget.training);
    if (planId == null || !mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) =>
            PlanDetailScreen(training: widget.training, planId: planId),
      ),
    );
  }

  /// A hidden goal time is not applied: a runner who typed one and then said
  /// they are not training for a race gets the plan they now describe.
  int? get _goalTimeSec {
    if (!_showGoalTime) return null;
    if (_goalHours == null && _goalMinutes == null && _goalSeconds == null) {
      return null;
    }
    return (_goalHours ?? 0) * 3600 +
        (_goalMinutes ?? 0) * 60 +
        (_goalSeconds ?? 0);
  }

  int? get _recent5kTotal {
    if (_recent5kMin == null && _recent5kSec == null) return null;
    return (_recent5kMin ?? 0) * 60 + (_recent5kSec ?? 0);
  }

  // Only anchor paces on the entered time once the runner confirms it's
  // current; an entered-but-unconfirmed time is treated as absent.
  int? get _recent5kApplied =>
      _recent5kConfirmed && _showRecent5k ? _recent5kTotal : null;

  // Shown only once the time is a whole one: a warning on the first digit
  // typed is noise, and a time under a minute is not a 5K.
  bool get _recent5kComplete =>
      _recent5kMin != null && _recent5kMin! > 0 && _recent5kSec != null;
  bool get _recent5kNeedsConfirm => _recent5kComplete && !_recent5kConfirmed;

  /// The opening-week ceiling the plan is eased in under, or null when it is
  /// not: no break to come back from, the runner turned it off, or a walk-run
  /// plan, whose opening week is already far below it.
  double? get _returnCapM =>
      _returning != null && _easeBack && !_beginnerWalkRun
      ? _returning!.openingCapM
      : null;

  GeneratedPlan? _preview() {
    if (_ultraDistanceInvalid) return null;
    try {
      final generated = generatePlan(
        GeneratePlanInput(
          goalEvent: _goal,
          goalDistanceM: _goalDistanceM,
          startDate: _startDate,
          daysPerWeek: _daysPerWeek,
          goalTimeSec: _goalTimeSec,
          recent5kSec: _recent5kApplied,
          weeks: _weekOverride,
          gender: _viewerGender,
          age: _viewerAge,
          beginnerWalkRun: _beginnerWalkRun,
        ),
      );
      final cap = _returnCapM;
      if (cap == null) return generated;
      return GeneratedPlan(
        weeks: capReturnRamp(generated.weeks, cap, generated.paces.easy),
        paces: generated.paces,
        vdot: generated.vdot,
        endDate: generated.endDate,
        goalDistanceM: generated.goalDistanceM,
        pacesAreFallback: generated.pacesAreFallback,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _busy || _checkingOverlap || _numbersInvalid) return;
    final preview = _preview();
    if (preview == null) return;
    final action = await _confirmOverlap(toIsoDate(preview.endDate));
    if (action == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final plan = await widget.training
          .createPlan(
            name: name,
            goalEvent: _goal,
            goalDistanceM: preview.goalDistanceM,
            goalTimeSec: _goalTimeSec,
            recent5kSec: _recent5kApplied,
            startDate: _startDate,
            daysPerWeek: _daysPerWeek,
            generated: preview,
            onOverlap: action,
          )
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              PlanDetailScreen(training: widget.training, planId: plan.id),
        ),
      );
    } catch (e) {
      debugPrint('PlanNewScreen._submit failed: $e');
      if (mounted) {
        setState(() => _error = _createError(AppLocalizations.of(context), e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _goalHoursCtrl.dispose();
    _goalMinutesCtrl.dispose();
    _goalSecondsCtrl.dispose();
    _recent5kMinCtrl.dispose();
    _recent5kSecCtrl.dispose();
    _weekOverrideCtrl.dispose();
    _aiCtrl.dispose();
    _ultraDistanceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final l10n = AppLocalizations.of(context);
    final today = _today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate.isBefore(today) ? today : _startDate,
      firstDate: today,
      lastDate: DateTime(today.year, today.month, today.day + 365),
      helpText: _beginnerWalkRun
          ? l10n.planNewStartDatePickerHelpWalkRun
          : l10n.planNewStartDatePickerHelp,
      // Every day role the generator emits is an offset from day 0, which it
      // treats as the Sunday long run, so a non-Sunday start shifts the whole
      // week. Web can only snap the value afterwards; the Material picker can
      // refuse it in both calendar and keyboard modes, so it does. A walk-run
      // plan has no weekday roles and may start on any day (issue #1186).
      selectableDayPredicate: (d) =>
          planStartAllowed(d, walkRun: _beginnerWalkRun),
    );
    if (!mounted || picked == null) return;
    setState(
      () => _startDate = DateTime(picked.year, picked.month, picked.day),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    final preview = _preview();
    final raceNote = _raceNote(l10n);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final nameEmpty = _nameCtrl.text.trim().isEmpty;
    final canCreate =
        !nameEmpty &&
        !_busy &&
        !_checkingOverlap &&
        !_numbersInvalid &&
        preview != null;
    final goalAhead =
        preview != null &&
            _showGoalTime &&
            _recent5kApplied == null &&
            !_beginnerWalkRun
        ? goalAheadOfRecentRuns(_goalDistanceM, _goalTimeSec, _efforts)
        : null;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.planNewTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_aiPlanAvailable) ...[
            _aiCard(theme, l10n),
            const SizedBox(height: 12),
          ],
          _readyMadeCard(theme, l10n),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(l10n.planNewBuildOwn, style: muted),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 16),
          if (raceNote != null) ...[
            Text(raceNote, key: const Key('plan-new-race-note'), style: muted),
            const SizedBox(height: 12),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SectionLabel(l10n.planNewStartingPoint),
                  RadioGroup<_StartingPoint>(
                    groupValue: _startingPoint,
                    onChanged: (v) {
                      if (v != null) setState(() => _setStartingPoint(v));
                    },
                    child: Column(
                      children: [
                        for (final (sp, title, hint) in [
                          (
                            _StartingPoint.newRunner,
                            l10n.planNewStartingPointNew,
                            l10n.planNewStartingPointNewHint,
                          ),
                          (
                            _StartingPoint.building,
                            l10n.planNewStartingPointBuilding,
                            l10n.planNewStartingPointBuildingHint,
                          ),
                          (
                            _StartingPoint.race,
                            l10n.planNewStartingPointRace,
                            l10n.planNewStartingPointRaceHint,
                          ),
                        ])
                          RadioListTile<_StartingPoint>(
                            key: Key('plan-new-starting-${sp.name}'),
                            value: sp,
                            contentPadding: EdgeInsets.zero,
                            title: Text(title),
                            subtitle: Text(hint),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: l10n.planNewNameLabel,
                      hintText: l10n.planNewNameHint,
                      helperText: l10n.planNewNameHelp,
                      helperMaxLines: 3,
                      errorText: _nameTouched && nameEmpty
                          ? l10n.planNewNameRequired
                          : null,
                    ),
                    maxLength: columnLength('training_plans.name'),
                    // Re-evaluate the Create button's enabled state as the
                    // name is typed.
                    onChanged: (_) => setState(() => _nameTouched = true),
                  ),
                  if (_showGoalRace) ...[
                    const SizedBox(height: 12),
                    _SectionLabel(l10n.planNewGoalRace),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final (value, label) in [
                          for (final g in const [
                            GoalEvent.distance5k,
                            GoalEvent.distance10k,
                            GoalEvent.distanceHalf,
                            GoalEvent.distanceFull,
                          ])
                            (goalEventDbValue(g), goalEventLabel(l10n, g)),
                          for (final p in kUltraPresets)
                            (p.id, _kUltraLabels[p.id]!),
                          (_kUltraOther, l10n.planNewUltraOther),
                        ])
                          ChoiceChip(
                            key: Key('plan-new-goal-$value'),
                            label: Text(label),
                            selected:
                                (_ultraChoice ?? goalEventDbValue(_goal)) ==
                                value,
                            onSelected: (_) =>
                                setState(() => _onGoalChanged(value)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(l10n.planNewGoalRaceHint, style: muted),
                  ],
                  if (_showGoalRace && _ultraChoice != null) ...[
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('plan-new-ultra-distance'),
                      controller: _ultraDistanceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: l10n.planNewUltraDistance(
                          activeDistanceUnit == DistanceUnit.mi ? 'mi' : 'km',
                        ),
                        helperText: l10n.planNewUltraDistanceHint,
                        helperMaxLines: 4,
                        errorText: _ultraDistanceInvalid
                            ? l10n.planNewUltraDistanceTooShort
                            : null,
                        errorMaxLines: 3,
                      ),
                      onChanged: (s) {
                        final n = double.tryParse(
                          s.trim().replaceAll(',', '.'),
                        );
                        setState(
                          () => _ultraDistanceM =
                              n == null || !n.isFinite || n <= 0
                              ? null
                              : n * _metresPerUnit,
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 16),
                  InkWell(
                    key: const Key('plan-new-start-date'),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    onTap: _pickStartDate,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: l10n.planNewStartDate,
                        helperText: _beginnerWalkRun
                            ? l10n.planNewStartDateHintWalkRun
                            : l10n.planNewStartDateHint,
                        helperMaxLines: 3,
                        suffixIcon: const Icon(Icons.calendar_today),
                      ),
                      child: Text(formatDateMed(_startDate, tag)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SectionLabel(l10n.planNewDaysPerWeek),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final n in _dayOptions)
                        ChoiceChip(
                          key: Key('plan-new-days-$n'),
                          label: Text(l10n.planNewDaysOption(n)),
                          selected: _daysPerWeek == n,
                          onSelected: (_) => setState(() => _daysPerWeek = n),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _beginnerWalkRun
                        ? l10n.planNewDaysPerWeekWalkRunHint
                        : l10n.planNewDaysPerWeekHint,
                    style: muted,
                  ),
                  if (_showGoalTime) ...[
                    const SizedBox(height: 16),
                    _SectionLabel(l10n.planNewGoalTimeSection),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _numField(
                            _goalHoursCtrl,
                            (v) => setState(() => _goalHours = v),
                            0,
                            raceGoalMaxHours,
                            labelText: l10n.planNewHoursLabel,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _numField(
                            _goalMinutesCtrl,
                            (v) => setState(() => _goalMinutes = v),
                            0,
                            59,
                            labelText: l10n.planNewMinutesLabel,
                            key: const Key('planNewGoalMinutes'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _numField(
                            _goalSecondsCtrl,
                            (v) => setState(() => _goalSeconds = v),
                            0,
                            59,
                            labelText: l10n.planNewSecondsLabel,
                            last: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(l10n.planNewGoalTimeHint, style: muted),
                    if (goalAhead != null) ...[
                      const SizedBox(height: 8),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          l10n.planNewGoalAheadOfRecent(
                            fmtHms(goalAhead.round()),
                          ),
                          key: const Key('plan-new-goal-ahead'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                  if (_startingPoint != _StartingPoint.newRunner) ...[
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      value: _beginnerWalkRun,
                      onChanged: (v) => setState(() => _setWalkRun(v ?? false)),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(l10n.planNewBeginnerTitle),
                      subtitle: Text(l10n.planNewBeginnerSubtitle),
                    ),
                  ],
                  // A walk-run plan is duration-based intervals: its paces are
                  // not anchored on a 5K time, and a runner who has never run
                  // has no recent 5K to enter.
                  if (_showRecent5k) ...[
                    const SizedBox(height: 12),
                    _SectionLabel(l10n.planNewRecent5kSection),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _numField(
                            _recent5kMinCtrl,
                            (v) => setState(() => _recent5kMin = v),
                            0,
                            59,
                            labelText: l10n.planNewMinutesLabel,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _numField(
                            _recent5kSecCtrl,
                            (v) => setState(() => _recent5kSec = v),
                            0,
                            59,
                            labelText: l10n.planNewSecondsLabel,
                            last: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    MetricSentence(
                      metric: Metric.riegel,
                      sentence: 'plan',
                      style: muted,
                    ),
                    if (widget.initialRecent5kSec != null &&
                        _recent5kTotal == widget.initialRecent5kSec &&
                        !_recent5kConfirmed)
                      Padding(
                        key: const Key('plan-new-recent5k-suggested'),
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(l10n.planNewRecent5kSuggested,
                            style: muted),
                      ),
                    if (_recent5kComplete)
                      SwitchListTile(
                        key: const Key('plan-new-recent5k-confirm'),
                        value: _recent5kConfirmed,
                        onChanged: (v) =>
                            setState(() => _recent5kConfirmed = v),
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.planNewRecent5kConfirm),
                        subtitle: Text(l10n.planNewRecent5kConfirmHint),
                      ),
                    if (_recent5kNeedsConfirm)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          l10n.planNewRecent5kWarning,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 16),
                  _numField(
                    _weekOverrideCtrl,
                    (v) => setState(() => _weekOverride = v),
                    4,
                    24,
                    labelText: l10n.planNewOverrideLabel(
                      _beginnerWalkRun
                          ? walkRunDefaultWeeks()
                          : defaultPlanWeeks(_goal, _goalDistanceM),
                    ),
                    helperText: l10n.planNewOverrideHelp,
                    last: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (preview != null) _buildPreview(theme, l10n, preview),
        ],
      ),
      bottomNavigationBar: _actionBar(theme, l10n, preview, canCreate, tag),
    );
  }

  /// Cancel and Create, pinned under the form so neither scrolls out of
  /// sight, with the plan's length and end date beside them and a create
  /// failure announced right above.
  Widget _actionBar(
    ThemeData theme,
    AppLocalizations l10n,
    GeneratedPlan? preview,
    bool canCreate,
    String tag,
  ) {
    final error = _error;
    return Material(
      elevation: 3,
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error != null)
                Semantics(
                  liveRegion: true,
                  child: Container(
                    key: const Key('plan-new-error'),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      error,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              if (preview != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    l10n.planNewSummary(
                      preview.weeks.length,
                      formatDateMed(preview.endDate, tag),
                    ),
                    key: const Key('plan-new-summary'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.planNewCancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: canCreate ? _submit : null,
                      child: _busy
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                                const SizedBox(width: 8),
                                Flexible(child: Text(l10n.planNewCreating)),
                              ],
                            )
                          : Text(l10n.planNewCreate),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _aiAssumptionLabel(AppLocalizations l10n, PlanRequestAssumption a) =>
      switch (a) {
        PlanRequestAssumption.goalEventDefault =>
          l10n.planNewAiAssumptionGoalEventDefault,
        PlanRequestAssumption.daysPerWeekDefault =>
          l10n.planNewAiAssumptionDaysDefault,
        PlanRequestAssumption.daysPerWeekClamped =>
          l10n.planNewAiAssumptionDaysClamped,
        PlanRequestAssumption.weeksClamped =>
          l10n.planNewAiAssumptionWeeksClamped,
        PlanRequestAssumption.raceDateDropped =>
          l10n.planNewAiAssumptionRaceDateDropped,
        PlanRequestAssumption.goalTimeDropped =>
          l10n.planNewAiAssumptionGoalTimeDropped,
        PlanRequestAssumption.recent5kDropped =>
          l10n.planNewAiAssumptionRecent5kDropped,
        PlanRequestAssumption.beginner5k => l10n.planNewAiAssumptionBeginner5k,
      };

  String? _aiRaceLine(AppLocalizations l10n, _AiApplied applied) {
    final refusal = applied.raceRefusal;
    if (refusal != null) {
      return switch (refusal) {
        RacePlanRefusal.past => l10n.planNewAiRacePast,
        RacePlanRefusal.tooSoon => l10n.planNewAiRaceTooSoon,
        RacePlanRefusal.invalid => l10n.planNewAiRaceInvalid,
      };
    }
    final date = applied.raceDate;
    if (date == null) return null;
    return l10n.planNewAiRaceApplied(
      formatDateMed(date, localeToTag(Localizations.localeOf(context))),
    );
  }

  Widget _aiCard(ThemeData theme, AppLocalizations l10n) {
    final cs = theme.colorScheme;
    final applied = _aiApplied;
    final error = _aiError;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    return Card(
      key: const Key('plan-new-ai-card'),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        // Open on arrival only when there is something in it already: a
        // description handed in from the Coach. Otherwise the form leads.
        initiallyExpanded: _aiCtrl.text.trim().isNotEmpty,
        leading: Icon(Icons.auto_awesome, color: cs.primary),
        title: Text(l10n.planNewAiTitle),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.planNewAiHint, style: muted),
          const SizedBox(height: 10),
          TextField(
            key: const Key('plan-new-ai-field'),
            controller: _aiCtrl,
            enabled: !_aiBusy,
            minLines: 3,
            maxLines: 6,
            maxLength: kPlanDescriptionMaxChars,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l10n.planNewAiTitle,
              hintText: l10n.planNewAiPlaceholder,
              hintMaxLines: 3,
              alignLabelWithHint: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 4),
          FilledButton.tonalIcon(
            key: const Key('plan-new-ai-fill'),
            onPressed: (_aiBusy || _aiCtrl.text.trim().isEmpty)
                ? null
                : _fillFromDescription,
            icon: _aiBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.edit_note, size: 18),
            label: Text(_aiBusy ? l10n.planNewAiWorking : l10n.planNewAiButton),
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Container(
                key: const Key('plan-new-ai-error'),
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(switch (error) {
                      PlanRequestErrorKind.consent =>
                        l10n.planNewAiErrorConsent,
                      PlanRequestErrorKind.dailyLimit =>
                        l10n.planNewAiErrorDailyLimit,
                      _ => l10n.planNewAiErrorFallback,
                    }, style: TextStyle(color: cs.onErrorContainer)),
                    if (error == PlanRequestErrorKind.consent)
                      TextButton(
                        key: const Key('plan-new-ai-review-disclosure'),
                        onPressed: _reviewAiDisclosure,
                        child: Text(l10n.planNewAiReviewDisclosure),
                      ),
                  ],
                ),
              ),
            ),
          ],
          if (applied != null) ...[
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Container(
                key: const Key('plan-new-ai-status'),
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.planNewAiAppliedTitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final line in [
                      l10n.planNewAiAppliedGenerator,
                      ?_aiRaceLine(l10n, applied),
                      if (applied.recent5kFilled) l10n.planNewAiAppliedRecent5k,
                      for (final a in applied.assumptions)
                        _aiAssumptionLabel(l10n, a),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '\u2022 $line',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSecondaryContainer,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The built-in starters and the runner's club templates behind one row,
  /// so the ready-made routes read as an alternative to the form rather than
  /// as its main action.
  Widget _readyMadeCard(ThemeData theme, AppLocalizations l10n) {
    final busy = _creatingStarter || _cloning;
    return Card(
      key: const Key('plan-new-ready-made'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.planNewReadyMadeTitle,
                style: theme.textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.planNewReadyMadeBody,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  key: const Key('plan-new-ready-made-open'),
                  onPressed: busy || _checkingOverlap ? null : _openReadyMade,
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.library_books_outlined, size: 18),
                  label: Text(
                    _creatingStarter
                        ? l10n.planNewStarterCreating
                        : _cloning
                        ? l10n.planNewTemplateCloning
                        : l10n.planNewReadyMadeButton,
                  ),
                ),
                TextButton.icon(
                  key: const Key('planNewImport'),
                  onPressed: _importPlan,
                  icon: const Icon(Icons.content_paste, size: 18),
                  label: Text(l10n.planNewImportButton),
                ),
                TextButton.icon(
                  key: const Key('planNewSeason'),
                  onPressed: _openSeason,
                  icon: const Icon(Icons.event_note, size: 18),
                  label: Text(l10n.seasonPlanTitle),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// What the wizard says about the race it was opened from — either that the
  /// dates are sized to it, or why they are the usual defaults instead. Null
  /// when there was no race.
  String? _raceNote(AppLocalizations l10n) {
    final result = _racePreset;
    if (result == null) return null;
    final preset = result.preset;
    if (preset != null) return l10n.planNewRaceAnchored(preset.weeks);
    return switch (result.reason!) {
      RacePlanRefusal.past => l10n.planNewRacePast,
      RacePlanRefusal.tooSoon => l10n.planNewRaceTooSoon,
      RacePlanRefusal.invalid => l10n.planNewRaceUnreadable,
    };
  }

  /// How the plan compares with what the runner has actually been running,
  /// or null when there is nothing worth saying. Recomputed on every build,
  /// so dropping a training day shows the ramp easing in real time.
  String? _rampMessage(AppLocalizations l10n, GeneratedPlan p, bool isWalkRun) {
    final recent = _recentVolume;
    if (recent == null) return null;
    final weeks = [
      for (final w in p.weeks)
        PlanWeekVolume(weekIndex: w.weekIndex, targetVolumeM: w.targetVolumeM),
    ];
    final check = planRampCheck(
      openingWeekVolumeM(weeks),
      peakWeekVolumeM(weeks),
      recent,
    );
    if (!shouldSurfaceRampNote(check, beginnerWalkRun: isWalkRun)) return null;
    final recentKm = fmtKm(check.recentWeeklyM, 0);
    // Each verdict quotes the week it was graded on: the safety warnings are
    // about the first step, the under-cooked one about the peak.
    if (check.verdict == PlanRampVerdict.under) {
      return l10n.planNewRampUnder(fmtKm(check.peakWeekM, 0), recentKm);
    }
    final opening = fmtKm(check.openingWeekM, 0);
    if (check.verdict == PlanRampVerdict.elevated) {
      return l10n.planNewRampElevated(opening, recentKm);
    }
    return l10n.planNewRampHigh(opening, recentKm);
  }

  Widget _buildPreview(
    ThemeData theme,
    AppLocalizations l10n,
    GeneratedPlan p,
  ) {
    // A beginner walk-run plan is duration-based intervals, not pace-based —
    // the VDOT badge + the five Daniels pace zones are jargon the runner who
    // ticked "New to running?" can't parse. Detect it from the plan itself
    // (every session is a walk_run workout) and hide the pace panel for it.
    final isWalkRun = p.weeks.any(
      (w) => w.workouts.any((wo) => wo.kind == WorkoutKind.walkRun),
    );
    final returning = _returning;
    final returnMessage = returning != null && !isWalkRun
        ? l10n.planNewReturnBody(
            returning.layoffWeeks,
            fmtKm(returning.preLayoffWeeklyM, 0),
            fmtKm(returning.openingCapM, 0),
          )
        : null;
    final rampMessage = returnMessage == null
        ? _rampMessage(l10n, p, isWalkRun)
        : null;
    // The ramp check has nothing to grade a runner with too little recent
    // running against. Said out loud rather than left silent, because that
    // runner is the one a big first week hurts, unless the plan is walk-run,
    // which is the gentle start this note would suggest.
    final recent = _recentVolume;
    final thinHistory =
        returnMessage == null &&
            rampMessage == null &&
            !isWalkRun &&
            recent != null &&
            recent.activeWeeks < kMinActiveWeeks
        ? l10n.planNewThinHistory(
            fmtKm(
              openingWeekVolumeM([
                for (final w in p.weeks)
                  PlanWeekVolume(
                    weekIndex: w.weekIndex,
                    targetVolumeM: w.targetVolumeM,
                  ),
              ]),
              0,
            ),
          )
        : null;
    return Card(
      key: const Key('plan-new-preview'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.planNewPreviewTitle,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (!isWalkRun) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                children: [
                  _pacePill(theme, l10n.planNewPaceEasy, p.paces.easy),
                  _pacePill(theme, l10n.planNewPaceMarathon, p.paces.marathon),
                  _pacePill(theme, l10n.planNewPaceTempo, p.paces.tempo),
                  _pacePill(theme, l10n.planNewPaceInterval, p.paces.interval),
                  _pacePill(theme, l10n.planNewPaceRep, p.paces.repetition),
                ],
              ),
              if (p.pacesAreFallback) ...[
                const SizedBox(height: 6),
                Text(
                  l10n.planNewPacesFallback,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              if (p.vdot != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        metricText(
                          l10n,
                          Metric.vdot,
                          variant: 'daniels',
                          args: {
                            'value': formatFixed(p.vdot!, 1, activeLocaleTag),
                          },
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const MetricInfoButton(metric: Metric.vdot),
                  ],
                ),
              ],
            ],
            if (returnMessage != null)
              _note(
                theme,
                key: const Key('plan-new-return-note'),
                title: l10n.planNewReturnTitle,
                body: returnMessage,
                children: [
                  SwitchListTile(
                    key: const Key('plan-new-ease-back'),
                    value: _easeBack,
                    onChanged: (v) => setState(() => _easeBack = v),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.planNewReturnEaseBack),
                  ),
                  OutlinedButton(
                    onPressed: () => setState(() => _setWalkRun(true)),
                    child: Text(l10n.planNewReturnWalkRun),
                  ),
                ],
              )
            else if (rampMessage != null)
              _note(theme, title: l10n.planNewRampLabel, body: rampMessage)
            else if (thinHistory != null)
              _note(
                theme,
                key: const Key('plan-new-thin-history'),
                title: l10n.planNewRampLabel,
                body: thinHistory,
                children: [
                  OutlinedButton(
                    onPressed: () => setState(() => _setWalkRun(true)),
                    child: Text(l10n.planNewThinHistoryWalkRun),
                  ),
                ],
              ),
            const SizedBox(height: 10),
            Semantics(
              header: true,
              child: Text(
                l10n.planNewWeekOutline,
                style: theme.textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 4),
            for (final w in p.weeks) _previewWeek(theme, l10n, w),
          ],
        ),
      ),
    );
  }

  Widget _note(
    ThemeData theme, {
    Key? key,
    required String title,
    required String body,
    List<Widget> children = const [],
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
        liveRegion: true,
        container: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _pacePill(ThemeData theme, String label, int sec) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            fmtPace(sec),
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// One week of the preview, opening to its day-by-day sessions.
  Widget _previewWeek(ThemeData theme, AppLocalizations l10n, GeneratedWeek w) {
    final tag = localeToTag(Localizations.localeOf(context));
    final active = w.workouts.where((x) => x.kind != WorkoutKind.rest).length;
    return ExpansionTile(
      key: Key('plan-new-week-${w.weekIndex}'),
      tilePadding: EdgeInsets.zero,
      dense: true,
      title: Row(
        children: [
          TextLane(
            width: 30,
            child: Text(
              '#${w.weekIndex + 1}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              planPhaseLabel(l10n, w.phase),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            fmtKm(w.targetVolumeM, 0),
            key: Key('plan-new-week-km-${w.weekIndex}'),
            style: theme.textTheme.bodySmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsetsDirectional.only(start: 30),
        child: Text(
          l10n.planNewSessions(active),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      children: [
        for (final wo in w.workouts)
          if (wo.kind != WorkoutKind.rest)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 30),
              title: Text(workoutKindLabel(l10n, wo.kind)),
              subtitle: Text(formatDateShort(wo.scheduledDate, tag)),
              trailing: wo.targetDistanceM != null
                  ? Text(fmtKm(wo.targetDistanceM!, 1))
                  : wo.targetDurationSeconds != null
                  ? Text(fmtHms(wo.targetDurationSeconds))
                  : null,
            ),
      ],
    );
  }

  Widget _numField(
    TextEditingController controller,
    void Function(int?) onChanged,
    int min,
    int max, {
    required String labelText,
    String? helperText,
    Key? key,
    bool last = false,
  }) {
    return TextField(
      key: key,
      controller: controller,
      keyboardType: TextInputType.number,
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: labelText,
        helperText: helperText,
        helperMaxLines: 3,
        errorText: _outOfRange(controller, min, max)
            ? AppLocalizations.of(context).prefsValueOutOfRange(min, max)
            : null,
        errorMaxLines: 3,
      ),
      onChanged: (s) {
        final n = int.tryParse(s);
        onChanged(n != null && n >= min && n <= max ? n : null);
      },
    );
  }

  // The field keeps what was typed even when it is out of range, so the
  // state value is cleared rather than left at the last valid number: "7"
  // then "75" in minutes used to show 75 and create the plan with 7.
  static bool _outOfRange(TextEditingController c, int min, int max) {
    if (c.text.isEmpty) return false;
    final n = int.tryParse(c.text);
    return n == null || n < min || n > max;
  }

  bool get _numbersInvalid =>
      (_showGoalTime &&
          (_outOfRange(_goalHoursCtrl, 0, raceGoalMaxHours) ||
              _outOfRange(_goalMinutesCtrl, 0, 59) ||
              _outOfRange(_goalSecondsCtrl, 0, 59))) ||
      (_showRecent5k &&
          (_outOfRange(_recent5kMinCtrl, 0, 59) ||
              _outOfRange(_recent5kSecCtrl, 0, 59))) ||
      _outOfRange(_weekOverrideCtrl, 4, 24);
}

/// Every ready-made plan in one sheet: the built-in starters, each with what
/// it asks of the runner, then the templates the runner's clubs published.
/// Pops the chosen [StarterPlan] or [_TemplateOption], or null on cancel.
/// Pure presentation: the parent creates, so a cancel leaves no half-state.
class _ReadyMadePicker extends StatelessWidget {
  final List<StarterPlan> starters;
  final List<_TemplateOption> templates;
  const _ReadyMadePicker({required this.starters, required this.templates});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.planNewReadyMadeTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  _SectionLabel(l10n.planNewReadyMadeBuiltIn),
                  for (final p in starters)
                    ListTile(
                      key: Key('plan-new-starter-${p.id}'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_note),
                      title: Text(starterPlanName(l10n, p.id)),
                      subtitle: Text(
                        starterSummaryText(l10n, p.id) ?? '',
                        style: muted,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, p),
                    ),
                  if (templates.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _SectionLabel(l10n.planNewReadyMadeClubs),
                    for (final o in templates)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.groups_outlined),
                        title: Text(o.template.name),
                        subtitle: Text(o.clubName, style: muted),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.pop(context, o),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.planNewCancel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

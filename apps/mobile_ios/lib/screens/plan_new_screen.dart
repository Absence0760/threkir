import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../column_limits.dart';
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
import '../social_service.dart' show ClubView, SocialService;
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
  DateTime _startDate = _nextSunday();
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
  // Bumped per fill so the dropdowns, which only read their initial value,
  // rebuild showing what the fill chose.
  int _aiFillCount = 0;

  static DateTime _nextSunday() =>
      nextSunday(DateTime.now().add(const Duration(days: 7)));

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
    _applyRacePreset();
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
    widget.training.fetchRecentRunVolume().then((v) {
      if (!mounted) return;
      setState(() => _recentVolume = v);
    });
    _loadTemplates();
  }

  Future<void> _loadAiPlanAvailability() async {
    var available = false;
    try {
      available =
          await (widget.loadAiPlanAvailable ?? fetchAiPlanAvailable)();
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
          text, toIsoDate(DateTime.now()));
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
    _aiFillCount++;
    // The fill replaces the plan's shape, so a note about the race the wizard
    // was opened from would now describe dates it no longer holds.
    _racePreset = null;
    _beginnerWalkRun = inputs.beginnerWalkRun;
    _goal = inputs.goalEvent;
    _ultraChoice = null;
    // An ultra arrives as custom plus its distance and selects the matching
    // Ultra entry, so the distance field shows what was heard.
    final ultraM = inputs.goalDistanceM;
    if (inputs.goalEvent == GoalEvent.custom && ultraM != null) {
      _selectUltra(_ultraPresetFor(ultraM) ?? _kUltraOther, ultraM);
    }
    _daysPerWeek = inputs.daysPerWeek;
    // A fill replaces the shape of the plan, not just the fields this
    // description happened to name: a second fill must not inherit the first
    // one's length, race start or goal time.
    _setWeekOverride(inputs.weeks);
    if (inputs.raceDate == null &&
        _aiRaceStart != null &&
        _startDate == _aiRaceStart) {
      _startDate = _nextSunday();
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
      // today is theirs to confirm, and an unconfirmed time keeps the paces
      // on the conservative goal-based fallback.
      _recent5kConfirmed = false;
    }
    final planName = inputs.planName?.trim();
    if (planName != null &&
        planName.isNotEmpty &&
        (!_nameTouched || _nameCtrl.text.trim().isEmpty)) {
      final cap = columnLength('training_plans.name');
      _nameCtrl.text =
          planName.length > cap ? planName.substring(0, cap) : planName;
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
          start.year, start.month, start.day + (weeks - requestedWeeks) * 7);
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
    if (start != null) _startDate = DateTime(start.year, start.month, start.day);
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
      _nameCtrl.text =
          raceName.length > cap ? raceName.substring(0, cap) : raceName;
      return;
    }
    if (widget.initialGoal != null || widget.initialBeginnerWalkRun) {
      _nameDefaulted = true;
      final l10n = AppLocalizations.of(context);
      final goal = goalEventLabel(_goal);
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
      final clubs =
          await _social.fetchMyClubs().timeout(kBackendLoadTimeout);
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
  Future<PlanOverlapAction?> _confirmOverlap(String endIso) async {
    setState(() => _checkingOverlap = true);
    try {
      return await confirmPlanOverlap(
        context,
        widget.training,
        startIso: toIsoDate(_startDate),
        endIso: endIso,
      );
    } finally {
      if (mounted) setState(() => _checkingOverlap = false);
    }
  }

  String _createError(AppLocalizations l10n, Object e) =>
      planOverlapErrorText(context, e) ?? friendlyError(l10n, e);

  Future<void> _pickTemplate() async {
    if (_templates.isEmpty || _cloning || _checkingOverlap) return;
    final l10n = AppLocalizations.of(context);
    final picked = await showModalBottomSheet<_TemplateOption>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TemplatePicker(options: _templates),
    );
    if (picked == null || !mounted) return;
    final action =
        await _confirmOverlap(clonedPlanEndIso(
            picked.template, toIsoDate(_startDate),
            start: planRowStartIso, end: planRowEndIso));
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
            planOverlapErrorText(context, e) ??
                l10n.planNewTemplateCloneFailed);
      }
    }
  }

  String _starterName(AppLocalizations l10n, String id) {
    switch (id) {
      case 'c25k':
        return l10n.planNewStarterC25k;
      case 'half_12wk':
        return l10n.planNewStarterHalf12;
      case 'marathon_16wk':
        return l10n.planNewStarterMarathon16;
      default:
        return id;
    }
  }

  Future<void> _pickStarter() async {
    if (_creatingStarter || _checkingOverlap) return;
    final l10n = AppLocalizations.of(context);
    final picked = await showModalBottomSheet<StarterPlan>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _StarterPicker(
        plans: starterPlans,
        nameFor: (id) => _starterName(l10n, id),
      ),
    );
    if (picked == null || !mounted) return;
    final generated = instantiateStarter(picked.id, _startDate, age: _viewerAge);
    if (generated == null) return;
    final action = await _confirmOverlap(toIsoDate(generated.endDate));
    if (action == null || !mounted) return;
    setState(() => _creatingStarter = true);
    try {
      final plan = await widget.training
          .createPlan(
            name: _starterName(l10n, picked.id),
            goalEvent: picked.goalEvent,
            goalDistanceM: generated.goalDistanceM,
            startDate: _startDate,
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
            planOverlapErrorText(context, e) ??
                l10n.planNewStarterCreateFailed);
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

  int? get _goalTimeSec {
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
  int? get _recent5kApplied => _recent5kConfirmed ? _recent5kTotal : null;
  bool get _recent5kNeedsConfirm => _recent5kTotal != null && !_recent5kConfirmed;

  GeneratedPlan? _preview() {
    if (_ultraDistanceInvalid) return null;
    try {
      return generatePlan(GeneratePlanInput(
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
      ));
    } catch (_) {
      return null;
    }
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _busy || _checkingOverlap) return;
    final preview = _preview();
    if (preview == null) return;
    final action = await _confirmOverlap(toIsoDate(preview.endDate));
    if (action == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final plan = await widget.training.createPlan(
        name: name,
        goalEvent: _goal,
        goalDistanceM: preview.goalDistanceM,
        goalTimeSec: _goalTimeSec,
        recent5kSec: _recent5kApplied,
        startDate: _startDate,
        daysPerWeek: _daysPerWeek,
        generated: preview,
        onOverlap: action,
      );
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final preview = _preview();
    final raceNote = _raceNote(l10n);
    // See plans_screen.dart — Samsung's 3-button nav bar isn't auto-padded
    // on screens without a bottom nav. Include it in the ListView bottom
    // padding so the Cancel/Create row sits above the system buttons.
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.planNewTitle)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 32 + bottomInset),
        children: [
          if (_aiPlanAvailable) ...[
            _aiCard(theme, l10n),
            const SizedBox(height: 20),
          ],
          _starterCard(theme, l10n),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('planNewImport'),
              onPressed: _importPlan,
              icon: const Icon(Icons.content_paste, size: 18),
              label: Text(l10n.planNewImportButton),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('planNewSeason'),
              onPressed: _openSeason,
              icon: const Icon(Icons.event_note, size: 18),
              label: Text(l10n.seasonPlanTitle),
            ),
          ),
          const SizedBox(height: 12),
          if (_templates.isNotEmpty) ...[
            _templateCard(theme, l10n),
            const SizedBox(height: 20),
          ],
          if (raceNote != null) ...[
            Text(
              raceNote,
              key: const Key('plan-new-race-note'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: l10n.planNewNameLabel,
              hintText: l10n.planNewNameHint,
            ),
            maxLength: columnLength('training_plans.name'),
            // Re-evaluate the Create button's enabled state as the name is
            // typed — without this the button (which gates on a non-empty
            // name) only un-disables on the next unrelated rebuild.
            onChanged: (_) => setState(() => _nameTouched = true),
          ),
          if (_nameCtrl.text.trim().isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.planNewNameRequiredHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('plan-new-goal-$_aiFillCount'),
            initialValue: _ultraChoice ?? goalEventDbValue(_goal),
            // The widest entry sizes a non-expanded dropdown, and "Other
            // ultra distance" overflows a narrow phone in the longer locales.
            isExpanded: true,
            decoration: InputDecoration(labelText: l10n.planNewGoalRace),
            items: [
              for (final g in const [
                GoalEvent.distance5k,
                GoalEvent.distance10k,
                GoalEvent.distanceHalf,
                GoalEvent.distanceFull,
              ])
                DropdownMenuItem(
                    value: goalEventDbValue(g),
                    child: Text(goalEventLabel(g))),
              for (final p in kUltraPresets)
                DropdownMenuItem(
                    value: p.id, child: Text(_kUltraLabels[p.id]!)),
              DropdownMenuItem(
                  value: _kUltraOther,
                  child: Text(l10n.planNewUltraOther,
                      overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _onGoalChanged(v));
            },
          ),
          if (_ultraChoice != null) ...[
            const SizedBox(height: 12),
            TextField(
              key: const Key('plan-new-ultra-distance'),
              controller: _ultraDistanceCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l10n.planNewUltraDistance(
                    activeDistanceUnit == DistanceUnit.mi ? 'mi' : 'km'),
                helperText: l10n.planNewUltraDistanceHint,
                helperMaxLines: 4,
                errorText: _ultraDistanceInvalid
                    ? l10n.planNewUltraDistanceTooShort
                    : null,
                errorMaxLines: 3,
              ),
              onChanged: (s) {
                final n = double.tryParse(s.trim().replaceAll(',', '.'));
                setState(() => _ultraDistanceM =
                    n == null || !n.isFinite || n <= 0 ? null : n * _metresPerUnit);
              },
            ),
          ],
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today),
            title: Text(l10n.planNewStartDate),
            subtitle: Text(toIsoDate(_startDate)),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _startDate,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                // Every day role the generator emits is an offset from day 0,
                // which it treats as the Sunday long run — so a non-Sunday
                // start shifts the whole week. Web can only snap the value
                // afterwards (`<input type="date">` takes no predicate); the
                // Material picker can refuse it in both calendar and keyboard
                // modes, so it does.
                selectableDayPredicate: isSunday,
              );
              if (!mounted) return;
              if (picked != null) setState(() => _startDate = picked);
            },
          ),
          DropdownButtonFormField<int>(
            key: ValueKey('plan-new-days-$_aiFillCount'),
            initialValue: _daysPerWeek,
            decoration: InputDecoration(labelText: l10n.planNewDaysPerWeek),
            items: [3, 4, 5, 6, 7]
                .map((n) => DropdownMenuItem(
                    value: n, child: Text(l10n.planNewDaysOption(n))))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _daysPerWeek = v);
            },
          ),
          const SizedBox(height: 12),
          _SectionLabel(l10n.planNewGoalTimeSection),
          Row(
            children: [
              Expanded(
                child: _numField(
                  _goalHoursCtrl, 'h',
                  (v) => setState(() => _goalHours = v), 0, raceGoalMaxHours),
              ),
              const Text(' : '),
              Expanded(
                child: _numField(
                  _goalMinutesCtrl, 'm',
                  (v) => setState(() => _goalMinutes = v), 0, 59),
              ),
              const Text(' : '),
              Expanded(
                child: _numField(
                  _goalSecondsCtrl, 's',
                  (v) => setState(() => _goalSeconds = v), 0, 59),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _beginnerWalkRun,
            onChanged: (v) => setState(() => _beginnerWalkRun = v ?? false),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(l10n.planNewBeginnerTitle),
            subtitle: Text(l10n.planNewBeginnerSubtitle),
          ),
          // A beginner walk-run plan is duration-based intervals — its paces
          // aren't anchored on a 5K time, and a runner who ticked "New to
          // running?" has no recent 5K to enter and can't parse "Riegel
          // equivalence". Hide the whole recent-5K helper here, mirroring the
          // VDOT / pace-pill panel that `_buildPreview` already hides in
          // walk-run mode.
          if (!_beginnerWalkRun) ...[
            const SizedBox(height: 12),
            _SectionLabel(l10n.planNewRecent5kSection),
            Row(
              children: [
                Expanded(
                  child: _numField(
                    _recent5kMinCtrl, 'min',
                    (v) => setState(() => _recent5kMin = v), 0, 59),
                ),
                const Text(' : '),
                Expanded(
                  child: _numField(
                    _recent5kSecCtrl, 'sec',
                    (v) => setState(() => _recent5kSec = v), 0, 59),
                ),
              ],
            ),
            const SizedBox(height: 4),
            MetricSentence(
              metric: Metric.riegel,
              sentence: 'plan',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_recent5kTotal != null)
              CheckboxListTile(
                value: _recent5kConfirmed,
                onChanged: (v) =>
                    setState(() => _recent5kConfirmed = v ?? false),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(l10n.planNewRecent5kConfirm),
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
            l10n.planNewOverrideHint,
            (v) => setState(() => _weekOverride = v),
            4,
            24,
            labelText: l10n.planNewOverrideLabel(
                defaultPlanWeeks(_goal, _goalDistanceM)),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (preview != null) _buildPreview(theme, l10n, preview),
          const SizedBox(height: 20),
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
                  onPressed:
                      (_nameCtrl.text.trim().isEmpty ||
                              _busy ||
                              _checkingOverlap ||
                              preview == null)
                          ? null
                          : _submit,
                  child: Text(
                      _busy ? l10n.planNewCreating : l10n.planNewCreate),
                ),
              ),
            ],
          ),
        ],
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
    return l10n.planNewAiRaceApplied(formatDateMed(
        date, localeToTag(Localizations.localeOf(context))));
  }

  Widget _aiCard(ThemeData theme, AppLocalizations l10n) {
    final cs = theme.colorScheme;
    final applied = _aiApplied;
    final error = _aiError;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    return Container(
      key: const Key('plan-new-ai-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(l10n.planNewAiTitle,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
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
              border: const OutlineInputBorder(),
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
                    Text(
                      switch (error) {
                        PlanRequestErrorKind.consent =>
                          l10n.planNewAiErrorConsent,
                        PlanRequestErrorKind.dailyLimit =>
                          l10n.planNewAiErrorDailyLimit,
                        _ => l10n.planNewAiErrorFallback,
                      },
                      style: TextStyle(color: cs.onErrorContainer),
                    ),
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

  Widget _starterCard(ThemeData theme, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.4),
        border: Border.all(color: theme.colorScheme.primary),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fitness_center,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(l10n.planNewStarterTitle,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(l10n.planNewStarterSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed:
                _creatingStarter || _checkingOverlap ? null : _pickStarter,
            icon: _creatingStarter
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add, size: 18),
            label: Text(_creatingStarter
                ? l10n.planNewStarterCreating
                : l10n.planNewStarterButton),
          ),
        ],
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

  Widget _templateCard(ThemeData theme, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.4),
        border: Border.all(color: theme.colorScheme.primary),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.library_books,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(l10n.planNewTemplateTitle,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(l10n.planNewTemplateSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: _cloning || _checkingOverlap ? null : _pickTemplate,
            icon: _cloning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add, size: 18),
            label: Text(_cloning
                ? l10n.planNewTemplateCloning
                : l10n.planNewTemplateButton),
          ),
        ],
      ),
    );
  }

  /// How the plan compares with what the runner has actually been running,
  /// or null when there is nothing worth saying. Recomputed on every build,
  /// so dropping a training day shows the ramp easing in real time.
  String? _rampMessage(
      AppLocalizations l10n, GeneratedPlan p, bool isWalkRun) {
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
      ThemeData theme, AppLocalizations l10n, GeneratedPlan p) {
    // A beginner walk-run plan is duration-based intervals, not pace-based —
    // the VDOT badge + the five Daniels pace zones are jargon the runner who
    // ticked "New to running?" can't parse. Detect it from the plan itself
    // (every session is a walk_run workout) and hide the pace panel for it.
    final isWalkRun = p.weeks
        .any((w) => w.workouts.any((wo) => wo.kind == WorkoutKind.walkRun));
    final rampMessage = _rampMessage(l10n, p, isWalkRun);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.planNewPreviewTitle,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
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
                        metricText(l10n, Metric.vdot, variant: 'daniels', args: {
                          'value': formatFixed(p.vdot!, 1, activeLocaleTag)
                        }),
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ),
                  const MetricInfoButton(metric: Metric.vdot),
                ],
              ),
            ],
          ],
          if (rampMessage != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              container: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.planNewRampLabel,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(rampMessage,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurface)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(l10n.planNewWeekOutline,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.6,
              )),
          const SizedBox(height: 4),
          for (final w in p.weeks.take(6)) _previewRow(theme, l10n, w),
          if (p.weeks.length > 6)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.planNewMoreWeeks(p.weeks.length - 6),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
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
          Text(label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
          const SizedBox(width: 4),
          Text(fmtPace(sec),
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _previewRow(
      ThemeData theme, AppLocalizations l10n, GeneratedWeek w) {
    final active = w.workouts.where((x) => x.kind != WorkoutKind.rest).length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          TextLane(
            width: 30,
            child: Text('#${w.weekIndex + 1}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.primary)),
          ),
          Expanded(
            child: Text(planPhaseLabel(l10n, w.phase),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall),
          ),
          const SizedBox(width: 8),
          Text(fmtKm(w.targetVolumeM, 0),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
          const SizedBox(width: 8),
          Text(l10n.planNewSessions(active),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
        ],
      ),
    );
  }

  Widget _numField(
    TextEditingController controller,
    String hint,
    void Function(int?) onChanged,
    int min,
    int max, {
    String? labelText,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hint,
        isDense: true,
      ),
      onChanged: (s) {
        if (s.isEmpty) {
          onChanged(null);
          return;
        }
        final n = int.tryParse(s);
        if (n != null && n >= min && n <= max) onChanged(n);
      },
    );
  }
}

/// Modal that lists the built-in starter plans and pops the chosen
/// [StarterPlan] (or `null` on cancel). Pure presentation — the parent
/// instantiates + creates so cancel doesn't leave a half-state.
class _StarterPicker extends StatelessWidget {
  final List<StarterPlan> plans;
  final String Function(String id) nameFor;
  const _StarterPicker({required this.plans, required this.nameFor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.planNewStarterPickerTitle,
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: plans.length,
                itemBuilder: (_, i) {
                  final p = plans[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_note),
                    title: Text(nameFor(p.id)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(context, p),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.planNewStarterPickerCancel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Modal that lists the viewer's adoptable club templates and pops the
/// chosen option (or `null` on cancel). Pure presentation — the parent
/// does the clone so cancel doesn't leave a half-state.
class _TemplatePicker extends StatelessWidget {
  final List<_TemplateOption> options;
  const _TemplatePicker({required this.options});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.planNewTemplatePickerTitle,
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (_, i) {
                  final o = options[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_note),
                    title: Text(o.template.name),
                    subtitle: Text(o.clubName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(context, o),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.planNewTemplatePickerCancel),
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
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.7,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

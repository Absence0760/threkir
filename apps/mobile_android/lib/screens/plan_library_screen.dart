import 'dart:async';

import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show EmptyState, ListSkeleton;

import '../auth_error.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../plan_labels.dart';
import '../plan_overlap.dart';
import '../preferences.dart' show formatDistanceForPref;
import '../training.dart';
import '../training_service.dart';
import '../backend_timeout.dart';
import '../widgets/error_state.dart';
import '../widgets/plan_meta_item.dart';
import '../widgets/plan_overlap_dialog.dart';
import '../widgets/sign_in_required_state.dart';
import '../widgets/top_banner.dart';
import 'plan_detail_screen.dart';

/// Public plan library — browse + search published plans any user can
/// clone. Mirrors web `/plans/library`. Tapping a plan opens a preview
/// (PlanLibraryPreviewScreen) with a clone-into-my-account action.
class PlanLibraryScreen extends StatefulWidget {
  final TrainingService training;

  const PlanLibraryScreen({super.key, required this.training});

  @override
  State<PlanLibraryScreen> createState() => _PlanLibraryScreenState();
}

class _PlanLibraryScreenState extends State<PlanLibraryScreen> {
  List<PublicPlanLibraryEntry> _plans = const [];
  bool _loading = true;

  /// True once any answer has landed. A search after that keeps the current
  /// results on screen (under a thin progress line) instead of swapping in a
  /// skeleton every debounce.
  bool _loaded = false;
  bool _error = false;
  bool _signedOut = false;
  String _query = '';
  Timer? _debounce;
  final _searchCtrl = TextEditingController();

  /// Bumped per request, so a slow earlier search can never overwrite the
  /// answer to a newer one.
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_requestSeq;
    setState(() {
      _loading = true;
      _error = false;
      _signedOut = false;
    });
    try {
      // The training_plans template read policy requires authenticated —
      // an anon read returns 0 rows with no error, which rendered as a
      // false "No published plans yet.". Show the sign-in state instead
      // (issue #237). Inside the try so a pre-init bootstrap StateError
      // still lands on the error state rather than masquerading as a
      // signed-out viewer.
      if (widget.training.currentUserId == null) {
        setState(() {
          _signedOut = true;
          _loading = false;
        });
        return;
      }
      final plans = await widget.training
          .fetchPublicPlanLibrary(query: _query)
          .timeout(kBackendLoadTimeout);
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _plans = plans;
        _loading = false;
        _loaded = true;
      });
    } catch (e) {
      debugPrint('PlanLibraryScreen._load failed: $e');
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  void _onSearch(String v) {
    // Rebuild now so the clear button tracks the field, not the debounce.
    setState(() => _query = v);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchCtrl.clear();
    setState(() => _query = '');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final showControls = !_signedOut;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.planLibraryTitle)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showControls) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                l10n.planLibrarySubheading,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: l10n.planLibrarySearchHint,
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          key: const Key('planLibraryClearSearch'),
                          icon: const Icon(Icons.close),
                          tooltip: l10n.commonClearSearch,
                          onPressed: _clearSearch,
                        ),
                ),
                onChanged: _onSearch,
              ),
            ),
            SizedBox(
              height: 2,
              child: _loading && _loaded
                  ? const LinearProgressIndicator(minHeight: 2)
                  : null,
            ),
          ],
          Expanded(
            child: _loading && !_loaded
                ? ListSkeleton(label: l10n.commonLoading, hasLeading: false)
                : _signedOut
                    ? SignInRequiredState(onSignedIn: _load)
                    : _error
                    ? ErrorState(message: l10n.planLibraryLoadError, onRetry: _load)
                    : _plans.isEmpty
                        ? RefreshIndicator(
                            onRefresh: _load,
                            child: EmptyState(
                              icon: _query.trim().isEmpty
                                  ? Icons.public
                                  : Icons.search_off,
                              title: _query.trim().isEmpty
                                  ? l10n.planLibraryEmpty
                                  : l10n.planLibraryEmptySearch(_query.trim()),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _plans.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, i) => _LibraryCard(
                                entry: _plans[i],
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => PlanLibraryPreviewScreen(
                                      training: widget.training,
                                      entry: _plans[i],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

/// The goal and length of a library plan, in the same [PlanMetaItem] style
/// and the same strings the plans list uses.
class _PlanFacts extends StatelessWidget {
  final TrainingPlanRow plan;

  /// The preview counts the weeks it actually loaded; the list only has the
  /// row's date span.
  final int? weeks;

  const _PlanFacts({required this.plan, this.weeks});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        PlanMetaItem(
          icon: Icons.flag_outlined,
          text: planGoalLabel(l10n, plan.goalEvent, plan.goalDistanceM),
        ),
        PlanMetaItem(
          icon: Icons.view_week_outlined,
          text: planLengthLabel(
            l10n,
            weeks ?? planWeekCount(plan.startDate, plan.endDate),
            plan.daysPerWeek,
          ),
        ),
      ],
    );
  }
}

class _LibraryCard extends StatelessWidget {
  final PublicPlanLibraryEntry entry;
  final VoidCallback onTap;

  const _LibraryCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = entry.plan;
    final author = entry.authorHandle ?? l10n.planLibraryAnonymous;
    return Card(
      child: ListTile(
        onTap: onTap,
        title: Text(p.name, style: theme.textTheme.titleMedium),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.planLibraryByAuthor(author)),
              const SizedBox(height: 6),
              _PlanFacts(plan: p),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

/// Preview of one public-library plan + a clone-into-my-account action.
class PlanLibraryPreviewScreen extends StatefulWidget {
  final TrainingService training;
  final PublicPlanLibraryEntry entry;

  const PlanLibraryPreviewScreen({
    super.key,
    required this.training,
    required this.entry,
  });

  @override
  State<PlanLibraryPreviewScreen> createState() => _PlanLibraryPreviewScreenState();
}

class _PlanLibraryPreviewScreenState extends State<PlanLibraryPreviewScreen> {
  DateTime _startDate = _nextMonday();
  bool _cloning = false;

  List<PlanWeekRow> _weeks = const [];
  List<PlanWorkoutRow> _workouts = const [];
  bool _weeksLoading = true;
  bool _weeksError = false;

  @override
  void initState() {
    super.initState();
    _loadWeeks();
  }

  Future<void> _loadWeeks() async {
    setState(() {
      _weeksLoading = true;
      _weeksError = false;
    });
    try {
      final r = await widget.training
          .fetchPlan(widget.entry.plan.id)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _weeks = r.weeks;
        _workouts = r.workouts;
        _weeksLoading = false;
      });
    } catch (e) {
      debugPrint('plan library preview weeks failed: $e');
      if (!mounted) return;
      setState(() {
        _weeksLoading = false;
        _weeksError = true;
      });
    }
  }

  /// What a week asks of the runner: its running days and their planned
  /// distance. Rest rows are skipped — the generator writes one per day, so a
  /// raw row count reads 7 for every week. Mirrors web
  /// `plans/library/[id]`'s `weekSummary`.
  String _weekSummary(AppLocalizations l10n, String weekId) {
    final runs =
        _workouts.where((w) => w.weekId == weekId && w.kind != 'rest').toList();
    final metres =
        runs.fold<double>(0, (sum, w) => sum + (w.targetDistanceM ?? 0));
    final count = l10n.planLibraryPreviewWeekRuns(runs.length);
    return metres > 0 ? '$count · ${formatDistanceForPref(metres)}' : count;
  }

  static DateTime _nextMonday() {
    final d = DateTime.now();
    final offset = (8 - d.weekday) % 7;
    // Calendar days — a fixed 24-hour step across a DST fall-back lands at
    // 23:00 the previous day, starting the plan on a Sunday.
    return addDays(DateTime(d.year, d.month, d.day), offset == 0 ? 7 : offset);
  }

  Future<void> _clone() async {
    if (_cloning) return;
    if (!await ensureSignedIn(context,
        viewerId: widget.training.currentUserId)) {
      return;
    }
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final startIso = toIsoDate(_startDate);
    final endIso = clonedPlanEndIso(widget.entry.plan, startIso,
        start: planRowStartIso, end: planRowEndIso);
    final action = await confirmPlanOverlap(context, widget.training,
        startIso: startIso, endIso: endIso);
    if (action == null || !mounted) return;
    setState(() => _cloning = true);
    try {
      final newId = await widget.training
          .clonePublicPlan(
            templateId: widget.entry.plan.id,
            startDate: _startDate,
            onOverlap: action,
          )
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => PlanDetailScreen(training: widget.training, planId: newId),
        ),
      );
    } catch (e) {
      debugPrint('plan library clone failed: $e');
      if (mounted) {
        setState(() => _cloning = false);
        showTopBanner(
            context,
            planOverlapErrorText(context, e) ??
                l10n.planLibraryCloneFailed(friendlyError(l10n, e)));
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _startDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = widget.entry.plan;
    final author = widget.entry.authorHandle ?? l10n.planLibraryAnonymous;
    return Scaffold(
      appBar: AppBar(title: Text(p.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.planLibraryByAuthor(author), style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          _PlanFacts(plan: p, weeks: _weeks.isEmpty ? null : _weeks.length),
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.planLibraryStartDate),
            subtitle: Text(formatDateMed(
                _startDate, localeToTag(Localizations.localeOf(context)))),
            trailing: const Icon(Icons.calendar_today),
            onTap: _pickDate,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _cloning ? null : _clone,
            icon: _cloning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.copy_all),
            label: Text(_cloning ? l10n.planLibraryCloning : l10n.planLibraryClone),
          ),
          const SizedBox(height: 24),
          Semantics(
            header: true,
            child: Text(l10n.planLibraryPreviewWeeks,
                style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          if (_weeksLoading)
            ListSkeleton.section(
              label: l10n.commonLoading,
              rowHeight: 40,
              hasLeading: false,
            )
          else if (_weeksError)
            Row(
              children: [
                Expanded(child: Text(l10n.planLibraryLoadError)),
                TextButton(
                  onPressed: _loadWeeks,
                  child: Text(l10n.planLibraryRetry),
                ),
              ],
            )
          else
            for (final w in _weeks)
              ListTile(
                key: Key('planLibraryWeek-${w.weekIndex}'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(l10n.planLibraryPreviewWeek(w.weekIndex + 1)),
                trailing: Text(
                  _weekSummary(l10n, w.id),
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
        ],
      ),
    );
  }
}

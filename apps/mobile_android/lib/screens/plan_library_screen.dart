import 'dart:async';

import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart'
    show
        AppSpace,
        DetailHero,
        DetailMeta,
        DetailPage,
        EmptyState,
        ListCard,
        ListSkeleton,
        PageHeader,
        ProgressBar,
        PushedPage,
        SectionHeader,
        TermValueRow;

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
import '../widgets/stale_refresh_banner.dart';
import '../widgets/official_badge.dart';
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
      // Results already on screen stay there; a failed search or refresh is
      // a banner over them rather than an error page that drops them.
      if (_loaded) {
        setState(() => _loading = false);
        showStaleRefreshBanner(context, e);
        return;
      }
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
    return PushedPage(
      title: l10n.planLibraryTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(title: l10n.planLibraryTitle),
          if (showControls) ...[
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
              height: ProgressBar.height,
              child: _loading && _loaded
                  ? const ProgressBar(value: null)
                  : null,
            ),
          ],
          Expanded(
            child: _loading && !_loaded
                ? ListSkeleton(label: l10n.commonLoading, hasLeading: false)
                : _signedOut
                    ? SignInRequiredState(onSignedIn: _load)
                    : _error
                    ? AppErrorState(message: l10n.planLibraryLoadError, onRetry: _load)
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
                              // The subheading scrolls with the cards: pinned
                              // above the search, it left the list no room at
                              // 320 dp and 2x (issue #1374).
                              itemCount: _plans.length + 1,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, i) => i == 0
                                  ? Text(
                                      l10n.planLibrarySubheading,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant),
                                    )
                                  : _LibraryCard(
                                      entry: _plans[i - 1],
                                      onTap: () => Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => PlanLibraryPreviewScreen(
                                            training: widget.training,
                                            entry: _plans[i - 1],
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
    return ListCard.row(
      margin: EdgeInsets.zero,
      onTap: onTap,
      title: p.name,
      chevron: true,
      meta: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry.isOfficial) const OfficialBadge(),
          Text(l10n.planLibraryByAuthor(author),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: AppSpace.xs),
          _PlanFacts(plan: p),
        ],
      ),
    );
  }
}

/// Preview of one public-library plan + a clone-into-my-account action.
class PlanLibraryPreviewScreen extends StatefulWidget {
  final TrainingService training;
  final PublicPlanLibraryEntry entry;

  /// The `ref` the creator's link carried; a copy started here is attributed
  /// to it (decisions § 2268).
  final String? shareRef;

  const PlanLibraryPreviewScreen({
    super.key,
    required this.training,
    required this.entry,
    this.shareRef,
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
      await widget.training.attributePlanStart(newId, widget.shareRef);
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
    return DetailPage(
      title: p.name,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DetailHero(
            title: p.name,
            padding: const EdgeInsets.only(bottom: 12),
            badges: [
              if (widget.entry.isOfficial) const OfficialBadge(size: 16),
            ],
            meta: [
              DetailMeta(
                icon: Icons.person_outline,
                text: l10n.planLibraryByAuthor(author),
              ),
            ],
          ),
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
          SectionHeader.title(label: l10n.planLibraryPreviewWeeks),
          const SizedBox(height: 8),
          if (_weeksLoading)
            ListSkeleton.section(
              label: l10n.commonLoading,
              rowHeight: 40,
              hasLeading: false,
            )
          else if (_weeksError)
            AppErrorState.inline(
              message: l10n.planLibraryLoadError,
              onRetry: _loadWeeks,
            )
          else
            // A week and its summary share a line while they fit; at large
            // text the summary drops under the week. A ListTile's trailing
            // summary took the whole row at 2x on 320 dp and threw.
            for (final w in _weeks)
              Padding(
                key: Key('planLibraryWeek-${w.weekIndex}'),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: TermValueRow(
                  term: l10n.planLibraryPreviewWeek(w.weekIndex + 1),
                  value: _weekSummary(l10n, w.id),
                  termStyle: theme.textTheme.bodyMedium,
                  valueStyle: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
        ],
      ),
    );
  }
}

/// A public-library plan opened by id: a creator's `/share/plan/<id>` "Train
/// with me" link, or the plan a copy started from (decisions § 2262). Loads
/// the library entry, then shows [PlanLibraryPreviewScreen] for it.
class PlanLibraryLinkScreen extends StatefulWidget {
  final TrainingService training;
  final String planId;

  /// The `ref` the creator's link carried (decisions § 2268).
  final String? shareRef;

  const PlanLibraryLinkScreen({
    super.key,
    required this.training,
    required this.planId,
    this.shareRef,
  });

  @override
  State<PlanLibraryLinkScreen> createState() => _PlanLibraryLinkScreenState();
}

class _PlanLibraryLinkScreenState extends State<PlanLibraryLinkScreen> {
  PublicPlanLibraryEntry? _entry;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final entry = await widget.training
          .fetchPublicPlanLibraryEntry(widget.planId)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _entry = entry;
        _loading = false;
      });
    } catch (e) {
      debugPrint('plan library link load failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    if (entry != null) {
      return PlanLibraryPreviewScreen(
          training: widget.training, entry: entry, shareRef: widget.shareRef);
    }
    final l10n = AppLocalizations.of(context);
    return DetailPage.placeholder(
      child: _loading
          ? ListSkeleton.section(
              label: l10n.commonLoading,
              rowHeight: 40,
              hasLeading: false,
            )
          : _error
              ? AppErrorState(message: l10n.planLibraryLoadError, onRetry: _load)
              : Center(
                  key: const Key('planLibraryLinkNotFound'),
                  child: EmptyState(
                    icon: Icons.public_off,
                    title: l10n.planLibraryNotFound,
                  ),
                ),
    );
  }
}

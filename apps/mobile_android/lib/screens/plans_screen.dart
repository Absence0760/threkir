import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart'
    show
        AppInsets,
        AsyncView,
        ChoiceChipOption,
        EmptyState,
        FilterBar,
        HubTabBody,
        ListCard,
        LoadingState,
        PrimaryAction,
        buildChoiceChip;

import '../auth_error.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../l10n/number_format.dart';
import '../local_run_store.dart';
import '../plan_labels.dart';
import '../starter_plans.dart';
import '../plan_calibration.dart' show PlanCalibration;
import '../training_service.dart';
import '../backend_timeout.dart';
import '../fab_clearance.dart';
import '../widgets/confirm_destructive.dart';
import '../widgets/error_state.dart';
import '../widgets/stale_refresh_banner.dart';
import '../widgets/plan_list_card.dart';
import '../widgets/plan_overlap_dialog.dart';
import '../widgets/sign_in_required_state.dart';
import '../widgets/top_banner.dart';
import 'plan_detail_screen.dart';
import 'plan_library_screen.dart';
import 'plan_new_screen.dart';

/// The status filter above the list. `null` is "All".
typedef _StatusFilter = String?;

/// The order a runner reads their plans in: the one they are on, then the one
/// they stepped away from, then the finished ones. Newest start first within
/// each. Mirrors web `plans/+page.svelte`'s `filteredPlans`.
const _statusRank = {'active': 0, 'paused': 1, 'completed': 2, 'abandoned': 3};

List<TrainingPlanRow> sortPlansForList(List<TrainingPlanRow> plans) {
  final out = [...plans];
  out.sort((a, b) {
    final r = (_statusRank[a.status] ?? 4) - (_statusRank[b.status] ?? 4);
    if (r != 0) return r;
    return b.startDate.compareTo(a.startDate);
  });
  return out;
}

class PlansScreen extends StatefulWidget {
  final TrainingService training;
  final ApiClient? apiClient;

  /// Threaded down to `PlanDetailScreen` for the P2 adaptive-replan fitness
  /// gate (gated OFF by default). Null when no run store is in scope.
  final LocalRunStore? runStore;

  const PlansScreen(
      {super.key, required this.training, this.apiClient, this.runStore});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  List<TrainingPlanRow> _plans = const [];
  bool _loading = true;
  _PlansLoadError? _error;
  _StatusFilter _filter;
  String? _creatingStarterId;

  @override
  void initState() {
    super.initState();
    widget.training.addListener(_onChange);
    _load();
  }

  @override
  void dispose() {
    widget.training.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) _load();
  }

  /// Runs a plan mutation (abandon / delete), surfacing a failure as a
  /// banner instead of letting it vanish silently — the plan still
  /// exists, so a swallowed error would leave the list looking unchanged
  /// with no explanation. On success the list reloads.
  /// The plan whose Abandon / Delete is being written. One at a time, and
  /// every card's action waits for it, so a second tap cannot start a second
  /// write while the first is still out.
  String? _actingPlanId;

  Future<void> _runPlanAction(
      String planId, Future<void> Function() action) async {
    if (_actingPlanId != null) return;
    setState(() => _actingPlanId = planId);
    try {
      await action().timeout(kBackendLoadTimeout);
    } catch (e) {
      debugPrint('plans action failed: $e');
      if (mounted) {
        setState(() => _actingPlanId = null);
        showTopBanner(context, AppLocalizations.of(context).plansActionFailed(friendlyError(AppLocalizations.of(context), e)));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _actingPlanId = null);
    await _load();
  }

  Future<void> _load() async {
    // A list already on screen stays there while it refreshes; a failed
    // refresh is a banner over it, as on plan detail, not an error page that
    // takes the plans away. The list reloads on every TrainingService change.
    final refreshing = _plans.isNotEmpty;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p =
          await widget.training.fetchMyPlans().timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _plans = p;
        _loading = false;
      });
    } catch (e, s) {
      debugPrint('PlansScreen._load failed: $e\n$s');
      if (!mounted) return;
      if (refreshing) {
        setState(() => _loading = false);
        showStaleRefreshBanner(context, e);
        return;
      }
      setState(() {
        _loading = false;
        _error = e is TimeoutException
            ? _PlansLoadError.timeout
            : _PlansLoadError.generic;
      });
    }
  }

  /// The list is empty, so there is no plan of the runner's own for the new
  /// one to overlap: the server is asked to refuse one anyway, and a refusal
  /// (a plan created on another device since) lands as the create-failed
  /// banner rather than replacing anything.
  Future<void> _createStarter(StarterPlan starter) async {
    if (_creatingStarterId != null) return;
    final l10n = AppLocalizations.of(context);
    final start = starterStartDate(starter.id, DateTime.now());
    setState(() => _creatingStarterId = starter.id);
    try {
      var calibration = PlanCalibration.unknown;
      try {
        calibration = await widget.training
            .fetchPlanCalibration()
            .timeout(kBackendLoadTimeout);
      } catch (e) {
        debugPrint('starter calibration lookup failed: $e');
      }
      final generated = instantiateStarter(
        starter.id,
        start,
        age: calibration.age,
        extraRecovery: calibration.extraRecovery,
      );
      if (generated == null) return;
      final plan = await widget.training
          .createPlan(
            name: starterPlanName(l10n, starter.id),
            goalEvent: starter.goalEvent,
            goalDistanceM: generated.goalDistanceM,
            startDate: start,
            daysPerWeek: starter.daysPerWeek,
            generated: generated,
          )
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      await _openPlan(plan.id);
    } catch (e) {
      debugPrint('Starter plan create failed: $e');
      if (mounted) {
        showTopBanner(context,
            planOverlapErrorText(context, e) ?? l10n.planNewStarterCreateFailed);
      }
    } finally {
      if (mounted) setState(() => _creatingStarterId = null);
    }
  }

  Future<void> _openPlan(String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlanDetailScreen(
          training: widget.training,
          planId: id,
          runStore: widget.runStore,
        ),
      ),
    );
    if (mounted) await _load();
  }

  /// Same confirm as plan detail's Abandon: it cannot be undone from the UI.
  Future<void> _abandon(TrainingPlanRow p) async {
    if (_actingPlanId != null) return;
    final l10n = AppLocalizations.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.plansAbandonTitle(p.name),
      body: l10n.plansAbandonBody,
      confirmLabel: l10n.plansAbandon,
      cancelLabel: l10n.plansCancel,
    );
    if (ok && mounted) {
      await _runPlanAction(
          p.id, () => widget.training.updateStatus(p.id, 'abandoned'));
    }
  }

  Future<void> _delete(TrainingPlanRow p) async {
    if (_actingPlanId != null) return;
    final l10n = AppLocalizations.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.plansDeleteTitle(p.name),
      body: l10n.plansDeleteBody,
      confirmLabel: l10n.plansDelete,
      cancelLabel: l10n.plansCancel,
    );
    if (ok && mounted) {
      await _runPlanAction(p.id, () => widget.training.deletePlan(p.id));
    }
  }

  void _openLibrary() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlanLibraryScreen(training: widget.training),
        ),
      );

  Future<void> _openNewPlan() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlanNewScreen(training: widget.training),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final signedIn = widget.apiClient?.userId != null;
    if (!signedIn) {
      return HubTabBody(
        title: l10n.runSurfaceTabPlans,
        body: SignInRequiredState(
          api: widget.apiClient,
          onSignedIn: () => setState(() {}),
        ),
      );
    }
    return HubTabBody(
      title: l10n.runSurfaceTabPlans,
      // "Browse library" is a second way to get a plan, as on web, so it is a
      // secondary action rather than a tab or a second primary button, and a
      // labelled one: as a bare glyph nobody found it (issue #1186).
      actions: [
        // Flexible, so at 2x text on a narrow phone the label ellipsizes
        // rather than pushing the row off the screen.
        Flexible(
          child: OutlinedButton.icon(
            onPressed: _openLibrary,
            icon: const Icon(Icons.public),
            label: Text(
              l10n.plansBrowseLibrary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      primary: PrimaryAction(
        label: l10n.plansNewPlan,
        icon: Icons.add,
        onPressed: _openNewPlan,
      ),
      filters: _plans.isEmpty ? null : _filterBar(l10n),
      onRefresh: _load,
      body: AsyncView<List<TrainingPlanRow>>(
        loading: _loading,
        error: _error,
        data: _plans,
        isEmpty: (p) => p.isEmpty,
        loadingState: LoadingState.list(label: l10n.commonLoading, hasLeading: false),
        errorBuilder: (_, _) =>
            AppErrorState(message: _errorText(l10n), onRetry: _load),
        empty: EmptyState(
          icon: Icons.calendar_month,
          title: l10n.plansEmptyTitle,
          body: l10n.plansEmptyBody,
          ctaLabel: l10n.plansNewPlan,
          onCta: _openNewPlan,
          footer: _Starters(
            today: DateTime.now(),
            creatingId: _creatingStarterId,
            onPick: _createStarter,
          ),
        ),
        builder: (_, plans) => _list(l10n, plans),
      ),
    );
  }

  String _errorText(AppLocalizations l10n) => _error == _PlansLoadError.timeout
      ? l10n.plansTimeoutError
      : l10n.plansLoadError;

  /// The status chips on one line, each with its count, as on web.
  FilterBar _filterBar(AppLocalizations l10n) {
    final tag = localeToTag(Localizations.localeOf(context));
    int count(String? s) =>
        s == null ? _plans.length : _plans.where((p) => p.status == s).length;
    String label(String text, String? s) {
      final n = count(s);
      return n == 0 ? text : '$text · ${formatFixed(n.toDouble(), 0, tag)}';
    }

    final options = [
      ChoiceChipOption<String?>(
          value: null, label: label(l10n.plansFilterAll, null)),
      ChoiceChipOption<String?>(
          value: 'active',
          label: label(l10n.plansFilterActive, 'active'),
          icon: Icons.play_circle_outline),
      ChoiceChipOption<String?>(
          value: 'paused',
          label: label(l10n.plansFilterPaused, 'paused'),
          icon: Icons.pause_circle_outline),
      ChoiceChipOption<String?>(
          value: 'completed',
          label: label(l10n.plansFilterCompleted, 'completed'),
          icon: Icons.check_circle_outline),
      ChoiceChipOption<String?>(
          value: 'abandoned',
          label: label(l10n.plansFilterAbandoned, 'abandoned'),
          icon: Icons.cancel_outlined),
    ];
    return FilterBar(
      chipsLabel: l10n.plansFilterGroupLabel,
      chips: [
        for (final o in options)
          buildChoiceChip<String?>(
              context, o, _filter, (f) => setState(() => _filter = f)),
      ],
    );
  }

  Widget _list(AppLocalizations l10n, List<TrainingPlanRow> plans) {
    final f = _filter;
    final shown = sortPlansForList(
        f == null ? plans : plans.where((p) => p.status == f).toList());
    if (shown.isEmpty) {
      return EmptyState(
        icon: Icons.filter_alt_off,
        title: l10n.plansNoFilteredPlans(planStatusLabel(l10n, f!)),
        ctaLabel: l10n.plansShowAllPlans,
        ctaIcon: Icons.apps,
        onCta: () => setState(() => _filter = null),
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(AppInsets.gutter, AppInsets.pageTop,
          AppInsets.gutter, fabScrollClearance(context)),
      itemCount: shown.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppInsets.itemGap),
      itemBuilder: (ctx, i) {
        final p = shown[i];
        final abandonable = p.status == 'active' || p.status == 'paused';
        return PlanListCard(
          plan: p,
          now: DateTime.now(),
          onTap: () => _openPlan(p.id),
          onAbandon: abandonable ? () => _abandon(p) : null,
          onDelete: abandonable ? null : () => _delete(p),
          actionBusy: _actingPlanId == p.id,
          actionsLocked: _actingPlanId != null,
        );
      },
    );
  }
}

class _Starters extends StatelessWidget {
  final DateTime today;
  final String? creatingId;
  final ValueChanged<StarterPlan> onPick;

  const _Starters({
    required this.today,
    required this.creatingId,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(l10n.planNewStarterTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall),
          ),
          const SizedBox(height: 12),
          for (final s in starterPlans)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _StarterTile(
                name: starterPlanName(l10n, s.id),
                summary: [
                  ?starterSummaryText(l10n, s.id),
                  l10n.plansStarterStarts(
                      formatDateShort(starterStartDate(s.id, today), tag)),
                ].join(' · '),
                id: s.id,
                creating: creatingId == s.id,
                onTap: creatingId == null ? () => onPick(s) : null,
              ),
            ),
        ],
      ),
    );
  }
}


/// One built-in starter as a single tappable card. A screen reader hears the
/// plan's name as the button and its summary as the hint, not the visual
/// "Start this plan" prompt, which would read the same on all three.
class _StarterTile extends StatelessWidget {
  final String id;
  final String name;
  final String summary;
  final bool creating;
  final VoidCallback? onTap;

  const _StarterTile({
    required this.id,
    required this.name,
    required this.summary,
    required this.creating,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final enabled = onTap != null;
    final accent = enabled || creating
        ? theme.colorScheme.primary
        : theme.disabledColor;
    return ListCard(
      key: Key('planStarter-$id'),
      margin: EdgeInsets.zero,
      onTap: onTap,
      enabled: enabled,
      semanticLabel: name,
      semanticHint: summary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            summary,
            key: Key('planStarterSummary-$id'),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Flexible(
                child: Text(
                  creating
                      ? l10n.planNewStarterCreating
                      : l10n.plansStarterStart,
                  style: theme.textTheme.labelLarge?.copyWith(color: accent),
                ),
              ),
              const SizedBox(width: 6),
              if (creating)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(Icons.arrow_forward, size: 18, color: accent),
            ],
          ),
        ],
      ),
    );
  }
}

enum _PlansLoadError { timeout, generic }

import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart'
    show
        AppSemanticColors,
        ChoiceChipOption,
        ChoiceChipRow,
        EmptyState,
        ListSkeleton,
        ProgressBar,
        StatusPill,
        StatusPillSize;

import '../auth_error.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../l10n/number_format.dart';
import '../local_run_store.dart';
import '../metrics.dart';
import '../plan_labels.dart';
import '../plan_start.dart';
import '../plan_week.dart';
import '../starter_plans.dart';
import '../training.dart';
import '../training_service.dart';
import '../backend_timeout.dart';
import '../widgets/confirm_destructive.dart';
import '../widgets/error_state.dart';
import '../widgets/next_race_card.dart';
import '../widgets/plan_meta_item.dart';
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

/// Where a starter picked from the empty plans list begins: the Sunday at
/// least a week out, the wizard's own default. Plan day 0 is the Sunday long
/// run, so a plan must start on a Sunday (decisions § 735).
DateTime planStarterStartDate(DateTime now) =>
    nextSunday(DateTime(now.year, now.month, now.day + 7));

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
  Future<void> _runPlanAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('plans action failed: $e');
      if (mounted) {
        showTopBanner(context, AppLocalizations.of(context).plansActionFailed(friendlyError(AppLocalizations.of(context), e)));
      }
      return;
    }
    await _load();
  }

  Future<void> _load() async {
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
    } on TimeoutException catch (e) {
      debugPrint('PlansScreen._load timed out: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _PlansLoadError.timeout;
        });
      }
    } catch (e, s) {
      debugPrint('PlansScreen._load failed: $e\n$s');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _PlansLoadError.generic;
        });
      }
    }
  }

  /// The list is empty, so there is no plan of the runner's own for the new
  /// one to overlap: the server is asked to refuse one anyway, and a refusal
  /// (a plan created on another device since) lands as the create-failed
  /// banner rather than replacing anything.
  Future<void> _createStarter(StarterPlan starter) async {
    if (_creatingStarterId != null) return;
    final l10n = AppLocalizations.of(context);
    final start = planStarterStartDate(DateTime.now());
    setState(() => _creatingStarterId = starter.id);
    try {
      int? age;
      try {
        age = await widget.training.fetchViewerAge().timeout(kBackendLoadTimeout);
      } catch (e) {
        debugPrint('starter age lookup failed: $e');
      }
      final generated = instantiateStarter(starter.id, start, age: age);
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

  Future<void> _abandon(TrainingPlanRow p) async {
    final l10n = AppLocalizations.of(context);
    final ok = await _confirm(
      context,
      l10n.plansAbandonTitle(p.name),
      l10n.plansAbandonBody,
      confirmLabel: l10n.plansAbandon,
    );
    if (ok) {
      await _runPlanAction(
          () => widget.training.updateStatus(p.id, 'abandoned'));
    }
  }

  Future<void> _delete(TrainingPlanRow p) async {
    final l10n = AppLocalizations.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.plansDeleteTitle(p.name),
      body: l10n.plansDeleteBody,
      confirmLabel: l10n.plansDelete,
      cancelLabel: l10n.plansCancel,
    );
    if (ok) {
      await _runPlanAction(() => widget.training.deletePlan(p.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final signedIn = widget.apiClient?.userId != null;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.plansTitle)),
      body: !signedIn
          ? SignInRequiredState(
              api: widget.apiClient,
              onSignedIn: () => setState(() {}),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Toolbar(
                  onBrowseLibrary: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          PlanLibraryScreen(training: widget.training),
                    ),
                  ),
                  onNewPlan: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            PlanNewScreen(training: widget.training),
                      ),
                    );
                  },
                ),
                if (!_loading && _error == null && _plans.isNotEmpty)
                  _FilterRow(
                    plans: _plans,
                    selected: _filter,
                    onChanged: (f) => setState(() => _filter = f),
                  ),
                Expanded(child: _body(l10n)),
              ],
            ),
    );
  }

  Widget _body(AppLocalizations l10n) {
    if (_loading && _plans.isEmpty) {
      return ListSkeleton(label: l10n.commonLoading, hasLeading: false);
    }
    if (_error != null) {
      return ErrorState(
          message: _error == _PlansLoadError.timeout
              ? l10n.plansTimeoutError
              : l10n.plansLoadError,
          onRetry: _load);
    }
    if (_plans.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: EmptyState(
          icon: Icons.calendar_month,
          title: l10n.plansEmptyTitle,
          body: l10n.plansEmptyBody,
          footer: _Starters(
            start: planStarterStartDate(DateTime.now()),
            creatingId: _creatingStarterId,
            onPick: _createStarter,
          ),
        ),
      );
    }
    final f = _filter;
    final shown = sortPlansForList(
        f == null ? _plans : _plans.where((p) => p.status == f).toList());
    return RefreshIndicator(
      onRefresh: _load,
      child: shown.isEmpty
          ? EmptyState(
              icon: Icons.filter_alt_off,
              title: l10n.plansNoFilteredPlans(planStatusLabel(l10n, f!)),
              ctaLabel: l10n.plansShowAllPlans,
              ctaIcon: Icons.apps,
              onCta: () => setState(() => _filter = null),
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: shown.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final p = shown[i];
                final abandonable =
                    p.status == 'active' || p.status == 'paused';
                return PlanListCard(
                  plan: p,
                  now: DateTime.now(),
                  onTap: () => _openPlan(p.id),
                  onAbandon: abandonable ? () => _abandon(p) : null,
                  onDelete: abandonable ? null : () => _delete(p),
                );
              },
            ),
    );
  }
}

/// "Browse library" beside "New plan", as on web: the library is a second way
/// to get a plan, not a sibling surface, so it is an action rather than a tab.
class _Toolbar extends StatelessWidget {
  final VoidCallback onBrowseLibrary;
  final VoidCallback onNewPlan;

  const _Toolbar({required this.onBrowseLibrary, required this.onNewPlan});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: onBrowseLibrary,
            icon: const Icon(Icons.public),
            label: Text(l10n.plansBrowseLibrary),
          ),
          FilledButton.icon(
            onPressed: onNewPlan,
            icon: const Icon(Icons.add),
            label: Text(l10n.plansNewPlan),
          ),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final List<TrainingPlanRow> plans;
  final _StatusFilter selected;
  final ValueChanged<_StatusFilter> onChanged;

  const _FilterRow({
    required this.plans,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    int count(String? s) =>
        s == null ? plans.length : plans.where((p) => p.status == s).length;
    String label(String text, String? s) {
      final n = count(s);
      return n == 0 ? text : '$text · ${formatFixed(n.toDouble(), 0, tag)}';
    }

    return Semantics(
      container: true,
      label: l10n.plansFilterGroupLabel,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: ChoiceChipRow<String?>(
          selected: selected,
          onChanged: onChanged,
          options: [
            ChoiceChipOption(
                value: null, label: label(l10n.plansFilterAll, null)),
            ChoiceChipOption(
                value: 'active',
                label: label(l10n.plansFilterActive, 'active'),
                icon: Icons.play_circle_outline),
            ChoiceChipOption(
                value: 'paused',
                label: label(l10n.plansFilterPaused, 'paused'),
                icon: Icons.pause_circle_outline),
            ChoiceChipOption(
                value: 'completed',
                label: label(l10n.plansFilterCompleted, 'completed'),
                icon: Icons.check_circle_outline),
            ChoiceChipOption(
                value: 'abandoned',
                label: label(l10n.plansFilterAbandoned, 'abandoned'),
                icon: Icons.cancel_outlined),
          ],
        ),
      ),
    );
  }
}

class _Starters extends StatelessWidget {
  final DateTime start;
  final String? creatingId;
  final ValueChanged<StarterPlan> onPick;

  const _Starters({
    required this.start,
    required this.creatingId,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(l10n.planNewStarterTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.plansStarterStartsOn(formatDateShort(start, tag)),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        for (final s in starterPlans)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton.icon(
              key: Key('planStarter-${s.id}'),
              onPressed: creatingId == null ? () => onPick(s) : null,
              icon: creatingId == s.id
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.event_note),
              label: Text(starterPlanName(l10n, s.id)),
            ),
          ),
      ],
    );
  }
}

Future<bool> _confirm(BuildContext context, String title, String body,
    {required String confirmLabel}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx);
      return AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.plansCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return res == true;
}

/// One plan on the list: name and status, the goal / target / VDOT it was
/// built for, its dates and length, and — while it is active — where today
/// sits in it. Mirrors web `plans/+page.svelte`'s card. Exactly one action:
/// Abandon while the plan is still live (active or paused), Delete once it is
/// over.
class PlanListCard extends StatelessWidget {
  final TrainingPlanRow plan;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback? onAbandon;
  final VoidCallback? onDelete;

  const PlanListCard({
    super.key,
    required this.plan,
    required this.now,
    required this.onTap,
    this.onAbandon,
    this.onDelete,
  }) : assert((onAbandon == null) != (onDelete == null),
            'a plan card carries exactly one action');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    final semantic = AppSemanticColors.ofTheme(theme);
    final todayIso = toIsoDate(now);
    final startIso = toIsoDate(plan.startDate);
    final endIso = toIsoDate(plan.endDate);
    final active = plan.status == 'active';
    // An active plan that hasn't started is queued behind the current one.
    final upcoming = active && startIso.compareTo(todayIso) > 0;
    final weeks = planWeekCount(plan.startDate, plan.endDate);

    final statusLabel =
        upcoming ? l10n.plansStatusUpcoming : planStatusLabel(l10n, plan.status);
    final pill = _pill(theme, semantic, statusLabel, upcoming);
    final goal = planGoalLabel(l10n, plan.goalEvent, plan.goalDistanceM);
    final target = plan.goalTimeSeconds != null && plan.goalTimeSeconds! > 0
        ? fmtHms(plan.goalTimeSeconds)
        : l10n.plansGoalFinish;
    final vdot = plan.vdot == null
        ? null
        : formatFixed(plan.vdot!.toDouble(), 1, activeLocaleTag);
    final dates =
        '${formatDateShort(plan.startDate, tag)} → ${formatDateShort(plan.endDate, tag)}';
    final length = planLengthLabel(l10n, weeks, plan.daysPerWeek);

    String? weekLine;
    String? when;
    double? progress;
    if (active) {
      final week = currentPlanWeekIndex(startIso, todayIso, weeks) + 1;
      weekLine = l10n.plansWeekOf(week, weeks);
      final countdown = planRaceCountdown(startIso, endIso, todayIso);
      when = countdown.kind == PlanRaceCountdownKind.racePast
          ? l10n.plansEnded
          : NextRaceCard.relation(l10n, countdown);
      progress = _calendarProgress(startIso, endIso, todayIso);
    }

    final label = [
      plan.name,
      statusLabel,
      '${l10n.plansHeroGoal}: $goal',
      '${l10n.plansHeroTarget}: $target',
      if (vdot != null)
        '${metricText(l10n, Metric.vdot)}: $vdot',
      dates,
      length,
      ?weekLine,
      if (when != null && when.isNotEmpty) when,
    ].join(', ');

    final info = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  plan.name,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(child: pill),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              _Hero(label: l10n.plansHeroGoal, value: goal, accent: true),
              _Hero(label: l10n.plansHeroTarget, value: target),
              if (vdot != null)
                _Hero(
                    label: metricText(l10n, Metric.vdot),
                    value: vdot),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              PlanMetaItem(icon: Icons.date_range, text: dates),
              PlanMetaItem(icon: Icons.view_week_outlined, text: length),
            ],
          ),
          if (weekLine != null && progress != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(weekLine,
                      style: theme.textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                if (when != null && when.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      when,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            ProgressBar(value: progress),
          ],
        ],
      ),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onTap,
            child: MergeSemantics(
              child: Semantics(
                button: true,
                label: label,
                child: ExcludeSemantics(child: info),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: onAbandon != null
                  ? TextButton(
                      onPressed: onAbandon,
                      child: Text(l10n.plansAbandon),
                    )
                  : TextButton(
                      onPressed: onDelete,
                      style: TextButton.styleFrom(
                          foregroundColor: semantic.danger),
                      child: Text(l10n.plansDelete),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(ThemeData theme, AppSemanticColors semantic, String label,
      bool upcoming) {
    final scheme = theme.colorScheme;
    final (IconData icon, Color fg, Color bg) = upcoming
        ? (Icons.schedule, scheme.onSecondaryContainer, scheme.secondaryContainer)
        : switch (plan.status) {
            'active' => (
                Icons.play_circle,
                scheme.onPrimaryContainer,
                scheme.primaryContainer
              ),
            'paused' => (
                Icons.pause_circle,
                scheme.onTertiaryContainer,
                scheme.tertiaryContainer
              ),
            'completed' => (
                Icons.check_circle,
                semantic.onSuccess,
                semantic.success
              ),
            _ => (
                Icons.cancel,
                scheme.onSurfaceVariant,
                scheme.surfaceContainerHigh
              ),
          };
    return StatusPill(
      key: upcoming ? const Key('planTileUpcoming') : null,
      label: label,
      icon: icon,
      foreground: fg,
      fill: bg,
      size: StatusPillSize.compact,
    );
  }

}

/// Calendar position (0..1) between a plan's start and end, counted in whole
/// days. Calendar-based, not workout-based, like web's `calendarPct`: cheap to
/// compute without a per-plan workouts fetch, and it answers "where am I in
/// the plan", which is all the list card asks.
double _calendarProgress(String startIso, String endIso, String todayIso) {
  int day(String iso) {
    final p = iso.split('-').map(int.parse).toList();
    return DateTime.utc(p[0], p[1], p[2]).millisecondsSinceEpoch ~/ 86400000;
  }

  final start = day(startIso), end = day(endIso), today = day(todayIso);
  if (today <= start) return 0;
  if (today >= end) return 1;
  return (today - start) / (end - start);
}

class _Hero extends StatelessWidget {
  final String label;
  final String value;
  final bool accent;

  const _Hero({required this.label, required this.value, this.accent = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: accent ? theme.colorScheme.primary : null,
          ),
        ),
      ],
    );
  }
}

enum _PlansLoadError { timeout, generic }

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;

import '../auth_error.dart' show friendlyError;
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../plan_change.dart';
import '../training.dart' show fmtKm, toIsoDate, workoutKindFromDb;
import '../training_labels.dart';
import 'confirm_destructive.dart';
import 'top_banner.dart';

/// Suggested changes to coach-assigned plans (issue #1215 Phase 2, decisions
/// § 2382) between the signed-in user and [partnerId] (the DM thread) or on
/// [planId] (the plan screen): pending first, then the three most recent
/// decided. Renders nothing when there are none. Web twin:
/// `PlanChangeRequests.svelte` + `PlanChangeRequestCard.svelte`.
class PlanChangeRequestsSection extends StatefulWidget {
  const PlanChangeRequestsSection({
    super.key,
    required this.api,
    this.planId,
    this.partnerId,
    this.onChanged,
    this.now = DateTime.now,
  }) : assert(planId != null || partnerId != null);

  final ApiClient api;
  final String? planId;
  final String? partnerId;
  final VoidCallback? onChanged;
  final DateTime Function() now;

  @override
  State<PlanChangeRequestsSection> createState() =>
      _PlanChangeRequestsSectionState();
}

const int _decidedShown = 3;

class _PlanChangeRequestsSectionState extends State<PlanChangeRequestsSection> {
  List<({PlanChangeRequestRow request, PlanChangeLines lines})> _items =
      const [];
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PlanChangeRequestsSection old) {
    super.didUpdateWidget(old);
    if (old.planId != widget.planId || old.partnerId != widget.partnerId) {
      _items = const [];
      _load();
    }
  }

  Future<void> _load() async {
    final planId = widget.planId;
    final partnerId = widget.partnerId;
    try {
      final all = await widget.api
          .fetchPlanChangeRequests(planId: planId, partnerId: partnerId);
      final shown = [
        ...all.where((r) => r.status == 'pending'),
        ...all.where((r) => r.status != 'pending').take(_decidedShown),
      ];
      final workoutIds = <String>{};
      final weekIds = <String>{};
      for (final r in shown) {
        final ids = planChangeIds(r.workouts, r.weeks);
        workoutIds.addAll(ids.workoutIds);
        weekIds.addAll(ids.weekIds);
      }
      final targets = shown.isEmpty
          ? (workouts: const <Map<String, dynamic>>[], weeks: const <Map<String, dynamic>>[])
          : await widget.api
              .fetchPlanChangeTargets(workoutIds.toList(), weekIds.toList());
      if (!mounted ||
          planId != widget.planId ||
          partnerId != widget.partnerId) {
        return;
      }
      final workoutRows = [
        for (final w in targets.workouts)
          PlanChangeWorkoutRow(
            id: w['id'] as String,
            scheduledDate: w['scheduled_date'] as String,
            kind: w['kind'] as String,
            targetDistanceM: w['target_distance_m'] as num?,
            targetDurationSeconds: w['target_duration_seconds'] as num?,
            skipped: w['skipped_at'] != null,
          ),
      ];
      final weekRows = [
        for (final k in targets.weeks)
          PlanChangeWeekRow(
            id: k['id'] as String,
            weekIndex: (k['week_index'] as num).toInt(),
            targetVolumeM: k['target_volume_m'] as num?,
          ),
      ];
      setState(() {
        _failed = false;
        _items = [
          for (final r in shown)
            (
              request: r,
              lines: planChangeLines(r.workouts, r.weeks, workoutRows, weekRows),
            ),
        ];
      });
    } catch (e) {
      debugPrint('plan change requests load failed: $e');
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _changed() async {
    await _load();
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final viewer = widget.api.userId;
    if (_failed) {
      return Padding(
        key: const Key('plan-change-load-failed'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.planChangeLoadFailed,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            TextButton(onPressed: _load, child: Text(l10n.planChangeRetry)),
          ],
        ),
      );
    }
    if (_items.isEmpty || viewer == null) return const SizedBox.shrink();
    return Column(
      key: const Key('plan-change-requests'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in _items)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: PlanChangeRequestCard(
              key: ValueKey(item.request.id),
              api: widget.api,
              request: item.request,
              lines: item.lines,
              viewerId: viewer,
              now: widget.now,
              onChanged: _changed,
            ),
          ),
      ],
    );
  }
}

class PlanChangeRequestCard extends StatefulWidget {
  const PlanChangeRequestCard({
    super.key,
    required this.api,
    required this.request,
    required this.lines,
    required this.viewerId,
    required this.onChanged,
    this.now = DateTime.now,
  });

  final ApiClient api;
  final PlanChangeRequestRow request;
  final PlanChangeLines lines;
  final String viewerId;
  final Future<void> Function() onChanged;
  final DateTime Function() now;

  @override
  State<PlanChangeRequestCard> createState() => _PlanChangeRequestCardState();
}

class _PlanChangeRequestCardState extends State<PlanChangeRequestCard> {
  final Set<String> _excluded = {};
  final _note = TextEditingController();
  bool _busy = false;

  bool get _isCoach => widget.viewerId == widget.request.coachId;
  bool get _pending => parsePlanChangeStatus(widget.request.status) == 'pending';
  int get _total => widget.lines.workouts.length + widget.lines.weeks.length;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String _status(AppLocalizations l10n) {
    switch (parsePlanChangeStatus(widget.request.status)) {
      case 'pending':
        return _isCoach ? l10n.planChangeWaitingForYou : l10n.planChangeWaitingForCoach;
      case 'approved':
        return widget.request.editedByCoach
            ? l10n.planChangeApprovedInPartByCoach
            : l10n.planChangeApprovedByCoach;
      case 'declined':
        return l10n.planChangeDeclinedByCoach;
      case 'withdrawn':
        return l10n.planChangeWithdrawnByAthlete;
      case 'overridden':
        return l10n.planChangeAppliedByAthlete;
      default:
        return '';
    }
  }

  String _describe(AppLocalizations l10n, PlanChangeWorkoutState s) {
    final tag = localeToTag(Localizations.localeOf(context));
    final day = formatDowDateShort(DateTime.parse(s.scheduledDate), tag);
    final kind = workoutKindLabel(l10n, workoutKindFromDb(s.kind));
    final distance = s.distanceM;
    final duration = s.durationS;
    final size = distance != null && distance > 0
        ? ' · ${fmtKm(distance)}'
        : duration != null && duration > 0
            ? ' · ${l10n.planChangeMinutes((duration / 60).round())}'
            : '';
    return '$day · $kind$size';
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      showTopBanner(context, done);
      await widget.onChanged();
    } catch (e) {
      debugPrint('plan change request action failed: $e');
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      showTopBanner(context, l10n.planChangeFailed(friendlyError(l10n, e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _today() => toIsoDate(widget.now());

  void _approve(AppLocalizations l10n) {
    final partial = _excluded.isNotEmpty;
    _run(
      () => widget.api.decidePlanChange(
        requestId: widget.request.id,
        approve: true,
        todayIso: _today(),
        workoutIds: partial
            ? [
                for (final l in widget.lines.workouts)
                  if (!_excluded.contains(l.workoutId)) l.workoutId,
              ]
            : null,
        weekIds: partial
            ? [
                for (final l in widget.lines.weeks)
                  if (!_excluded.contains(l.weekId)) l.weekId,
              ]
            : null,
        note: _note.text,
      ),
      l10n.planChangeApprovedToast,
    );
  }

  void _decline(AppLocalizations l10n) {
    _run(
      () => widget.api.decidePlanChange(
        requestId: widget.request.id,
        approve: false,
        todayIso: _today(),
        note: _note.text,
      ),
      l10n.planChangeDeclinedToast,
    );
  }

  Future<void> _withdraw(AppLocalizations l10n) async {
    final ok = await confirmDestructive(
      context,
      title: l10n.planChangeWithdrawConfirmTitle,
      body: l10n.planChangeWithdrawConfirmMessage,
      confirmLabel: l10n.planChangeWithdraw,
      cancelLabel: l10n.planChangeKeep,
    );
    if (!ok || !mounted) return;
    await _run(
      () => widget.api.withdrawPlanChange(widget.request.id),
      l10n.planChangeWithdrawnToast,
    );
  }

  void _applyMyself(AppLocalizations l10n) {
    _run(
      () => widget.api.applyPlanChangeMyself(widget.request.id, _today()),
      l10n.planChangeAppliedToast,
    );
  }

  Widget _line(
    BuildContext context,
    String id,
    String semantics,
    Widget content,
  ) {
    final l10n = AppLocalizations.of(context);
    if (!(_isCoach && _pending)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: content,
      );
    }
    return Row(
      children: [
        Checkbox(
          key: Key('plan-change-line-$id'),
          value: !_excluded.contains(id),
          onChanged: _busy
              ? null
              : (keep) => setState(() {
                    if (keep ?? false) {
                      _excluded.remove(id);
                    } else {
                      _excluded.add(id);
                    }
                  }),
          semanticLabel: l10n.planChangeIncludeLine(semantics),
        ),
        Expanded(child: content),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final note = widget.request.coachNote;
    return Card(
      key: const Key('plan-change-request'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tune, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.planChangeTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(_status(l10n), style: TextStyle(color: muted)),
            const SizedBox(height: 6),
            for (final l in widget.lines.workouts)
              _line(
                context,
                l.workoutId,
                _describe(l10n, l.before),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: _describe(l10n, l.before),
                      style: TextStyle(
                        color: muted,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    const TextSpan(text: '  →  '),
                    TextSpan(
                      text: l.after.skipped
                          ? l10n.planChangeSkipped
                          : _describe(l10n, l.after),
                    ),
                  ]),
                ),
              ),
            for (final w in widget.lines.weeks)
              _line(
                context,
                w.weekId,
                l10n.planChangeWeekLabel(w.weekIndex + 1),
                Text(l10n.planChangeWeekTarget(
                  w.weekIndex + 1,
                  fmtKm(w.beforeM ?? 0),
                  fmtKm(w.afterM ?? 0),
                )),
              ),
            if (widget.lines.unreadable > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(l10n.planChangeUnreadable,
                    style: TextStyle(color: muted)),
              ),
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(l10n.planChangeCoachNote(note)),
              ),
            if (_pending && _isCoach) ...[
              const SizedBox(height: 8),
              TextField(
                key: const Key('plan-change-note-input'),
                controller: _note,
                enabled: !_busy,
                minLines: 1,
                maxLines: 3,
                inputFormatters: [LengthLimitingTextInputFormatter(500)],
                decoration: InputDecoration(
                  labelText: l10n.planChangeNoteLabel,
                  hintText: l10n.planChangeNotePlaceholder,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  OutlinedButton(
                    key: const Key('plan-change-decline'),
                    onPressed: _busy ? null : () => _decline(l10n),
                    child: Text(l10n.planChangeDecline),
                  ),
                  FilledButton(
                    key: const Key('plan-change-approve'),
                    onPressed: _busy || _excluded.length >= _total
                        ? null
                        : () => _approve(l10n),
                    child: Text(_excluded.isEmpty
                        ? l10n.planChangeApprove
                        : l10n.planChangeApproveSelected),
                  ),
                ],
              ),
            ] else if (_pending) ...[
              const SizedBox(height: 8),
              Text(l10n.planChangeApplyMyselfHint,
                  style: TextStyle(color: muted)),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  OutlinedButton(
                    key: const Key('plan-change-withdraw'),
                    onPressed: _busy ? null : () => _withdraw(l10n),
                    child: Text(l10n.planChangeWithdraw),
                  ),
                  FilledButton.tonal(
                    key: const Key('plan-change-apply-myself'),
                    onPressed: _busy ? null : () => _applyMyself(l10n),
                    child: Text(l10n.planChangeApplyMyself),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

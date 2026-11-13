import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart'
    show
        AppBarAction,
        FieldColumn,
        ListSkeleton,
        PageHeader,
        PushedPage,
        SectionHeader,
        SheetScaffold,
        SkeletonBlock;

import '../auth_error.dart';
import '../column_limits.dart';
import '../local_crossings_store.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart' show activeLocaleTag;
import '../l10n/number_format.dart' show formatFixed;
import '../preferences.dart' show WeightFormat, activeWeightUnit;
import '../weigh_in_flag.dart';
import '../widgets/form_sheet.dart';
import '../widgets/top_banner.dart';
import '../widgets/loading_skeletons.dart';

/// Offline aid-station check-in for race-crew volunteers. Pick the checkpoint,
/// enter/scan a bib (account linkage optional), stamp IN / OUT. Writes flow
/// through [LocalCrossingsStore] so the surface works fully offline; the server
/// merges two volunteers' stamps via the upsert RPC. Reached from an
/// organiser-gated action on the event detail screen.
class CheckpointCheckinScreen extends StatefulWidget {
  final String eventId;
  final DateTime instanceStart;

  /// Test seam — production passes null and the screen builds its own.
  final ApiClient? api;
  final LocalCrossingsStore? store;

  const CheckpointCheckinScreen({
    super.key,
    required this.eventId,
    required this.instanceStart,
    this.api,
    this.store,
  });

  @override
  State<CheckpointCheckinScreen> createState() =>
      _CheckpointCheckinScreenState();
}

class _CheckpointCheckinScreenState extends State<CheckpointCheckinScreen> {
  late final ApiClient _api = widget.api ?? ApiClient();
  late final LocalCrossingsStore _store = widget.store ?? LocalCrossingsStore();
  final TextEditingController _bib = TextEditingController();

  List<EventCheckpointRow> _checkpoints = const [];
  EventCheckpointRow? _selected;
  bool _loading = true;
  bool _busy = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
    _load();
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    _bib.dispose();
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      if (_store.dir == null) await _store.init();
      final checkpoints = await _api.fetchEventCheckpoints(widget.eventId);
      // Best-effort overlay of already-synced crossings so the volunteer sees
      // who's been stamped from another phone; pending local stamps survive it.
      try {
        final crossings = await _api.fetchCheckpointCrossings(
            widget.eventId, widget.instanceStart);
        await _store.replaceFromServer(
          crossings.map((c) => c.toJson()).toList(),
          eventId: widget.eventId,
          instanceStart: widget.instanceStart,
        );
      } catch (_) {
        // Offline / not yet synced — the local store is the source of truth.
      }
      if (!mounted) return;
      setState(() {
        _checkpoints = checkpoints;
        _selected ??= checkpoints.isNotEmpty ? checkpoints.first : null;
        _loading = false;
      });
    } catch (e) {
      debugPrint('checkpoint check-in load failed: $e');
      if (!mounted) return;
      setState(() {
        _loadError = friendlyError(AppLocalizations.of(context), e);
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    await _store.syncWithServer(_api);
    await _load();
  }

  Future<void> _stamp({required bool isOut}) async {
    final cp = _selected;
    final bib = _bib.text.trim();
    if (cp == null) return;
    final l10n = AppLocalizations.of(context);
    if (bib.isEmpty) {
      showTopBanner(context, l10n.checkpointBibRequired);
      return;
    }

    var healthConsent = false;
    double? bodyWeightKg;
    bool? medicalHold;
    if (weighInGate && cp.requiresWeighIn) {
      final result = await _showWeighInSheet();
      if (result == null) return; // cancelled
      healthConsent = result.consent;
      if (healthConsent) {
        bodyWeightKg = result.bodyWeightKg;
        medicalHold = result.medicalHold;
      }
    }

    if (!mounted) return;
    setState(() => _busy = true);
    final now = DateTime.now().toUtc();
    try {
      await _store.createLocal(
        eventId: widget.eventId,
        checkpointId: cp.id,
        instanceStart: widget.instanceStart,
        bib: bib,
        inTime: isOut ? null : now,
        outTime: isOut ? now : null,
        healthConsent: healthConsent,
        bodyWeightKg: bodyWeightKg,
        medicalHold: medicalHold,
      );
      // Best-effort immediate push; the offline store keeps it pending on
      // failure and drains on the next refresh / connectivity return.
      try {
        await _store.syncWithServer(_api);
      } catch (e) {
        debugPrint('checkpoint check-in: immediate sync deferred: $e');
      }
      if (!mounted) return;
      _bib.clear();
      showTopBanner(
        context,
        isOut ? l10n.checkpointStampedOut(bib) : l10n.checkpointStampedIn(bib),
      );
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, l10n.checkpointStampFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<_WeighInResult?> _showWeighInSheet() {
    return showFormSheet<_WeighInResult>(
      context,
      builder: (ctx) => _WeighInSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return PushedPage(
      title: l10n.checkpointCheckinTitle,
      actions: [
        AppBarAction(
          icon: const Icon(Icons.sync),
          label: l10n.checkpointSyncNow,
          onPressed: _busy ? null : _refresh,
        ),
      ],
      // The title heads every state (loading, failed, empty) so the bar
      // never has to carry it, cut, on a narrow phone (TO-12); the unsynced
      // count rides under it rather than squeezing the toolbar. It scrolls
      // with the form: fixed above it, the heading and its subtitle took
      // half of a 320 x 640 phone at 2x text and left the Stamp buttons
      // under the fold.
      body: _buildBody(
        l10n,
        theme,
        PageHeader(
          title: l10n.checkpointCheckinTitle,
          subtitle: _store.hasPending ? l10n.checkpointPending : null,
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }

  /// A failed or empty read: the heading, then [child] centred in the rest.
  Widget _state(Widget header, Widget child) => CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(child: header),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: child),
          ),
        ],
      );

  Widget _buildBody(AppLocalizations l10n, ThemeData theme, Widget header) {
    if (_loading) {
      return ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          header,
          const SizedBox(height: 16),
          const FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: 0.3,
            child: SkeletonBlock(height: 12, radius: 4),
          ),
          const SizedBox(height: 8),
          const SkeletonBlock(height: 56),
          const SizedBox(height: 20),
          const SkeletonBlock(height: 56),
          const SizedBox(height: 16),
          const SkeletonStatStrip(cells: 2),
          const SizedBox(height: 16),
          ListSkeleton.section(
            label: l10n.commonLoading,
            hasLeading: false,
          ),
        ],
      );
    }
    if (_loadError != null) {
      return _state(
        header,
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.checkpointLoadFailed,
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              OutlinedButton(
                  onPressed: _load, child: Text(l10n.checkpointRetry)),
            ],
          ),
        ),
      );
    }
    if (_checkpoints.isEmpty) {
      return _state(
        header,
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.checkpointNone,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    final selected = _selected;
    final stamped = selected == null
        ? const <Map<String, dynamic>>[]
        : _store.rowsForCheckpoint(
            widget.eventId, selected.id, widget.instanceStart);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          header,
          const SizedBox(height: 16),
          SectionHeader(label: l10n.checkpointPickLabel),
          const SizedBox(height: 8),
          FieldColumn(children: [
            // Expanded, so a long checkpoint name ("Rucky Chucky river
            // crossing, far side") ellipsizes in the field rather than
            // overflowing it; the menu still lists each name in full.
            DropdownButtonFormField<String>(
              initialValue: selected?.id,
              isExpanded: true,
              items: [
                for (final cp in _checkpoints)
                  DropdownMenuItem(
                    value: cp.id,
                    child: Text(cp.requiresWeighIn && weighInGate
                        ? '${cp.name}  ⚖'
                        : cp.name),
                  ),
              ],
              onChanged: (id) => setState(() {
                _selected = _checkpoints.firstWhere((c) => c.id == id);
              }),
            ),
            TextField(
              controller: _bib,
              autofocus: true,
              textInputAction: TextInputAction.done,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(
                labelText: l10n.checkpointBibLabel,
                hintText: l10n.checkpointBibHint,
                prefixIcon: const Icon(Icons.tag),
              ),
              onSubmitted: (_) => _busy ? null : _stamp(isOut: false),
            ),
          ]),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _stamp(isOut: false),
                  icon: const Icon(Icons.login),
                  label: Text(l10n.checkpointStampIn),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _stamp(isOut: true),
                  icon: const Icon(Icons.logout),
                  label: Text(l10n.checkpointStampOut),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SectionHeader(label: l10n.checkpointLoggedHere(stamped.length)),
          const SizedBox(height: 6),
          if (stamped.isEmpty)
            Text(
              l10n.checkpointNoneLoggedHere,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          else
            for (final r in stamped)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.person_outline),
                title: Text(r['bib'] != null
                    ? l10n.checkpointBibRow('${r['bib']}')
                    : (r['runner_name'] as String? ?? '—')),
                subtitle: Text(_inOutSummary(l10n, r)),
              ),
        ],
      ),
    );
  }

  String _inOutSummary(AppLocalizations l10n, Map<String, dynamic> r) {
    String fmt(dynamic v) {
      final dt = v is String ? DateTime.tryParse(v)?.toLocal() : null;
      if (dt == null) return '—';
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }

    return l10n.checkpointInOut(fmt(r['in_time']), fmt(r['out_time']));
  }
}

class _WeighInResult {
  final bool consent;
  final double? bodyWeightKg;
  final bool? medicalHold;
  const _WeighInResult({
    required this.consent,
    this.bodyWeightKg,
    this.medicalHold,
  });
}

/// Art 9 weigh-in capture, only reachable when `WEIGH_IN_GATE` is on AND the
/// checkpoint requires a weigh-in. Body weight + medical hold persist only
/// after the explicit on-screen consent toggle (mirrors the Art 9 consent
/// pattern in settings_body_metrics_screen).
class _WeighInSheet extends StatefulWidget {
  @override
  State<_WeighInSheet> createState() => _WeighInSheetState();
}

class _WeighInSheetState extends State<_WeighInSheet> {
  static const _weightKey = 'checkpoint_crossings.body_weight_kg';

  final TextEditingController _weight = TextEditingController();
  bool _consent = false;
  bool _medicalHold = false;

  @override
  void initState() {
    super.initState();
    // `body_weight_kg` is CHECK-bounded 20..400 kg and this field had no
    // bound at all, so a mis-keyed weigh-in was a raw 23514 at an aid station
    // with no signal (decisions § 792).
    _weight.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _weight.removeListener(_onChanged);
    _weight.dispose();
    super.dispose();
  }

  /// The typed weight in canonical kg. The field is entered in the volunteer's
  /// own weight unit, so the bound has to be converted for the message too.
  double? get _typedKg =>
      WeightFormat.parseToKg(_weight.text, activeWeightUnit);

  bool get _outOfRange {
    final kg = _typedKg;
    return kg != null && !withinColumnLimit(_weightKey, kg);
  }

  static String _bound(num v) =>
      formatFixed(v.toDouble(), v == v.roundToDouble() ? 0 : 1, activeLocaleTag);

  String _rangeMessage(AppLocalizations l10n) {
    final b = WeightFormat.boundsIn(_weightKey, activeWeightUnit);
    return l10n.limitsWeightOutOfRange(
        _bound(b.min), _bound(b.max), WeightFormat.label(activeWeightUnit));
  }

  @override
  Widget build(BuildContext context) => SheetDiscardGuard(
        isDirty: () => _weight.text.trim().isNotEmpty,
        child: _sheet(context),
      );

  Widget _sheet(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SheetScaffold(
      padding: const EdgeInsets.all(20),
      actions: OverflowBar(
        alignment: MainAxisAlignment.end,
        overflowAlignment: OverflowBarAlignment.end,
        spacing: 8,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(l10n.checkpointCancel),
          ),
          FilledButton(
            onPressed: _outOfRange
                ? null
                : () {
                    Navigator.of(context).pop(_WeighInResult(
                      consent: _consent,
                      bodyWeightKg: _consent ? _typedKg : null,
                      medicalHold: _consent ? _medicalHold : null,
                    ));
                  },
            child: Text(l10n.checkpointWeighInSave),
          ),
        ],
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.checkpointWeighInTitle,
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            l10n.checkpointWeighInConsentBlurb,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.checkpointWeighInConsent,
                style: theme.textTheme.bodyMedium),
            value: _consent,
            onChanged: (v) => setState(() => _consent = v),
          ),
          if (_consent) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _weight,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l10n.checkpointWeighInBodyWeight,
                suffixText: WeightFormat.label(activeWeightUnit),
                errorText: _outOfRange ? _rangeMessage(l10n) : null,
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l10n.checkpointMedicalHold,
                  style: theme.textTheme.bodyMedium),
              value: _medicalHold,
              onChanged: (v) => setState(() => _medicalHold = v ?? false),
            ),
          ],
        ],
      ),
    );
  }
}

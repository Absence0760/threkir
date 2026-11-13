import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ui_kit/ui_kit.dart'
    show ActiveFilter, AppInsets, AppSearchField, AppSpace, AsyncView, ChoiceChipOption, EmptyState, FilterBar, HubTabBody, ListCard, LoadingState, StatusPill, buildChoiceChip, showFilterSheet;

import '../l10n/gen/app_localizations.dart';
import '../social_service.dart';
import '../widgets/error_state.dart';
import 'event_detail_screen.dart';

/// Cross-club activity search: the Social hub's Events tab (named Discover
/// until issue #1374). Mirrors
/// `apps/web/src/lib/components/SocialDiscover.svelte`: a search field plus
/// category / cadence / weekday / time-of-day / price filters over the
/// `search_public_events` RPC (public clubs only). Tapping a result opens
/// that club event's detail. A ui_kit `HubTabBody`: in the hub it draws no
/// app bar, pushed on its own it gets a small titled one.
class DiscoverScreen extends StatefulWidget {
  final ApiClient api;
  final SocialService social;

  const DiscoverScreen({
    super.key,
    required this.api,
    required this.social,
  });

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

const _weekdays = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _searchCtl = TextEditingController();
  Timer? _debounce;
  int _searchGen = 0;

  String _query = '';
  String _category = '';
  String _cadence = '';
  String _byday = '';
  String _time = '';
  String _paid = '';

  bool _loading = true;
  bool _error = false;
  List<PublicEventResult> _results = const [];

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _run);
  }

  Future<void> _run() async {
    final gen = ++_searchGen;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final next = await widget.api.searchPublicEvents(
        query: _query.trim().isEmpty ? null : _query.trim(),
        category: _category.isEmpty ? null : _category,
        cadence: _cadence.isEmpty ? null : _cadence,
        byday: _byday.isEmpty ? null : _byday,
        time: _time.isEmpty ? null : _time,
        paid: _paid.isEmpty ? null : _paid,
      );
      if (!mounted || gen != _searchGen) return;
      setState(() {
        _results = next;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || gen != _searchGen) return;
      setState(() {
        _results = const [];
        _error = true;
        _loading = false;
      });
    }
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _scheduleSearch();
  }

  void _openEvent(PublicEventResult e) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EventDetailScreen(
          social: widget.social,
          clubSlug: e.clubSlug,
          eventId: e.id,
        ),
      ),
    );
  }

  String _categoryLabel(AppLocalizations l10n, String c) {
    switch (c) {
      case 'run':
        return l10n.eventEditorCatRun;
      case 'cycle':
        return l10n.eventEditorCatCycle;
      case 'class':
        return l10n.eventEditorCatClass;
      case 'social':
        return l10n.eventEditorCatSocial;
      default:
        return c;
    }
  }

  String _weekdayLabel(AppLocalizations l10n, String code) {
    switch (code) {
      case 'MO':
        return l10n.discoverDayMon;
      case 'TU':
        return l10n.discoverDayTue;
      case 'WE':
        return l10n.discoverDayWed;
      case 'TH':
        return l10n.discoverDayThu;
      case 'FR':
        return l10n.discoverDayFri;
      case 'SA':
        return l10n.discoverDaySat;
      case 'SU':
        return l10n.discoverDaySun;
      default:
        return code;
    }
  }

  String _cadenceLabel(AppLocalizations l10n, PublicEventResult e) {
    if (e.recurrenceFreq == null) return l10n.discoverOneOff;
    final freq = switch (e.recurrenceFreq) {
      'weekly' => l10n.discoverWeekly,
      'biweekly' => l10n.discoverBiweekly,
      'monthly' => l10n.discoverMonthly,
      _ => l10n.discoverWeekly,
    };
    final days = (e.recurrenceByday ?? [])
        .map((d) => _weekdayLabel(l10n, d))
        .join(', ');
    return days.isEmpty ? freq : '$freq · $days';
  }

  String _priceLabel(AppLocalizations l10n, PublicEventResult e) {
    if (e.priceCents == null) return l10n.discoverFree;
    final amount = e.priceCents! / 100.0;
    final code = (e.currency ?? 'usd').toUpperCase();
    try {
      return NumberFormat.simpleCurrency(name: code).format(amount);
    } catch (_) {
      return '${amount.toStringAsFixed(2)} $code';
    }
  }

  String _cadenceFilterLabel(AppLocalizations l10n, String v) => switch (v) {
        'one_off' => l10n.discoverOneOff,
        'weekly' => l10n.discoverWeekly,
        'biweekly' => l10n.discoverBiweekly,
        'monthly' => l10n.discoverMonthly,
        _ => l10n.discoverCadenceAny,
      };

  String _timeFilterLabel(AppLocalizations l10n, String v) => switch (v) {
        'morning' => l10n.discoverMorning,
        'afternoon' => l10n.discoverAfternoon,
        'evening' => l10n.discoverEvening,
        _ => l10n.discoverTimeAny,
      };

  String _priceFilterLabel(AppLocalizations l10n, String v) => switch (v) {
        'free' => l10n.discoverFree,
        'paid' => l10n.discoverPaid,
        _ => l10n.discoverPriceAny,
      };

  bool get _filtered =>
      _query.trim().isNotEmpty ||
      _category.isNotEmpty ||
      _cadence.isNotEmpty ||
      _byday.isNotEmpty ||
      _time.isNotEmpty ||
      _paid.isNotEmpty;

  void _set(VoidCallback change) {
    setState(change);
    _run();
  }

  void _clearFilters() {
    _debounce?.cancel();
    _searchCtl.clear();
    _set(() {
      _query = '';
      _category = '';
      _cadence = '';
      _byday = '';
      _time = '';
      _paid = '';
    });
  }

  /// Search, the category as the quick chips, and cadence, weekday, time of
  /// day and price in the Filters sheet, each shown as a removable chip while
  /// it is on. The always-open block of a field, two chip rows and three
  /// dropdowns took the first screen before any result (issue #1374).
  FilterBar _filterBar(AppLocalizations l10n) {
    ActiveFilter active(String label, VoidCallback onRemove) => ActiveFilter(
          label: label,
          onRemove: onRemove,
          removeTooltip: l10n.filterBarRemoveFilter(label),
        );
    final filters = [
      if (_cadence.isNotEmpty)
        active(_cadenceFilterLabel(l10n, _cadence),
            () => _set(() => _cadence = '')),
      if (_byday.isNotEmpty)
        active(_weekdayLabel(l10n, _byday), () => _set(() => _byday = '')),
      if (_time.isNotEmpty)
        active(_timeFilterLabel(l10n, _time), () => _set(() => _time = '')),
      if (_paid.isNotEmpty)
        active(_priceFilterLabel(l10n, _paid), () => _set(() => _paid = '')),
    ];
    return FilterBar(
      key: const ValueKey('events-filter-bar'),
      search: Semantics(
        textField: true,
        label: l10n.discoverSearchPlaceholder,
        child: AppSearchField(
          controller: _searchCtl,
          hint: l10n.discoverSearchPlaceholder,
          clearTooltip: l10n.commonClearSearch,
          onChanged: _onQueryChanged,
        ),
      ),
      chips: [
        for (final c in const ['', 'run', 'cycle', 'class', 'social'])
          buildChoiceChip<String>(
            context,
            ChoiceChipOption(
              value: c,
              label: c.isEmpty
                  ? l10n.discoverActivityAll
                  : _categoryLabel(l10n, c),
            ),
            _category,
            (v) => _set(() => _category = v),
          ),
      ],
      activeFilters: filters,
      filtersLabel: l10n.filterBarFilters,
      filtersSemanticLabel:
          filters.isEmpty ? null : l10n.filterBarFiltersCount(filters.length),
      activeFilterCount: filters.length,
      onOpenFilters: _openFilters,
    );
  }

  Future<void> _openFilters() {
    final l10n = AppLocalizations.of(context);
    return showFilterSheet(
      context: context,
      title: l10n.filterBarFilters,
      doneLabel: l10n.filterBarDone,
      builder: (sheetContext, setSheet) {
        final theme = Theme.of(sheetContext);
        Widget group(String heading, List<String> values, String selected,
                String Function(String) label, ValueChanged<String> onPick) =>
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(heading, style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpace.sm),
                  Semantics(
                    container: true,
                    label: heading,
                    child: Wrap(
                      spacing: AppSpace.sm,
                      children: [
                        for (final v in values)
                          ChoiceChip(
                            label: Text(label(v)),
                            selected: v == selected,
                            onSelected: (_) {
                              onPick(v);
                              setSheet(() {});
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            group(
              l10n.discoverCadenceLabel,
              const ['', 'one_off', 'weekly', 'biweekly', 'monthly'],
              _cadence,
              (v) => _cadenceFilterLabel(l10n, v),
              (v) => _set(() => _cadence = v),
            ),
            group(
              l10n.discoverDayLabel,
              const ['', ..._weekdays],
              _byday,
              (v) => v.isEmpty ? l10n.discoverDayAny : _weekdayLabel(l10n, v),
              (v) => _set(() => _byday = v),
            ),
            group(
              l10n.discoverTimeLabel,
              const ['', 'morning', 'afternoon', 'evening'],
              _time,
              (v) => _timeFilterLabel(l10n, v),
              (v) => _set(() => _time = v),
            ),
            group(
              l10n.discoverPriceLabel,
              const ['', 'free', 'paid'],
              _paid,
              (v) => _priceFilterLabel(l10n, v),
              (v) => _set(() => _paid = v),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return HubTabBody(
      title: l10n.socialTabEvents,
      filters: _filterBar(l10n),
      onRefresh: _run,
      body: AsyncView<List<PublicEventResult>>(
        loading: _loading,
        error: _error ? l10n.discoverSearchFailed : null,
        data: _results,
        isEmpty: (r) => r.isEmpty,
        loadingState: LoadingState.list(
          label: l10n.discoverLoading,
          hasLeading: false,
        ),
        errorBuilder: (_, _) =>
            AppErrorState(message: l10n.discoverSearchFailed, onRetry: _run),
        empty: EmptyState(
          icon: Icons.event_busy,
          title: l10n.discoverEmpty,
          ctaLabel: _filtered ? l10n.feedClearFilters : null,
          ctaIcon: Icons.filter_alt_off,
          onCta: _filtered ? _clearFilters : null,
        ),
        builder: (_, results) => ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(AppInsets.gutter, AppSpace.sm,
              AppInsets.gutter, AppSpace.md + MediaQuery.paddingOf(context).bottom),
          itemCount: results.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppInsets.itemGap),
          itemBuilder: (_, i) => _ResultCard(
            event: results[i],
            title: (results[i].discipline?.isNotEmpty ?? false)
                ? results[i].discipline!
                : results[i].title,
            meta:
                '${_categoryLabel(l10n, results[i].category)} · ${_cadenceLabel(l10n, results[i])}',
            price: _priceLabel(l10n, results[i]),
            free: results[i].priceCents == null,
            onTap: () => _openEvent(results[i]),
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final PublicEventResult event;
  final String title;
  final String meta;
  final String price;
  final bool free;
  final VoidCallback onTap;

  const _ResultCard({
    required this.event,
    required this.title,
    required this.meta,
    required this.price,
    required this.free,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListCard.row(
      margin: EdgeInsets.zero,
      dense: true,
      onTap: onTap,
      title: title,
      titleMaxLines: 1,
      badge: StatusPill(
        label: price,
        foreground: free
            ? theme.colorScheme.onSurfaceVariant
            : theme.colorScheme.onPrimaryContainer,
        fill: free
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.primaryContainer,
      ),
      subtitle: event.clubName,
      subtitleMaxLines: 1,
      meta: Text(meta,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}

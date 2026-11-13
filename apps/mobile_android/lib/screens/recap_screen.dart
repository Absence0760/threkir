import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart'
    show AppBarAction, ChoiceChipOption, ChoiceChipRow, ListCard, PageHeader, PushedPage;

import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../local_run_store.dart';
import '../park_courses.dart';
import '../preferences.dart';
import '../recap.dart';
import '../share_sheet.dart';
import '../web_base_url.dart';
import '../widgets/recap_share_card.dart';
import '../widgets/sign_in_required_state.dart';
import '../widgets/top_banner.dart';

/// Which calendar window the recap covers.
enum RecapPeriod { year, month }

/// Year-in-running / month-in-running recap. Mobile mirror of web
/// `/recap/[year]` and `/recap/[year]/[month]` — the two web routes collapse
/// into one screen here with a period toggle, matching how
/// `period_summary_screen` already lets one surface walk week / month /
/// all-time.
///
/// Reads runs from the local store (no extra Supabase round-trip) and builds
/// the hero numbers via `buildYearInRunningRecap` / `buildMonthInRunningRecap`.
/// Includes a share CTA that opens a sheet sharing the recap as a square or
/// story image (the web card's layout, `recap_card_layout.dart`) or as a
/// short text summary,
/// plus a "Publish & share link" action (when `api` is wired) that freezes a
/// public snapshot via the web `public_recaps` table and shares the web
/// /recap/share/[id] link — the device OS-share-sheet is the mobile-additive
/// part; the page it links to is web-canonical.
class RecapScreen extends StatefulWidget {
  final LocalRunStore runStore;
  final Preferences preferences;
  final int? year;

  /// 1-based. When set the screen opens on the monthly recap.
  final int? month;

  /// Optional — when wired, enables the "Publish & share link" action.
  final ApiClient? api;

  const RecapScreen({
    super.key,
    required this.runStore,
    required this.preferences,
    this.year,
    this.month,
    this.api,
  });

  @override
  State<RecapScreen> createState() => _RecapScreenState();
}

class _RecapScreenState extends State<RecapScreen> {
  late RecapPeriod _period;
  late int _year;
  late int _month;
  bool _publishing = false;

  /// The period's park lines, keyed by the period they were read for so a
  /// late answer for the previous period is never shown under the new one.
  RecapParkSummary? _parks;
  String? _parksKey;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = widget.year ?? now.year;
    _month = widget.month ?? now.month;
    _period = widget.month == null ? RecapPeriod.year : RecapPeriod.month;
    widget.runStore.addListener(_onChanged);
    widget.preferences.addListener(_onChanged);
    _loadParks();
  }

  /// L4: the park lines are auxiliary. A failed or signed-out read leaves the
  /// recap without them and changes nothing else.
  Future<void> _loadParks() async {
    final api = widget.api;
    if (api == null || api.userId == null) return;
    final key = _periodKey;
    final start = _period == RecapPeriod.year
        ? DateTime(_year)
        : DateTime(_year, _month);
    final end = _period == RecapPeriod.year
        ? DateTime(_year + 1)
        : DateTime(_year, _month + 1);
    try {
      final rows = await api.fetchRecapParkCourses(start, end);
      if (!mounted || key != _periodKey) return;
      setState(() {
        _parksKey = key;
        _parks = recapParkSummary([
          for (final r in rows)
            RecapParkRow(
              parkId: r.parkId,
              parkName: r.parkName,
              regionCode: r.regionCode,
              courseId: r.courseId,
            ),
        ]);
      });
    } catch (e) {
      debugPrint('recap park courses read failed: $e');
    }
  }

  @override
  void dispose() {
    widget.runStore.removeListener(_onChanged);
    widget.preferences.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  YearInRunningRecap _buildRecap() {
    // Reads the full-history index (distance / duration / elevation_m /
    // activity_type) — no track, so the lightweight summaries are exact and
    // stay correct once `runs` becomes a resident window.
    final runs = widget.runStore.summaryRuns;
    final parks = _parksKey == _periodKey ? _parks : null;
    final extras = RecapExtras(
      parkCourseCount: parks?.courseCount ?? 0,
      parkCount: parks?.parkCount ?? 0,
    );
    return _period == RecapPeriod.year
        ? buildYearInRunningRecap(runs, _year, extras)
        : buildMonthInRunningRecap(runs, _year, _month, extras);
  }

  bool get _outOfRange => _year < 2000 || _year > DateTime.now().year + 1;

  bool get _atLatestPeriod {
    final now = DateTime.now();
    if (_period == RecapPeriod.year) return _year >= now.year;
    return _year > now.year || (_year == now.year && _month >= now.month);
  }

  String _periodLabel(String localeTag) => _period == RecapPeriod.year
      ? '$_year'
      : '${formatMonthName(DateTime(_year, _month), localeTag)} $_year';

  /// `public_recaps.period_kind` / `period_key` — the same wire pair the web
  /// routes upsert on, so a recap published from either client refreshes the
  /// one share link instead of minting a second.
  String get _periodKind => _period == RecapPeriod.year ? 'year' : 'month';

  String get _periodKey => _period == RecapPeriod.year
      ? '$_year'
      : '$_year-${_month.toString().padLeft(2, '0')}';

  void _shiftPeriod(int delta) {
    setState(() {
      if (_period == RecapPeriod.year) {
        _year += delta;
        return;
      }
      // DateTime normalises a month of 0 or 13 into the adjacent year.
      final shifted = DateTime(_year, _month + delta);
      _year = shifted.year;
      _month = shifted.month;
    });
    _loadParks();
  }

  void _selectPeriod(RecapPeriod period) {
    if (period == _period) return;
    setState(() => _period = period);
    _loadParks();
  }

  String get _webBase => resolveWebBaseUrl();

  Future<void> _publishAndShare(YearInRunningRecap recap, String label) async {
    final api = widget.api;
    if (api == null || _publishing) return;
    if (!await ensureSignedIn(context, viewerId: api.userId, api: api)) {
      return;
    }
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _publishing = true);
    try {
      final id = await api.publishRecap(
        periodKind: _periodKind,
        periodKey: _periodKey,
        snapshot: recapSnapshotJson(recap),
      );
      if (!mounted) return;
      if (id == null) {
        showTopBanner(context, l10n.recapPublishFailed);
        return;
      }
      await shareTextFrom(
        context,
        text: '$_webBase/recap/share/$id',
        subject: _shareSubject(l10n, label),
      );
    } catch (e) {
      debugPrint('publishAndShare failed: $e');
      if (mounted) showTopBanner(context, l10n.recapPublishFailed);
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  String _shareSubject(AppLocalizations l10n, String label) =>
      _period == RecapPeriod.year
          ? l10n.recapShareSubject(_year)
          : l10n.recapMonthShareSubject(label);

  Future<void> _share(YearInRunningRecap recap, String label) async {
    final l10n = AppLocalizations.of(context);
    final total = UnitFormat.distance(recap.totalDistanceM, widget.preferences.unit);
    final lines = <String>[
      _period == RecapPeriod.year
          ? l10n.recapShareHeadline(_year)
          : l10n.recapMonthShareHeadline(label),
      l10n.recapShareTotals(total, recap.runCount),
      if (recap.longestRunM > 0)
        l10n.recapShareLongestRun(
            UnitFormat.distance(recap.longestRunM, widget.preferences.unit)),
      if (recap.bestStreakDays > 0)
        l10n.recapShareBestStreak(recap.bestStreakDays),
    ];
    await shareTextFrom(
      context,
      text: lines.join('\n'),
      subject: _shareSubject(l10n, label),
    );
  }

  Future<void> _openShareSheet(YearInRunningRecap recap, String label) {
    final l10n = AppLocalizations.of(context);
    return showRecapShareSheet(
      context,
      text: recapCardText(l10n, recap, widget.preferences.unit, label),
      fileStem: 'threkir-$_periodKey',
      subject: _shareSubject(l10n, label),
      shareText: () => _share(recap, label),
      videoUrl: recapVideoExportUrl(_year,
          month: _period == RecapPeriod.month ? _month : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final unit = widget.preferences.unit;
    final localeTag = localeToTag(Localizations.localeOf(context));
    final label = _periodLabel(localeTag);
    final recap = _buildRecap();

    final title =
        _period == RecapPeriod.year ? l10n.recapTitle : l10n.recapMonthTitle;
    return PushedPage(
      title: title,
      actions: [
        if (widget.api != null)
          AppBarAction(
            icon: _publishing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.link),
            label: l10n.recapPublishAndShare,
            onPressed: recap.runCount == 0 || _publishing
                ? null
                : () => _publishAndShare(recap, label),
          ),
        AppBarAction(
          icon: const Icon(Icons.share_outlined),
          label: l10n.recapShareTooltip,
          onPressed:
              recap.runCount == 0 ? null : () => _openShareSheet(recap, label),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          PageHeader(
            title: title,
            padding: const EdgeInsets.only(top: 16, bottom: 12),
          ),
          Center(
            child: ChoiceChipRow<RecapPeriod>(
              alignment: WrapAlignment.center,
              options: [
                ChoiceChipOption(
                    value: RecapPeriod.year, label: l10n.recapPeriodYear),
                ChoiceChipOption(
                    value: RecapPeriod.month, label: l10n.recapPeriodMonth),
              ],
              selected: _period,
              onChanged: _selectPeriod,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: _period == RecapPeriod.year
                    ? l10n.recapPrevYear
                    : l10n.recapPrevMonth,
                onPressed: () => _shiftPeriod(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineMedium),
              ),
              IconButton(
                tooltip: _period == RecapPeriod.year
                    ? l10n.recapNextYear
                    : l10n.recapNextMonth,
                onPressed: _atLatestPeriod ? null : () => _shiftPeriod(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_outOfRange) ...[
            ListCard(
              child: Text(
                l10n.recapNoRunsForPeriod(label),
                style: theme.textTheme.titleMedium,
              ),
            ),
          ] else if (recap.runCount == 0) ...[
            ListCard(
              child: Text(
                l10n.recapNoRunsYetInPeriod(label),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ] else ...[
            // Hero distance
            ListCard(
              child: Column(
                children: [
                  Text(
                    UnitFormat.distance(recap.totalDistanceM, unit),
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.recapAcrossRuns(recap.runCount,
                        recap.runCount == 1 ? 'run' : 'runs'),
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: l10n.recapLongestRunLabel,
                    value: UnitFormat.distance(recap.longestRunM, unit),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    label: l10n.recapBestStreakLabel,
                    value: l10n.recapStreakDays(recap.bestStreakDays,
                        recap.bestStreakDays == 1 ? 'day' : 'days'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: l10n.recapTopWeekLabel,
                    value: recap.topWeek == null
                        ? '—'
                        : UnitFormat.distance(
                            recap.topWeek!.distanceM, unit),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    label: l10n.recapUniqueRoutesLabel,
                    value: '${recap.uniqueRouteCount}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: l10n.recapEarliestStartLabel,
                    value: recap.earliestStartLocal ?? '—',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    label: l10n.recapLatestStartLabel,
                    value: recap.latestStartLocal ?? '—',
                  ),
                ),
              ],
            ),
            if (recap.parkCourseCount > 0) ...[
              const SizedBox(height: 12),
              _StatCard(
                key: const Key('recap-park-courses'),
                label: l10n.recapParkCoursesLabel,
                value: '${recap.parkCourseCount}',
                sub: l10n.recapParkCoursesSub(recap.parkCount),
              ),
            ],
            if (_parksKey == _periodKey && (_parks?.parks.isNotEmpty ?? false)) ...[
              const SizedBox(height: 16),
              Text(l10n.recapParksHeading, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              for (final p in _parks!.parks)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.park_outlined),
                  title: Text(p.name),
                  subtitle: Text(regionName(p.regionCode)),
                  trailing: Text(l10n.recapParkCourseCount(p.courseCount)),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  const _StatCard({super.key, required this.label, required this.value, this.sub});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: theme.textTheme.titleLarge),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

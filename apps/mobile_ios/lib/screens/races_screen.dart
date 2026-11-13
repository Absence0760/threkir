import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/gen/app_localizations.dart';
import '../fab_clearance.dart';
import '../preferences.dart' show formatDistanceForPref;
import '../race_plan_preset.dart';
import '../race_provider_labels.dart';
import '../provenance.dart';
import '../race_service.dart';
import '../training.dart' show toIsoDate;
import '../training_service.dart';
import '../widgets/error_state.dart';
import '../widgets/help_button.dart';
import '../widgets/provenance_badge.dart';
import '../widgets/run_any_time_section.dart';
import '../widgets/top_banner.dart';
import 'plan_new_screen.dart';
import 'race_detail_screen.dart';

/// Races & courses (issue #1352): the race calendar under **Upcoming races**,
/// and the park courses that can be run on any day under **Run any time**.
/// Mirrors the web `/races` page.
///
/// Upcoming races is the race calendar discovery of race_calendar.md: a name
/// search + distance-band chips + "near a place" geocode over the
/// `search_race_listings` RPC, with a race-page link per result, a name that
/// opens the race detail screen, and an "Import my result" affordance from
/// race day on (manual paste always; a provider pull when that listing's
/// provider has a leg and its key is configured). An "Add a race" action
/// submits a crowd listing.
///
/// Run any time is [RunAnyTimeSection], which loads and fails on its own; it
/// needs a client, so a mount without one shows the races alone.
///
/// A tab of the Fitness hub (decisions § 2437), and pushed as itself only
/// where no shell is listening (`openFitnessSurface`). NOT a bottom-nav
/// destination (the 5-slot ceiling holds, decisions §63).
///
/// Nothing gates reaching it: the search is a public RPC, and
/// [RaceService.isProviderConfigured] gates only the *provider* import path
/// inside the per-race import sheet, which probes the listing it was opened
/// for rather than a provider chosen up front.
class RacesScreen extends StatefulWidget {
  final RaceService service;
  final String? mapTilerKey;

  /// The client the Run any time section reads park courses through. Null
  /// leaves the section out.
  final ApiClient? api;

  /// Test-only DI seam for the plan wizard the "train for this race" action
  /// opens; production callsites let the screen build its own.
  final TrainingService? training;

  /// Which view is showing, shared with the shell so a link elsewhere (the
  /// Segments tab's Park courses action) can open the Courses view of the
  /// tab already in the hub (decisions § 2480). Null in standalone mounts,
  /// where the screen owns one starting at [initialShow].
  final ValueNotifier<RacesShow>? show;
  final RacesShow initialShow;

  const RacesScreen({
    super.key,
    required this.service,
    this.mapTilerKey,
    this.api,
    this.training,
    this.show,
    this.initialShow = RacesShow.all,
  });

  @override
  State<RacesScreen> createState() => _RacesScreenState();
}

const _distanceBands = ['', '5k', '10k', 'half', 'marathon', 'ultra'];

/// What Races & courses shows: both sections, the race calendar alone, or the
/// park courses alone. Mirrors web `/races?show=`.
enum RacesShow { all, races, courses }

/// How far back Recent results looks, in days. Mirrors web's
/// `RECENT_WINDOW_DAYS` on `/races`.
const recentWindowDays = 30;

class _RacesScreenState extends State<RacesScreen> {
  final _searchCtl = TextEditingController();
  final _placeCtl = TextEditingController();
  Timer? _debounce;
  int _gen = 0;

  String _query = '';
  String _distance = '';
  bool _recent = false;
  String _nearPlace = '';
  late final ValueNotifier<RacesShow> _show =
      widget.show ?? ValueNotifier(widget.initialShow);

  bool _loading = true;
  bool _error = false;
  List<RaceListingView> _results = const [];

  late final TrainingService _training = widget.training ?? TrainingService();

  @override
  void initState() {
    super.initState();
    _show.addListener(_onShow);
    _run();
  }

  void _onShow() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _show.removeListener(_onShow);
    if (widget.show == null) _show.dispose();
    _debounce?.cancel();
    _searchCtl.dispose();
    _placeCtl.dispose();
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _run);
  }

  Future<void> _run() async {
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _error = false;
    });
    final today = DateTime.now();
    try {
      final next = await widget.service.searchRaceListings(
        query: _query,
        distance: _distance.isEmpty ? null : _distance,
        from: _recent
            ? toIsoDate(
                DateTime(today.year, today.month, today.day - recentWindowDays))
            : null,
        to: _recent
            ? toIsoDate(DateTime(today.year, today.month, today.day - 1))
            : null,
        newestFirst: _recent,
        nearPlace: _nearPlace.isEmpty ? null : _nearPlace,
        mapTilerKey: widget.mapTilerKey,
      );
      if (!mounted || gen != _gen) return;
      setState(() {
        _results = next;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  String _bandLabel(AppLocalizations l, String band) {
    switch (band) {
      case '5k':
        return l.racesDistance5k;
      case '10k':
        return l.racesDistance10k;
      case 'half':
        return l.racesDistanceHalf;
      case 'marathon':
        return l.racesDistanceMarathon;
      case 'ultra':
        return l.racesDistanceUltra;
      default:
        return l.racesDistanceAny;
    }
  }

  Future<void> _openSubmit() async {
    final created = await showRaceListingForm(context, widget.service);
    if (created == true) _run();
  }

  /// Open the plan wizard sized around this race. The listing's own facts go
  /// across, not the derived dates — the wizard re-derives them against today,
  /// so the arithmetic has one home (decisions § 606).
  Future<void> _trainForRace(RaceListingView race) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlanNewScreen(
          training: _training,
          raceDateIso: race.raceDate,
          raceName: race.name,
          raceDistanceM: race.distanceM,
        ),
      ),
    );
  }

  Future<void> _openDetail(RaceListingView race) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RaceDetailScreen(
          service: widget.service,
          listingId: race.id,
          training: _training,
        ),
      ),
    );
  }

  Future<void> _openImport(RaceListingView race) async {
    final done = await showRaceImportSheet(
      context,
      service: widget.service,
      race: race,
    );
    if (done == true && mounted) {
      showTopBanner(context, AppLocalizations.of(context).racesImported);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final api = widget.api;
    final racesShown = _show.value != RacesShow.courses;
    return HubTabBody(
      title: l.runSurfaceTabRacesCourses,
      // No primary action: "Add a race" contributes a listing, which few
      // people do and nobody comes here to do, so it waits in the overflow
      // rather than holding the FAB (issue #1374 report 2).
      actions: [
        const HelpButton(routes: ['/races']),
        PopupMenuButton<void>(
          key: const Key('races-overflow'),
          itemBuilder: (_) => [
            PopupMenuItem<void>(
              onTap: _openSubmit,
              child: ListTile(
                leading: const Icon(Icons.add),
                title: Text(l.racesSubmitRace),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ],
      filters: _filterBar(l, api: api, racesShown: racesShown),
      onRefresh: racesShown ? _run : null,
      // One scroll for both sections: Upcoming races first, as on web, then
      // Run any time below the results.
      body: CustomScrollView(
        key: const Key('races-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (racesShown) ..._raceSlivers(l, theme),
          if (api != null && _show.value != RacesShow.races)
            // Keyed so switching views keeps its courses, records and fix
            // rather than reading them again.
            SliverToBoxAdapter(
              key: const Key('races-any-time-sliver'),
              child: RunAnyTimeSection(
                api: api,
                limit: _show.value == RacesShow.courses
                    ? null
                    : kRunAnyTimeLimit,
                showParks: _show.value == RacesShow.courses,
              ),
            ),
          SliverToBoxAdapter(
            child: SizedBox(height: fabScrollClearance(context)),
          ),
        ],
      ),
    );
  }

  /// The race search and Filters (hidden with the race calendar in Courses),
  /// the All · Races · Courses view on the one chip line, and the filters
  /// that are on as removable chips after it.
  FilterBar _filterBar(AppLocalizations l,
      {required ApiClient? api, required bool racesShown}) {
    ActiveFilter active(String label, VoidCallback onRemove) => ActiveFilter(
          label: label,
          onRemove: onRemove,
          removeTooltip: l.filterBarRemoveFilter(label),
        );
    return FilterBar(
      key: const Key('races-filter-bar'),
      search: racesShown
          ? AppSearchField(
              controller: _searchCtl,
              hint: l.racesSearchPlaceholder,
              clearTooltip: l.commonClearSearch,
              onChanged: (v) {
                _query = v;
                _schedule();
              },
            )
          : null,
      chipsLabel: api == null ? null : l.racesShowGroup,
      chips: [
        if (api != null)
          for (final o in [
            ChoiceChipOption(value: RacesShow.all, label: l.racesShowAll),
            ChoiceChipOption(value: RacesShow.races, label: l.racesShowRaces),
            ChoiceChipOption(
                value: RacesShow.courses, label: l.racesShowCourses),
          ])
            buildChoiceChip<RacesShow>(
                context, o, _show.value, (v) => _show.value = v),
      ],
      activeFilters: racesShown
          ? [
              if (_recent) active(l.racesWhenRecent, () => _setRecent(false)),
              if (_distance.isNotEmpty)
                active(_bandLabel(l, _distance), () => _setDistance('')),
              if (_nearPlace.trim().isNotEmpty)
                active(l.racesNearChip(_nearPlace.trim()), _clearNear),
            ]
          : const [],
      filtersLabel: racesShown ? l.filterBarFilters : null,
      filtersSemanticLabel:
          _activeCount > 0 ? l.filterBarFiltersCount(_activeCount) : null,
      activeFilterCount: _activeCount,
      onOpenFilters: racesShown ? _openFilters : null,
    );
  }

  List<Widget> _raceSlivers(AppLocalizations l, ThemeData theme) => [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppInsets.gutter,
                AppInsets.pageTop, AppInsets.gutter, AppSpace.xs),
            child: Semantics(
              header: true,
              child: Text(l.racesSectionUpcoming,
                  style: theme.textTheme.titleMedium),
            ),
          ),
        ),
        _buildResults(l),
      ];

  int get _activeCount =>
      (_distance.isEmpty ? 0 : 1) +
      (_recent ? 1 : 0) +
      (_nearPlace.trim().isEmpty ? 0 : 1);

  void _setRecent(bool recent) {
    setState(() => _recent = recent);
    _run();
  }

  void _setDistance(String band) {
    setState(() => _distance = band);
    _run();
  }

  void _clearNear() {
    _placeCtl.clear();
    setState(() => _nearPlace = '');
    _run();
  }

  Future<void> _openFilters() {
    final l = AppLocalizations.of(context);
    return showFilterSheet(
      context: context,
      title: l.filterBarFilters,
      doneLabel: l.filterBarDone,
      builder: (sheetContext, setSheet) {
          // Each change applies at once, so the list behind the sheet and the
          // chips above it are already right when it closes.
          void apply(VoidCallback change) {
            change();
            setSheet(() {});
          }

          final theme = Theme.of(sheetContext);
          return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _placeCtl,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.place),
                      hintText: l.racesNearPlace,
                      isDense: true,
                    ),
                    onChanged: (v) => apply(() {
                      setState(() => _nearPlace = v);
                      _schedule();
                    }),
                  ),
                  const SizedBox(height: 16),
                  Text(l.racesWhenGroup, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  // semantics-children: a group name, read once before the controls inside it
                  Semantics(
                    container: true,
                    label: l.racesWhenGroup,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(l.racesWhenUpcoming),
                          selected: !_recent,
                          onSelected: (_) => apply(() => _setRecent(false)),
                        ),
                        ChoiceChip(
                          label: Text(l.racesWhenRecent),
                          selected: _recent,
                          onSelected: (_) => apply(() => _setRecent(true)),
                        ),
                      ],
                    ),
                  ),
                  if (_recent)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        l.racesWhenHint(recentWindowDays),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(l.racesDistanceGroup, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  // A Wrap, not a fixed-height lane: a chip needs 58 px at 2x
                  // OS text scale and a 40 px lane cropped its label (and stole
                  // its 48 dp tap target at 1.0x).
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final band in _distanceBands)
                        ChoiceChip(
                          label: Text(_bandLabel(l, band)),
                          selected: _distance == band,
                          onSelected: (_) => apply(() => _setDistance(band)),
                        ),
                    ],
                  ),
                ],
              );
      },
    );
  }

  Widget _buildResults(AppLocalizations l) {
    if (_loading) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        sliver: SliverToBoxAdapter(
          child: ListSkeleton.section(
              label: l.commonLoading, rows: 3, hasLeading: false),
        ),
      );
    }
    if (_error) {
      return SliverToBoxAdapter(
        child: AppErrorState(message: l.racesSearchFailed, onRetry: _run),
      );
    }
    if (_results.isEmpty) {
      return SliverToBoxAdapter(
        child: EmptyState(
          icon: Icons.flag_outlined,
          title: _recent ? l.racesEmptyRecent(recentWindowDays) : l.racesEmpty,
        ),
      );
    }
    return SliverList.builder(
      itemCount: _results.length,
      itemBuilder: (context, i) => _RaceCard(
        race: _results[i],
        onImport: () => _openImport(_results[i]),
        onOpen: () => _openDetail(_results[i]),
        onTrainFor: () => _trainForRace(_results[i]),
      ),
    );
  }
}

class _RaceCard extends StatelessWidget {
  final RaceListingView race;
  final VoidCallback onImport;
  final VoidCallback onTrainFor;
  final VoidCallback onOpen;

  const _RaceCard({
    required this.race,
    required this.onImport,
    required this.onTrainFor,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // Only offer to build a plan when one can actually be built for this race
    // — a past or too-close race gets no action rather than one that lands on
    // a refusal. The wizard re-derives from the same helper, so a list left
    // open across midnight is caught there too.
    final today = toIsoDate(DateTime.now());
    final canTrainFor = racePlanPreset(
      raceDateIso: race.raceDate,
      distanceM: race.distanceM,
      todayIso: today,
    ).ok;
    // A result exists only from race day on; before that the import can only
    // come back empty, so the action is not offered.
    final canImport = race.raceDate.compareTo(today) <= 0;
    final provenance = raceListingProvenance(
      organiserIsOfficial: race.organiserIsOfficial,
      provider: race.provider,
      isVerified: race.isVerified,
    );
    final meta = <String>[
      _formatRaceDate(race.raceDate),
      if (race.distanceM != null)
        formatDistanceForPref(race.distanceM!.toDouble()),
      if (race.locationLabel != null) race.locationLabel!,
      if (race.distanceMAway != null)
        l.racesDistanceAway(formatDistanceForPref(race.distanceMAway!)),
    ];
    // The whole card opens the race; the action buttons below stay their own
    // targets because each claims its own tap. A screen reader hears the
    // name and facts as one button, and each action separately.
    return ListCard.row(
      margin: ListCard.listMargin,
      dense: true,
      onTap: onOpen,
      title: race.name,
      badge: provenanceShowsBadge(provenance)
          ? ProvenanceBadge(provenance: provenance)
          : null,
      subtitle: meta.join(' · '),
      subtitleMaxLines: 3,
      meta: race.isVerified
          ? null
          : Text(
              l.racesUnverified,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
      actions: [
        if (canTrainFor)
          OutlinedButton(
            onPressed: onTrainFor,
            child: Text(l.racesTrainForThis),
          ),
        if (race.entryUrl != null)
          OutlinedButton(
            onPressed: () => _launch(context, race.entryUrl!),
            child: Text(l.racesRegister),
          ),
        if (race.resultsUrl != null)
          OutlinedButton(
            onPressed: () => _launch(context, race.resultsUrl!),
            child: Text(l.racesViewResults),
          ),
        if (canImport)
          FilledButton(
            onPressed: onImport,
            child: Text(l.racesImportResult),
          ),
      ],
    );
  }

  Future<void> _launch(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    var ok = false;
    if (uri != null) {
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          ok = true;
        } else {
          debugPrint('RacesScreen: no handler available for $url');
        }
      } catch (e) {
        debugPrint('RacesScreen: launch failed for $url: $e');
      }
    } else {
      debugPrint('RacesScreen: could not parse URL: $url');
    }
    if (!ok && context.mounted) {
      showTopBanner(context, AppLocalizations.of(context).racesCouldNotOpenLink);
    }
  }
}

String _formatRaceDate(String iso) {
  // YYYY-MM-DD only — display the date part verbatim (locale-agnostic so the
  // calendar day never shifts across zones; mirrors the web card's formatDate).
  return iso.length >= 10 ? iso.substring(0, 10) : iso;
}

/// Manual-listing submit form (modal). Resolves true when a listing was saved.
Future<bool?> showRaceListingForm(BuildContext context, RaceService service) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _RaceListingForm(service: service),
  );
}

class _RaceListingForm extends StatefulWidget {
  final RaceService service;
  const _RaceListingForm({required this.service});

  @override
  State<_RaceListingForm> createState() => _RaceListingFormState();
}

class _RaceListingFormState extends State<_RaceListingForm> {
  final _name = TextEditingController();
  final _date = TextEditingController();
  final _distance = TextEditingController();
  final _location = TextEditingController();
  final _entryUrl = TextEditingController();
  final _resultsUrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _date.dispose();
    _distance.dispose();
    _location.dispose();
    _entryUrl.dispose();
    _resultsUrl.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _name.text.trim().isNotEmpty && _date.text.trim().isNotEmpty && !_saving;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() => _date.text =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final l = AppLocalizations.of(context);
    try {
      await widget.service.submitRaceListing(
        name: _name.text,
        raceDate: _date.text,
        distanceM: int.tryParse(_distance.text.trim()),
        locationLabel: _location.text,
        entryUrl: _entryUrl.text,
        resultsUrl: _resultsUrl.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showTopBanner(context, l.racesSubmitFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.racesEditorTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FieldColumn(children: [
              TextField(
                controller: _name,
                decoration: InputDecoration(labelText: l.racesFieldName),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                controller: _date,
                readOnly: true,
                onTap: _pickDate,
                decoration: InputDecoration(
                  labelText: l.racesFieldDate,
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
              ),
              TextField(
                controller: _distance,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l.racesFieldDistance),
              ),
              TextField(
                controller: _location,
                decoration: InputDecoration(labelText: l.racesFieldLocation),
              ),
              TextField(
                controller: _entryUrl,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(labelText: l.racesFieldEntryUrl, hintText: 'https://'),
              ),
              TextField(
                controller: _resultsUrl,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(labelText: l.racesFieldResultsUrl, hintText: 'https://'),
              ),
            ]),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: Text(l.racesCancel),
        ),
        FilledButton(onPressed: _canSave ? _save : null, child: Text(l.racesSave)),
      ],
    );
  }
}

/// Import a result onto a recorded run / new race run. Offers this listing's
/// own provider pull when that provider has a built leg and its key is
/// configured, and manual paste in every case. Resolves true when a result was
/// imported.
Future<bool?> showRaceImportSheet(
  BuildContext context, {
  required RaceService service,
  required RaceListingView race,
  String? matchRunId,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _RaceImportForm(
      service: service,
      race: race,
      matchRunId: matchRunId,
    ),
  );
}

class _RaceImportForm extends StatefulWidget {
  final RaceService service;
  final RaceListingView race;
  final String? matchRunId;

  const _RaceImportForm({
    required this.service,
    required this.race,
    this.matchRunId,
  });

  @override
  State<_RaceImportForm> createState() => _RaceImportFormState();
}

class _RaceImportFormState extends State<_RaceImportForm> {
  final _bib = TextEditingController();
  final _chip = TextEditingController();
  final _gun = TextEditingController();
  final _place = TextEditingController();
  bool _busy = false;

  /// Null for a listing whose provider has no import leg at all (ultrasignup,
  /// manual, raceresult) — manual paste still applies to every one of them.
  late final RaceImportProvider? _provider =
      raceImportProviderFor(widget.race.provider);

  /// Null until the probe answers. Guessing either way is wrong: offering an
  /// import that 503s, or withdrawing one that works. Nothing below is gated
  /// on it — paste is offered throughout.
  bool? _available;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  /// A probe is a network call (L4): a failure degrades this listing's
  /// provider to unavailable and never takes the sheet or the paste form down.
  Future<void> _probe() async {
    final spec = _provider;
    if (spec == null) return;
    var ok = false;
    try {
      ok = await widget.service.isProviderConfigured(spec.provider);
    } catch (e) {
      debugPrint('RacesScreen: ${spec.provider} probe failed: $e');
    }
    if (mounted) setState(() => _available = ok);
  }

  @override
  void dispose() {
    _bib.dispose();
    _chip.dispose();
    _gun.dispose();
    _place.dispose();
    super.dispose();
  }

  bool get _canPaste =>
      !_busy && (_chip.text.trim().isNotEmpty || _gun.text.trim().isNotEmpty);

  /// Whether this runner's pull is scoped by their bib. Every leg refuses
  /// without one client-side, mirroring the Edge Function's own pre-fetch gate
  /// (issue #360).
  bool get _scoped => _provider != null && _blank(_bib.text) != null;

  bool get _canProviderImport => !_busy && _available == true && _scoped;

  Future<void> _providerImport() async {
    final spec = _provider;
    if (spec == null || !_scoped) return;
    setState(() => _busy = true);
    final l = AppLocalizations.of(context);
    try {
      final outcome = await widget.service.importRaceResult(
        provider: spec.provider,
        listingId: widget.race.id,
        bib: _blank(_bib.text),
        matchRunId: widget.matchRunId,
      );
      if (!mounted) return;
      // A field read only as far as the cap still imports what it found, so a
      // truncated import used to close the sheet looking like a whole one.
      if (!outcome.complete) {
        showTopBanner(context, l.integrationsImportPartial(outcome.imported));
      }
      Navigator.of(context).pop(true);
    } on RaceResultsTruncated {
      if (!mounted) return;
      setState(() => _busy = false);
      showTopBanner(context, l.integrationsImportTruncated);
    } catch (e) {
      if (!mounted) return;
      // The service throws the catalogue's own const instance, so identity is
      // what tells "this provider is unconfigured" from any other failure —
      // and the probe that said otherwise is now known to be wrong.
      final unconfigured = identical(e, spec.unavailable);
      setState(() {
        _busy = false;
        if (unconfigured) _available = false;
      });
      showTopBanner(
        context,
        unconfigured
            ? (raceProviderLabels(l)[spec.provider]?.unavailable ??
                l.racesImportFailed)
            : l.racesImportFailed,
      );
    }
  }

  Future<void> _pasteImport() async {
    if (!_canPaste) return;
    setState(() => _busy = true);
    final l = AppLocalizations.of(context);
    try {
      await widget.service.importRaceResult(
        provider: 'paste',
        listingId: widget.race.id,
        matchRunId: widget.matchRunId,
        result: PastedRaceResult(
          bib: _blank(_bib.text),
          chipTime: _blank(_chip.text),
          gunTime: _blank(_gun.text),
          overallPlace: int.tryParse(_place.text.trim()),
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        showTopBanner(context, l.racesImportFailed);
      }
    }
  }

  String? _blank(String s) => s.trim().isEmpty ? null : s.trim();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.race.name),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_provider case final spec?) ...[
              if (_available == true) ...[
                Text(l.racesRunSignUpBibHint,
                    style: Theme.of(context).textTheme.bodySmall),
                FilledButton(
                  onPressed: _canProviderImport ? _providerImport : null,
                  child: Text(l.racesImportResult),
                ),
              ] else if (_available == false)
                Text(
                  raceProviderLabels(l)[spec.provider]?.unavailable ??
                      l.racesImportFailed,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
            const SizedBox(height: 8),
            Text(l.racesPasteResultHint, style: Theme.of(context).textTheme.bodySmall),
            FieldColumn(children: [
              TextField(
                controller: _bib,
                decoration: InputDecoration(labelText: l.racesBib),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                controller: _chip,
                decoration: InputDecoration(labelText: l.racesChipTime, hintText: '1:47:23'),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                controller: _gun,
                decoration: InputDecoration(labelText: l.racesGunTime, hintText: '1:48:01'),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                controller: _place,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l.racesOverallPlace),
              ),
            ]),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l.racesCancel),
        ),
        FilledButton(
          onPressed: _canPaste ? _pasteImport : null,
          child: Text(l.racesMatchConfirm),
        ),
      ],
    );
  }
}

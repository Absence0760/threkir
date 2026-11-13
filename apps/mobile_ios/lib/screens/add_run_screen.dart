import '../activity_type_labels.dart';
import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:ui_kit/ui_kit.dart' show EditorPage, EditorSave, SheetScaffold;
import 'package:uuid/uuid.dart';

import '../auth_error.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../local_route_store.dart';
import '../local_run_store.dart';
import '../manual_duration_input.dart';
import '../preferences.dart';
import '../route_file_import.dart';
import '../social_service.dart';
import '../typed_decimal.dart';
import '../widgets/confirm_discard.dart';
import '../widgets/top_banner.dart';
import 'route_builder_screen.dart';

/// Form for adding a run to history without recording it live.
///
/// The user provides date, duration, and distance; they can optionally pick
/// one of their saved routes to prefill the distance — or, with none saved,
/// build or import one from the empty route field. No GPS track is
/// captured — the resulting run has an empty `track` and `metadata` is
/// stamped with `manual_entry: true` so other surfaces can tell it apart
/// from a recorded one.
class AddRunScreen extends StatefulWidget {
  final LocalRunStore runStore;
  final LocalRouteStore routeStore;
  final Preferences preferences;

  /// Null when signed out: the route builder needs it, so the empty route
  /// field then offers only Import.
  final ApiClient? apiClient;
  final SocialService? social;
  final DateTime Function() now;

  /// Replaces pushing [RouteBuilderScreen], which needs a live map and
  /// backend, so a widget test can hand back the route a save would pop.
  @visibleForTesting
  final Future<Route?> Function(BuildContext context)? openRouteBuilder;

  const AddRunScreen({
    super.key,
    required this.runStore,
    required this.routeStore,
    required this.preferences,
    this.apiClient,
    this.social,
    this.now = DateTime.now,
    this.openRouteBuilder,
  });

  @override
  State<AddRunScreen> createState() => _AddRunScreenState();
}

class _AddRunScreenState extends State<AddRunScreen> {
  static const _metresPerMile = 1609.344;
  static const _uuid = Uuid();

  final _formKey = GlobalKey<FormState>();
  final _titleCtl = TextEditingController();
  final _notesCtl = TextEditingController();
  final _distanceCtl = TextEditingController();
  final _hoursCtl = TextEditingController();
  final _minutesCtl = TextEditingController();
  final _secondsCtl = TextEditingController();

  late DateTime _startedAt;
  late DateTime _initialStartedAt;
  ActivityType _activityType = ActivityType.run;
  Route? _selectedRoute;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = widget.now();
    _startedAt = DateTime(now.year, now.month, now.day, now.hour);
    _initialStartedAt = _startedAt;
  }

  bool get _isDirty =>
      _titleCtl.text.isNotEmpty ||
      _notesCtl.text.isNotEmpty ||
      _distanceCtl.text.isNotEmpty ||
      _hoursCtl.text.isNotEmpty ||
      _minutesCtl.text.isNotEmpty ||
      _secondsCtl.text.isNotEmpty ||
      _activityType != ActivityType.run ||
      _selectedRoute != null ||
      _startedAt != _initialStartedAt;

  @override
  void dispose() {
    _titleCtl.dispose();
    _notesCtl.dispose();
    _distanceCtl.dispose();
    _hoursCtl.dispose();
    _minutesCtl.dispose();
    _secondsCtl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startedAt,
      firstDate: DateTime(2000),
      lastDate: widget.now(),
    );
    if (picked == null) return;
    if (!mounted) return;
    setState(() {
      _startedAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _startedAt.hour,
        _startedAt.minute,
      );
    });
  }

  /// The date picker stops at today, but a time of day has no such bound,
  /// so a start later today than now has to be refused here — and again at
  /// save, because a date moved back to today keeps the earlier time.
  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startedAt),
    );
    if (picked == null) return;
    if (!mounted) return;
    final next = DateTime(
      _startedAt.year,
      _startedAt.month,
      _startedAt.day,
      picked.hour,
      picked.minute,
    );
    if (next.isAfter(widget.now())) {
      showTopBanner(context, AppLocalizations.of(context).addRunStartInFuture);
      return;
    }
    setState(() => _startedAt = next);
  }

  void _onRouteSelected(Route? route) {
    setState(() {
      _selectedRoute = route;
      if (route != null) {
        _distanceCtl.text = _formatDistanceForInput(route.distanceMetres);
        if (_titleCtl.text.trim().isEmpty) {
          _titleCtl.text = route.name;
        }
      }
    });
  }

  Future<void> _pickRoute(List<Route> routes, DistanceUnit unit) async {
    final picked = await Navigator.push<_RoutePick>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _RoutePickerPage(routes: routes, unit: unit),
      ),
    );
    if (picked == null) return;
    _onRouteSelected(picked.route);
  }

  Future<void> _addRoute() async {
    final l10n = AppLocalizations.of(context);
    final api = widget.apiClient;
    final source = await showModalBottomSheet<_NewRouteSource>(
      context: context,
      builder: (sheetContext) => SheetScaffold(
        padding: EdgeInsets.zero,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (api != null)
              ListTile(
                leading: const Icon(Icons.add_location_alt),
                title: Text(l10n.addRunBuildRoute),
                onTap: () => Navigator.pop(sheetContext, _NewRouteSource.build),
              ),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: Text(l10n.addRunImportRoute),
              onTap: () => Navigator.pop(sheetContext, _NewRouteSource.import),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    switch (source) {
      case _NewRouteSource.build:
        final created =
            await (widget.openRouteBuilder?.call(context) ??
                Navigator.of(context).push<Route>(
                  MaterialPageRoute(
                    builder: (_) => RouteBuilderScreen(
                      apiClient: api!,
                      routeStore: widget.routeStore,
                      social: widget.social,
                    ),
                  ),
                ));
        if (created != null && mounted) _onRouteSelected(created);
      case _NewRouteSource.import:
        final imported = await pickAndImportRouteFile(
          context,
          widget.routeStore,
        );
        if (!mounted) return;
        if (imported.length == 1) {
          _onRouteSelected(imported.first);
        } else {
          setState(() {});
        }
    }
  }

  String _formatDistanceForInput(double metres) {
    final unit = widget.preferences.unit;
    if (unit == DistanceUnit.mi) {
      return (metres / _metresPerMile).toStringAsFixed(2);
    }
    return (metres / 1000).toStringAsFixed(2);
  }

  double? _parseDistanceMetres(String raw) {
    final v = parseTypedDecimal(raw);
    if (v == null || v <= 0) return null;
    return widget.preferences.unit == DistanceUnit.mi
        ? v * _metresPerMile
        : v * 1000;
  }

  ManualDurationResult _duration() => validateManualDuration(
    _hoursCtl.text,
    _minutesCtl.text,
    _secondsCtl.text,
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final distance = _parseDistanceMetres(_distanceCtl.text);
    final seconds = _duration().seconds;
    if (distance == null || seconds == null) return;
    if (_startedAt.isAfter(widget.now())) {
      showTopBanner(context, AppLocalizations.of(context).addRunStartInFuture);
      return;
    }
    if (isImplausiblySlow(seconds, distance) &&
        !await confirmImplausiblySlowDuration(context)) {
      return;
    }
    if (!mounted) return;
    final duration = Duration(seconds: seconds);

    setState(() => _saving = true);

    final metadata = <String, dynamic>{
      MetadataKeys.activityType: _activityType.name,
      MetadataKeys.manualEntry: true,
    };
    final title = _titleCtl.text.trim();
    if (title.isNotEmpty) metadata[MetadataKeys.title] = title;
    final notes = _notesCtl.text.trim();
    if (notes.isNotEmpty) metadata[MetadataKeys.notes] = notes;

    final run = Run(
      id: _uuid.v4(),
      startedAt: _startedAt.toUtc(),
      duration: duration,
      distanceMetres: distance,
      source: RunSource.app,
      routeId: _selectedRoute?.id,
      metadata: metadata,
    );

    try {
      await widget.runStore.save(run);
    } catch (e) {
      debugPrint('add run save failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      showTopBanner(
        context,
        AppLocalizations.of(
          context,
        ).addRunSaveFailed(friendlyError(AppLocalizations.of(context), e)),
      );
      return;
    }

    if (!mounted) return;
    final added = AppLocalizations.of(context).addRunSaved;
    Navigator.pop(context);
    showTopBanner(context, added);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final unit = widget.preferences.unit;
    final routes = widget.routeStore.routes;

    // The fields sit in one Form above the page, and the page's single Save
    // is pinned under them (issue #1374: Save was in the app bar and again
    // at the foot of the list).
    final page = Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: EditorPage(
        title: l10n.addRunTitle,
        save: EditorSave(
          label: l10n.addRunSaveButton,
          busy: _saving,
          onPressed: _save,
        ),
        fields: [
          Text(l10n.addRunSectionWhen, style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today),
                  label: Text(
                    formatDateMed(
                      _startedAt,
                      localeToTag(Localizations.localeOf(context)),
                    ),
                  ),
                  onPressed: _pickDate,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.schedule),
                  label: Text(_formatTime(_startedAt)),
                  onPressed: _pickTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(l10n.addRunSectionActivity, style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ActivityType.values.map((a) {
              final selected = _activityType == a;
              return ChoiceChip(
                label: Text(activityTypeLabel(l10n, a)),
                avatar: Icon(a.icon, size: 18),
                selected: selected,
                onSelected: (_) => setState(() => _activityType = a),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Text(l10n.addRunSectionRoute, style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          if (routes.isNotEmpty) ...[
            InkWell(
              onTap: () => _pickRoute(routes, unit),
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: InputDecoration(
                  suffixIcon: _selectedRoute == null
                      ? const Icon(Icons.search)
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: l10n.addRunClearRoute,
                          onPressed: () => _onRouteSelected(null),
                        ),
                ),
                child: Text(
                  _selectedRoute == null
                      ? l10n.addRunSearchRoutes
                      : '${_selectedRoute!.name} • '
                            '${UnitFormat.distance(_selectedRoute!.distanceMetres, unit)}',
                  style: _selectedRoute == null
                      ? theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )
                      : theme.textTheme.bodyLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ] else ...[
            InkWell(
              key: const Key('add_run_add_route'),
              onTap: _addRoute,
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: const InputDecoration(suffixIcon: Icon(Icons.add)),
                child: Text(
                  l10n.addRunNoRoutes,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(l10n.addRunSectionDistance, style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Semantics(
            label: l10n.addRunSectionDistance,
            child: TextFormField(
              controller: _distanceCtl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: typedDecimalInputFormatters,
              decoration: InputDecoration(
                suffixText: UnitFormat.distanceLabel(unit),
              ),
              validator: (v) {
                if (_parseDistanceMetres(v ?? '') == null) {
                  return l10n.addRunDistanceInvalid;
                }
                return null;
              },
            ),
          ),
          const SizedBox(height: 20),
          Text(l10n.addRunSectionDuration, style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          FormField<Duration>(
            validator: (_) {
              final error = _duration().error;
              return error == null
                  ? null
                  : manualDurationErrorText(l10n, error);
            },
            builder: (state) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _durationField(
                          _hoursCtl,
                          'h',
                          state,
                          l10n.durationFieldHours,
                          hours: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _durationField(
                          _minutesCtl,
                          'm',
                          state,
                          l10n.durationFieldMinutes,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _durationField(
                          _secondsCtl,
                          's',
                          state,
                          l10n.durationFieldSeconds,
                        ),
                      ),
                    ],
                  ),
                  if (state.hasError)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 12),
                      child: Text(
                        state.errorText!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Text(l10n.addRunSectionTitle, style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          TextFormField(
            controller: _titleCtl,
            decoration: InputDecoration(hintText: l10n.addRunTitleHint),
          ),
          const SizedBox(height: 20),
          Text(l10n.addRunSectionNotes, style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          TextFormField(
            controller: _notesCtl,
            maxLines: 3,
            decoration: InputDecoration(hintText: l10n.addRunNotesHint),
          ),
        ],
      ),
    );
    return DiscardGuard(
      isDirty: () => _isDirty,
      isBusy: () => _saving,
      child: page,
    );
  }

  /// [suffix] is the visible 'h' / 'm' / 's' hint, which is decorative:
  /// `suffixText` is not folded into the field's accessible name, so all
  /// three boxes announced as a bare "text field" and a screen-reader user
  /// had no way to tell which one they were editing. [label] names it. The
  /// Distance field above already carries the equivalent Semantics wrapper.
  Widget _durationField(
    TextEditingController ctl,
    String suffix,
    FormFieldState<Duration> state,
    String label, {
    bool hours = false,
  }) {
    return Semantics(
      label: label,
      textField: true,
      child: TextField(
        controller: ctl,
        keyboardType: TextInputType.number,
        inputFormatters: durationBoxFormatters(hours: hours),
        onChanged: (_) => state.didChange(null),
        decoration: InputDecoration(suffixText: suffix),
      ),
    );
  }

  static String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// Result wrapper so `Navigator.pop(null)` (dismiss) is distinguishable
/// from "the user picked the No route option" — the latter pops a
/// [_RoutePick] whose `route` field is null.
enum _NewRouteSource { build, import }

class _RoutePick {
  final Route? route;
  const _RoutePick(this.route);
}

/// Full-screen searchable route picker. Pushed as a Material full-screen
/// dialog rather than a modal bottom sheet — sheets fight the keyboard
/// animation (viewInsets + FractionallySizedBox both reflow during open),
/// which is the "slow and glitchy" feel users notice. A pushed Scaffold
/// has the OS soft keyboard, AppBar, and list layout all playing by
/// their normal rules.
class _RoutePickerPage extends StatefulWidget {
  final List<Route> routes;
  final DistanceUnit unit;
  const _RoutePickerPage({required this.routes, required this.unit});

  @override
  State<_RoutePickerPage> createState() => _RoutePickerPageState();
}

class _RoutePickerPageState extends State<_RoutePickerPage> {
  final _searchCtl = TextEditingController();
  String _query = '';

  /// Lowercased route names, indexed parallel to `widget.routes`. Filled
  /// once in `initState` so typing a 6-character query doesn't re-allocate
  /// N lowercase strings per keystroke.
  late final List<String> _lowerNames;

  @override
  void initState() {
    super.initState();
    _lowerNames = widget.routes.map((r) => r.name.toLowerCase()).toList();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  List<Route> _filtered() {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.routes;
    final out = <Route>[];
    for (var i = 0; i < widget.routes.length; i++) {
      if (_lowerNames[i].contains(q)) out.add(widget.routes[i]);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final filtered = _filtered();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: l10n.addRunPickerCancel,
          onPressed: () => Navigator.pop(context),
        ),
        title: TextField(
          controller: _searchCtl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          style: theme.textTheme.titleMedium,
          decoration: InputDecoration(
            hintText: l10n.addRunPickerSearchHint,
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: l10n.addRunPickerClear,
              onPressed: () {
                _searchCtl.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: filtered.isEmpty
            ? Center(
                child: Text(
                  l10n.addRunPickerNoMatch(_query),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            : ListView.builder(
                // `+1` for the leading "No route" row.
                itemCount: filtered.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return ListTile(
                      leading: const Icon(Icons.block),
                      title: Text(l10n.addRunPickerNoRoute),
                      onTap: () =>
                          Navigator.pop(context, const _RoutePick(null)),
                    );
                  }
                  final route = filtered[index - 1];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(
                        Icons.route,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      route.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      UnitFormat.distance(route.distanceMetres, widget.unit),
                    ),
                    onTap: () => Navigator.pop(context, _RoutePick(route)),
                  );
                },
              ),
      ),
    );
  }
}

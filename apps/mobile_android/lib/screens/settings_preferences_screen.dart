import '../activity_type_labels.dart';
import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart'
    show ActivityType, DistanceUnit;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart'
    show
        AppInsets,
        AppSpace,
        ListRow,
        PageHeader,
        PushedPage,
        SettingsList,
        SettingsSection;

import '../adaptive_width.dart';
import '../dashboard_layout.dart';
import '../disclosure.dart';
import '../goals.dart';
import '../hr_prescription_gate.dart';
import '../hr_zones.dart'
    show kMaxHrBpmMax, kMaxHrBpmMin, kRestingHrBpmMax, kRestingHrBpmMin;
import '../l10n/gen/app_localizations.dart';
import '../messages_inbox.dart';
import '../l10n/locale_support.dart';
import '../l10n/number_format.dart';
import '../local_food_store.dart';
import '../local_gym_store.dart';
import '../local_run_store.dart';
import '../locale_defaults.dart';
import '../main.dart' show themeModeNotifier, localeNotifier;
import '../nearby_flag.dart';
import '../preferences.dart';
import '../preferences_page.dart';
import '../push_messaging_bridge.dart';
import '../settings_sync.dart';
import '../typed_decimal.dart';
import '../undo_queue.dart';
import '../weekly_goal.dart';
import '../widgets/async_switch_tile.dart';
import '../widgets/top_banner.dart';
import 'follow_requests_screen.dart';
import 'nearby_area_screen.dart';
import 'privacy_zones_screen.dart';

export '../preferences_page.dart';

/// One Preferences page ([PreferencesPage]): the rows of one subject, in
/// groups mirroring web's page of the same name. Every row applies at once.
class SettingsPreferencesScreen extends StatefulWidget {
  final PreferencesPage page;
  final ApiClient? apiClient;
  final Preferences preferences;
  final SettingsSyncService? settingsSync;
  final LocalGymStore? gymStore;
  final LocalFoodStore? foodStore;

  /// Sizes the history the "How much detail" hint derives its Automatic level
  /// from. Null counts no runs, so the hint names the goal's level alone.
  final LocalRunStore? runStore;

  /// The heart-rate prescription gate (decisions § 2092); null reads the
  /// deploy flag. A test passes it directly.
  final bool? hrPrescription;

  const SettingsPreferencesScreen({
    super.key,
    required this.page,
    this.apiClient,
    required this.preferences,
    required this.settingsSync,
    this.gymStore,
    this.foodStore,
    this.runStore,
    this.hrPrescription,
  });

  @override
  State<SettingsPreferencesScreen> createState() =>
      _SettingsPreferencesScreenState();
}

class _SettingsPreferencesScreenState extends State<SettingsPreferencesScreen> {
  bool _darkMode = themeModeNotifier.value == ThemeMode.dark;
  bool _localeBackfillDone = false;

  /// Read once per mount, not per build: the whole runners-nearby surface —
  /// the opt-in switch, the area row, and the `my_discoverable_area` read
  /// behind it — must be absent while the sign-off gate is off (decisions §270).
  final bool _nearbyGate = nearbyRunnersGate;

  /// "My heart rate is affected by medication" is Art 9: shown only under
  /// the deploy gate, and only switchable on with health-data consent, which
  /// the server re-checks (decisions § 2092).
  late final bool _hrPrescription = widget.hrPrescription ?? hrPrescriptionGate;
  String? _nearbyAreaLabel;

  /// user_profiles.profile_private, not a prefs key: RLS and the public views
  /// read it (decisions § 1967), so it is read and written on the profile row.
  /// Null until read; a failed read sets [_profilePrivateFailed] instead of
  /// guessing (issue #1374 FS-6).
  bool? _profilePrivate;
  bool _profilePrivateSaving = false;
  bool _profilePrivateFailed = false;

  /// user_settings.dm_read_receipts, a column because the server reads it when
  /// a message is marked read (migration 20271113000001). Null until read: the
  /// switch stays disabled rather than claim a state it has not seen.
  bool? _readReceipts;
  bool _readReceiptsSaving = false;
  bool _readReceiptsFailed = false;

  /// user_settings.dm_requests, a column because the INSERT policy reads it
  /// (migration 20271213121601). Null until read, like [_readReceipts].
  bool? _messageRequests;
  bool _messageRequestsSaving = false;
  bool _messageRequestsFailed = false;

  /// Date of birth lives in two stores under two rules (decisions § 718).
  /// [_profileDob] is the `user_profiles` age record behind the under-18
  /// discoverability floor — written whenever the runner picks a date — and
  /// is what the tile displays, because a withdrawal clears the Art 9
  /// mirror while the record stays on file. [_healthConsentAt] decides
  /// whether the mirror is written at all; null means no consent on record,
  /// which is also what an unreadable profile leaves behind, so the Art 9
  /// half fails closed.
  String? _profileDob;
  DateTime? _healthConsentAt;

  @override
  void initState() {
    super.initState();
    widget.preferences.addListener(_onChange);
    widget.settingsSync?.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeBackfillLocale());
    // Each read backs rows on one page only; a page that does not show them
    // does not ask.
    switch (widget.page) {
      case PreferencesPage.privacy:
        if (_nearbyGate) _loadNearbyAreaLabel();
        _loadProfilePrivate();
        _loadReadReceipts();
        _loadMessageRequests();
      case PreferencesPage.training:
        _loadHealthProfile();
      case PreferencesPage.display ||
            PreferencesPage.recording ||
            PreferencesPage.notifications:
        break;
    }
  }

  /// Best-effort (L4), for the same reason as [_loadNearbyAreaLabel]: a
  /// signed-out or offline read must leave the row showing the bag mirror
  /// rather than throw out of initState.
  Future<void> _loadHealthProfile() async {
    final api = widget.apiClient;
    if (api == null) return;
    try {
      final profile = await api.fetchMyProfile();
      if (!mounted) return;
      setState(() {
        _profileDob = profile?.dateOfBirth == null
            ? null
            : ApiClient.dateOnly(profile!.dateOfBirth!);
        _healthConsentAt = profile?.healthDataConsentAt;
      });
    } catch (e) {
      debugPrint('preferences health profile read failed: $e');
    }
  }

  @override
  void dispose() {
    widget.preferences.removeListener(_onChange);
    widget.settingsSync?.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
    _maybeBackfillLocale();
  }

  String _unitSubtitle() {
    final l10n = AppLocalizations.of(context);
    final base = widget.preferences.useMiles
        ? l10n.prefsUnitImperial
        : l10n.prefsUnitMetric;
    final sync = widget.settingsSync;
    if (sync == null || !sync.synced) return base;
    return l10n.prefsSyncedSuffix(base);
  }

  static String _splitIntervalLabel(int metres, DistanceUnit unit) {
    if (unit == DistanceUnit.mi) {
      final miles = metres / 1609.344;
      if ((miles - miles.roundToDouble()).abs() < 0.01) {
        return '${miles.round()} mi';
      }
      return '${formatFixed(miles, 1, activeLocaleTag)} mi';
    }
    if (metres >= 1000 && metres % 1000 == 0) {
      return '${metres ~/ 1000} km';
    }
    return '${metres}m';
  }

  Future<void> _editSplitInterval() async {
    final l10n = AppLocalizations.of(context);
    final prefs = widget.preferences;
    final options = prefs.useMiles
        ? <int>[0, 805, 1609, 3219, 8047]
        : <int>[0, 500, 1000, 2000, 5000];
    final labels = prefs.useMiles
        ? [l10n.prefsSplitIntervalDefault, '0.5 mi', '1 mi', '2 mi', '5 mi']
        : [l10n.prefsSplitIntervalDefault, '500m', '1 km', '2 km', '5 km'];

    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.prefsSplitInterval),
        children: [
          for (var i = 0; i < options.length; i++)
            RadioListTile<int>(
              title: Text(labels[i]),
              value: options[i],
              groupValue: prefs.splitIntervalMetres,
              onChanged: (v) => Navigator.pop(ctx, v),
            ),
        ],
      ),
    );
    if (result != null) {
      await prefs.setSplitIntervalMetres(result);
      await _roamPush(widget.settingsSync?.pushSplitInterval);
    }
  }

  Future<void> _editTargetPace() async {
    final l10n = AppLocalizations.of(context);
    final prefs = widget.preferences;
    final unit = prefs.unit;
    // The row reads this pace back in the runner's unit, so the editor has to
    // collect it in that unit too — otherwise a miles runner types 9:00 and
    // stores a 9:00/km target the alert then holds them to.
    final current = prefs.targetPaceSecPerKm > 0
        ? UnitFormat.paceSecPerUnit(prefs.targetPaceSecPerKm.toDouble(), unit)
            .round()
        : 0;
    final mCtl = TextEditingController(
      text: '${current > 0 ? current ~/ 60 : 5}',
    );
    final sCtl = TextEditingController(
      text: '${current > 0 ? current % 60 : 30}',
    );

    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.prefsTargetPace),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 60,
              child: TextField(
                controller: mCtl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.prefsLivePaceAlertMin,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              // The separator between two number fields, so it takes the step
              // an M3 `TextField` sizes its own input at rather than a step of
              // its own — a colon larger than the digits it separates.
              child: Text(':', style: Theme.of(context).textTheme.bodyLarge),
            ),
            SizedBox(
              width: 60,
              child: TextField(
                controller: sCtl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.prefsLivePaceAlertSec,
                  suffixText: UnitFormat.paceLabel(unit),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 0),
            child: Text(l10n.prefsClear),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(l10n.prefsCancel),
          ),
          FilledButton(
            onPressed: () {
              final m = int.tryParse(mCtl.text) ?? 0;
              final s = int.tryParse(sCtl.text) ?? 0;
              final perUnit = m * 60 + s;
              Navigator.pop(
                ctx,
                perUnit <= 0
                    ? 0
                    : UnitFormat.paceSecPerKm(perUnit.toDouble(), unit).round(),
              );
            },
            child: Text(l10n.prefsSave),
          ),
        ],
      ),
    );
    if (mounted) FocusScope.of(context).unfocus();
    if (result != null) await prefs.setTargetPaceSecPerKm(result);
  }

  Future<void> _editSplitPaceMode() async {
    final l10n = AppLocalizations.of(context);
    final picked = await _pickRadio<String>(
      title: l10n.prefsSplitPaceMode,
      options: const [
        SplitPaceMode.split,
        SplitPaceMode.average,
        SplitPaceMode.both,
      ],
      labels: [
        l10n.prefsSplitPaceModeSplit,
        l10n.prefsSplitPaceModeAverage,
        l10n.prefsSplitPaceModeBoth,
      ],
      current: widget.preferences.splitPaceMode,
    );
    if (picked == null) return;
    await widget.preferences.setSplitPaceMode(picked);
    await _putUniversal(SettingsKeys.voiceSplitPaceMode, picked);
  }

  static String _splitPaceModeLabel(AppLocalizations l10n, String raw) {
    switch (raw) {
      case SplitPaceMode.average:
        return l10n.prefsSplitPaceModeAverage;
      case SplitPaceMode.both:
        return l10n.prefsSplitPaceModeBoth;
      default:
        return l10n.prefsSplitPaceModeSplit;
    }
  }

  static String _toTitle(String raw) => raw
      .split('_')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');

  static String _paceFormatLabel(AppLocalizations l10n, String raw) {
    switch (raw) {
      case 'min_per_km':
        return l10n.prefsPaceFormatMinPerKm;
      case 'min_per_mi':
        return l10n.prefsPaceFormatMinPerMi;
      case 'kph':
        return l10n.prefsPaceFormatKph;
      case 'mph':
        return l10n.prefsPaceFormatMph;
      default:
        return _toTitle(raw);
    }
  }

  static String _mapStyleLabel(AppLocalizations l10n, String raw) {
    switch (raw) {
      case 'streets':
        return l10n.prefsMapStyleStreets;
      case 'satellite':
        return l10n.prefsMapStyleSatellite;
      case 'outdoors':
        return l10n.prefsMapStyleOutdoors;
      case 'dark':
        return l10n.prefsMapStyleDark;
      default:
        return _toTitle(raw);
    }
  }

  static String _weekStartLabel(AppLocalizations l10n, String raw) {
    switch (raw) {
      case 'monday':
        return l10n.prefsWeekStartMonday;
      case 'sunday':
        return l10n.prefsWeekStartSunday;
      default:
        return _toTitle(raw);
    }
  }

  static String _privacyLabel(AppLocalizations l10n, String raw) {
    switch (raw) {
      case 'public':
        return l10n.privacyPublicTitle;
      case 'followers':
        return l10n.privacyFollowersTitle;
      case 'private':
        return l10n.privacyPrivateTitle;
      default:
        return _toTitle(raw);
    }
  }

  static String _coachLabel(AppLocalizations l10n, String raw) {
    switch (raw) {
      case 'supportive':
        return l10n.prefsCoachSupportive;
      case 'drill_sergeant':
        return l10n.prefsCoachDrillSergeant;
      case 'analytical':
        return l10n.prefsCoachAnalytical;
      default:
        return _toTitle(raw);
    }
  }

  static String _emailNotifLabel(AppLocalizations l10n, String raw) {
    switch (raw) {
      case 'all':
        return l10n.prefsEmailNotifAll;
      case 'important':
        return l10n.prefsEmailNotifImportant;
      case 'off':
        return l10n.prefsEmailNotifOff;
      default:
        return _toTitle(raw);
    }
  }

  static String _pushNotifLabel(AppLocalizations l10n, String raw) {
    switch (raw) {
      case 'all':
        return l10n.prefsPushNotifAll;
      case 'important':
        return l10n.prefsPushNotifImportant;
      case 'off':
        return l10n.prefsPushNotifOff;
      default:
        return _toTitle(raw);
    }
  }

  String _hrZonesSummary() {
    final l10n = AppLocalizations.of(context);
    final raw = _bagValue<Map>(SettingsKeys.hrZones);
    if (raw == null) return l10n.prefsNotSet;
    final vals = ['z1', 'z2', 'z3', 'z4', 'z5']
        .map((k) => raw[k])
        .whereType<num>()
        .map((n) => n.round().toString())
        .toList();
    if (vals.isEmpty) return l10n.prefsNotSet;
    return l10n.prefsHrZonesSummary(vals.join(' · '));
  }

  String _weeklyGoalSummary() {
    final l10n = AppLocalizations.of(context);
    final unit = widget.preferences.unit;
    final display = weeklyGoalToInput(
      _bagValue<num>(SettingsKeys.weeklyMileageGoalMetres),
      unit,
    );
    if (display == null) return l10n.prefsNotSet;
    return l10n.prefsWeeklyGoalSummary(
      formatFixed(display, display == display.roundToDouble() ? 0 : 1,
          activeLocaleTag),
      unit.name,
    );
  }

  /// The bag-backed tiles light up as soon as the [SettingsSyncService]
  /// reports `synced`. With an on-disk cache in play (the default on
  /// production builds) this now becomes true on cache hit, not only
  /// after a successful server round-trip — so an airplane-mode
  /// signed-in user can still read + write every prefs key.
  bool get _bagReady => widget.settingsSync?.synced == true;

  T? _bagValue<T>(String key) =>
      widget.settingsSync?.service?.effective<T>(key);

  Future<void> _putUniversal(String key, dynamic value) async {
    try {
      await widget.settingsSync?.updateUniversal(<String, dynamic>{key: value});
    } catch (e) {
      // Best-effort (L4): updateUniversal already persisted the change to
      // the local cache and queued it for the next online drain before any
      // server push, so a rare cache/auth throw here must not surface as an
      // unhandled async error or revert the toggle.
      debugPrint('settings updateUniversal failed for $key: $e');
    }
    if (mounted) setState(() {});
  }

  /// Roam a pref that is ALREADY saved locally up to the settings bags.
  /// Best-effort (L4) for the same reason as [_putUniversal]: the local
  /// value is the live read path, so a signed-out / unloadable bag must
  /// disclose in the log rather than throw out of an `onChanged` handler.
  Future<void> _roamPush(Future<void> Function()? push) async {
    if (push == null) return;
    try {
      await push();
    } catch (e) {
      debugPrint('settings roam push failed: $e');
    }
  }

  Future<T?> _pickRadio<T>({
    required String title,
    required List<T> options,
    required List<String> labels,
    required T? current,
  }) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          for (var i = 0; i < options.length; i++)
            RadioListTile<T>(
              title: Text(labels[i]),
              value: options[i],
              groupValue: current,
              onChanged: (v) => Navigator.pop(ctx, v),
            ),
        ],
      ),
    );
  }

  Future<int?> _pickInt({
    required String title,
    required int? current,
    required String suffix,
    int minValue = 0,
    int maxValue = 1 << 30,
    bool allowClear = true,
  }) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(
      text: current == null ? '' : '$current',
    );
    // Popping null on a refusal made an out-of-range entry indistinguishable
    // from Cancel: the dialog closed, the caller returned, and a runner who
    // typed 300 was never told the range. Every numeric preference on this
    // screen shares the helper, so the refusal is stated here once and the
    // dialog stays open on it (decisions § 1410).
    String? rangeError;
    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(title),
          // semantics-children: names a field that shows no label or hint of its own
          content: Semantics(
            label: title,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                suffixText: suffix,
                errorText: rangeError,
              ),
              autofocus: true,
              onChanged: (_) {
                if (rangeError != null) {
                  setDialogState(() => rangeError = null);
                }
              },
            ),
          ),
          actions: [
            if (allowClear)
              TextButton(
                onPressed: () => Navigator.pop(ctx, -1),
                child: Text(l10n.prefsClear),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: Text(l10n.prefsCancel),
            ),
            FilledButton(
              onPressed: () {
                final v = int.tryParse(controller.text.trim());
                if (v == null || v < minValue || v > maxValue) {
                  setDialogState(() {
                    rangeError = l10n.prefsValueOutOfRange(minValue, maxValue);
                  });
                  return;
                }
                Navigator.pop(ctx, v);
              },
              child: Text(l10n.prefsSave),
            ),
          ],
        ),
      ),
    );
    if (mounted) FocusScope.of(context).unfocus();
    return result;
  }

  Future<double?> _pickDouble({
    required String title,
    required double? current,
    required String suffix,
    double minValue = 0,
    double maxValue = double.infinity,
    bool allowClear = true,
  }) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(
      text: current == null ? '' : '$current',
    );
    final result = await showDialog<double?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        // semantics-children: names a field that shows no label or hint of its own
        content: Semantics(
          label: title,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(suffixText: suffix),
            autofocus: true,
          ),
        ),
        actions: [
          if (allowClear)
            TextButton(
              onPressed: () => Navigator.pop(ctx, -1.0),
              child: Text(l10n.prefsClear),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(l10n.prefsCancel),
          ),
          FilledButton(
            onPressed: () {
              final v = parseTypedDecimal(controller.text);
              if (v == null || v < minValue || v > maxValue) {
                Navigator.pop(ctx, null);
              } else {
                Navigator.pop(ctx, v);
              }
            },
            child: Text(l10n.prefsSave),
          ),
        ],
      ),
    );
    if (mounted) FocusScope.of(context).unfocus();
    return result;
  }

  Future<void> _editDefaultActivityType() async {
    final l10n = AppLocalizations.of(context);
    final opts = [for (final a in ActivityType.values) a.name];
    final labels = [
      for (final a in ActivityType.values) activityTypeLabel(l10n, a),
    ];
    final picked = await _pickRadio<String>(
      title: l10n.prefsDefaultActivity,
      options: opts,
      labels: labels,
      current: _bagValue<String>(SettingsKeys.defaultActivityType) ?? 'run',
    );
    if (picked != null) {
      await _putUniversal(SettingsKeys.defaultActivityType, picked);
      await widget.preferences.setDefaultActivityType(picked);
    }
  }

  Future<void> _editWeightUnit() async {
    final l10n = AppLocalizations.of(context);
    const opts = ['kg', 'lbs'];
    final labels = [l10n.prefsWeightUnitKg, l10n.prefsWeightUnitLbs];
    final picked = await _pickRadio<String>(
      title: l10n.prefsWeightUnit,
      options: opts,
      labels: labels,
      current: _bagValue<String>(SettingsKeys.weightUnit) ?? 'kg',
    );
    if (picked != null) {
      await _putUniversal(SettingsKeys.weightUnit, picked);
      await widget.preferences.setWeightUnit(WeightFormat.unitFromWire(picked));
    }
  }

  String _weightUnitLabel(AppLocalizations l10n, String raw) =>
      raw == 'lbs' ? l10n.prefsWeightUnitLbs : l10n.prefsWeightUnitKg;

  Future<void> _editLanguage() async {
    final t = AppLocalizations.of(context);
    // '' is the "follow device locale" sentinel; the rest are derived from
    // supportedLocales rather than listed, because a hand-written list is how
    // European Portuguese came to ship in the binary while being unpickable.
    final tags = ['', ...supportedLocales.map(localeToTag)];
    final labels = [
      t.prefsLanguageSystem,
      ...supportedLocales.map((l) => localeLabels[localeToTag(l)]!),
    ];
    final current = widget.preferences.locale == null
        ? ''
        : localeToTag(widget.preferences.locale!);
    final picked = await _pickRadio<String>(
      title: t.prefsLanguage,
      options: tags,
      labels: labels,
      current: current,
    );
    if (picked == null) return;
    final next = picked.isEmpty ? null : localeFromTag(picked);
    await widget.preferences.setLocale(next);
    localeNotifier.value = next;
    // Mirror the applied locale into the universal bag so the worker can
    // localize email (decisions §120). For "follow device" (empty pick),
    // resolve the concrete tag the device negotiates to. The per-device UI
    // locale above stays the source of truth for what THIS device shows.
    final tag = picked.isEmpty
        ? resolveActiveLocaleTag(
            null,
            WidgetsBinding.instance.platformDispatcher.locales,
          )
        : picked;
    await _putUniversal(SettingsKeys.locale, tag);
    if (mounted) setState(() {});
  }

  // One-shot backfill: when the bag has no `locale` yet, persist the active
  // locale so a user who never opens the language picker still gets email in
  // their language (decisions §120). Gated on a real settings service (the
  // server-backed bag) so it no-ops in widget tests with a stubbed sync.
  void _maybeBackfillLocale() {
    if (_localeBackfillDone) return;
    final sync = widget.settingsSync;
    final svc = sync?.service;
    if (sync == null || !sync.synced || svc == null)
      return; // not ready; retry on next change
    _localeBackfillDone = true;
    if (svc.effective<String>(SettingsKeys.locale) != null)
      return; // already set
    final tag = resolveActiveLocaleTag(
      widget.preferences.locale,
      WidgetsBinding.instance.platformDispatcher.locales,
    );
    _putUniversal(SettingsKeys.locale, tag);
  }

  Future<void> _editMapStyle() async {
    final l10n = AppLocalizations.of(context);
    final labels = [
      l10n.prefsMapStyleStreets,
      l10n.prefsMapStyleSatellite,
      l10n.prefsMapStyleOutdoors,
      l10n.prefsMapStyleDark,
    ];
    final picked = await _pickRadio<String>(
      title: l10n.prefsMapStyle,
      options: kMapStyles,
      labels: labels,
      current: _mapStylePref,
    );
    if (picked == null) return;
    // Local mirror first: it is what every map surface reads through
    // `activeMapStyle`, and it must survive a cold start offline.
    await widget.preferences.setMapStyle(picked);
    await _putUniversal(SettingsKeys.mapStyle, picked);
  }

  String get _mapStylePref => normaliseMapStyle(
    _bagValue<String>(SettingsKeys.mapStyle) ?? widget.preferences.mapStyle,
  );

  Future<void> _editPaceFormat() async {
    final l10n = AppLocalizations.of(context);
    const opts = ['min_per_km', 'min_per_mi', 'kph', 'mph'];
    final labels = [
      l10n.prefsPaceFormatMinPerKm,
      l10n.prefsPaceFormatMinPerMi,
      l10n.prefsPaceFormatKph,
      l10n.prefsPaceFormatMph,
    ];
    final picked = await _pickRadio<String>(
      title: l10n.prefsPaceFormat,
      options: opts,
      labels: labels,
      current: _bagValue<String>(SettingsKeys.unitsPaceFormat) ?? 'min_per_km',
    );
    if (picked != null) {
      await _putUniversal(SettingsKeys.unitsPaceFormat, picked);
    }
  }

  Future<void> _editPrivacyDefault() async {
    final l10n = AppLocalizations.of(context);
    const opts = ['public', 'followers', 'private'];
    final labels = [
      l10n.privacyPublicTitle,
      l10n.privacyFollowersTitle,
      l10n.privacyPrivateTitle,
    ];
    final picked = await _pickRadio<String>(
      title: l10n.prefsDefaultRunVisibility,
      options: opts,
      labels: labels,
      current: _bagValue<String>(SettingsKeys.privacyDefault) ?? 'private',
    );
    if (picked != null) {
      await _putUniversal(SettingsKeys.privacyDefault, picked);
      await widget.preferences.setPrivacyDefault(picked);
    }
  }

  Future<void> _editCoachPersonality() async {
    final l10n = AppLocalizations.of(context);
    const opts = ['supportive', 'drill_sergeant', 'analytical'];
    final labels = [
      l10n.prefsCoachSupportive,
      l10n.prefsCoachDrillSergeant,
      l10n.prefsCoachAnalytical,
    ];
    final picked = await _pickRadio<String>(
      title: l10n.prefsCoachPersonality,
      options: opts,
      labels: labels,
      current: _bagValue<String>(SettingsKeys.coachPersonality) ?? 'supportive',
    );
    if (picked != null) {
      await _putUniversal(SettingsKeys.coachPersonality, picked);
    }
  }

  Future<void> _editEmailNotifications() async {
    final l10n = AppLocalizations.of(context);
    const opts = ['important', 'all', 'off'];
    final labels = [
      l10n.prefsEmailNotifImportant,
      l10n.prefsEmailNotifAll,
      l10n.prefsEmailNotifOff,
    ];
    final picked = await _pickRadio<String>(
      title: l10n.prefsEmailNotifications,
      options: opts,
      labels: labels,
      current:
          _bagValue<String>(SettingsKeys.emailNotifications) ?? 'important',
    );
    if (picked != null) {
      await _putUniversal(SettingsKeys.emailNotifications, picked);
    }
  }

  Future<void> _editPushNotifications() async {
    final l10n = AppLocalizations.of(context);
    const opts = ['important', 'all', 'off'];
    final labels = [
      l10n.prefsPushNotifImportant,
      l10n.prefsPushNotifAll,
      l10n.prefsPushNotifOff,
    ];
    final picked = await _pickRadio<String>(
      title: l10n.prefsPushNotifications,
      options: opts,
      labels: labels,
      current: _bagValue<String>(SettingsKeys.pushNotifications) ?? 'important',
    );
    if (picked != null) {
      await _putUniversal(SettingsKeys.pushNotifications, picked);
      // Mirror the channel choice down to this device's native-push opt-in
      // flag so the worker's per-device fan-out filter matches. 'off' disables
      // this device; 'all'/'important' re-enable it (the worker still applies
      // the category gate). Best-effort — no-ops when push isn't configured.
      await PushMessagingBridge.instance?.setNotificationsEnabled(
        picked != 'off',
      );
    }
  }

  Future<void> _editEmailWeeklyDigest() async {
    // Opt-IN consent stored as 'on'|'off' (default 'off'); deliberately a
    // separate key from the transactional email_notifications.
    final on = _bagValue<String>(SettingsKeys.emailWeeklyDigest) == 'on';
    await _putUniversal(SettingsKeys.emailWeeklyDigest, on ? 'off' : 'on');
    if (!on) await _clearUnsubscribeBlock();
  }

  Future<void> _toggleEmailNewDeviceAlerts() async {
    // Opt-OUT security alert stored as 'on'|'off' (default 'on'); only the
    // literal 'off' mutes it, matching the worker's read.
    final on = _bagValue<String>(SettingsKeys.emailNewDeviceAlerts) != 'off';
    await _putUniversal(SettingsKeys.emailNewDeviceAlerts, on ? 'off' : 'on');
  }

  /// Where the AI Coach sits in the Messages inbox (decisions § 2227).
  Future<void> _editCoachInMessages() async {
    final l10n = AppLocalizations.of(context);
    final picked = await _pickRadio<CoachInboxPlacement>(
      title: l10n.prefsCoachInMessages,
      options: CoachInboxPlacement.values,
      labels: [
        for (final p in CoachInboxPlacement.values) _coachPlacementLabel(l10n, p),
      ],
      current: parseCoachInboxPlacement(
          _bagValue<Object>(SettingsKeys.messagesCoachRow)),
    );
    if (picked != null) {
      await _putUniversal(SettingsKeys.messagesCoachRow, picked.name);
    }
  }

  static String _coachPlacementLabel(
          AppLocalizations l10n, CoachInboxPlacement p) =>
      switch (p) {
        CoachInboxPlacement.pinned => l10n.prefsCoachInMessagesPinned,
        CoachInboxPlacement.listed => l10n.prefsCoachInMessagesListed,
        CoachInboxPlacement.hidden => l10n.prefsCoachInMessagesHidden,
      };

  Future<void> _toggleNotifyWorkoutReminder() async {
    // Opt-OUT, stored as 'on'|'off' (default 'on'); only the literal 'off'
    // mutes it, matching the scheduler's and the worker's read.
    final on = _bagValue<String>(SettingsKeys.notifyWorkoutReminder) != 'off';
    await _putUniversal(SettingsKeys.notifyWorkoutReminder, on ? 'off' : 'on');
  }

  Future<void> _toggleNotifyRaceStartingSoon() async {
    final on = _bagValue<String>(SettingsKeys.notifyRaceStartingSoon) != 'off';
    await _putUniversal(SettingsKeys.notifyRaceStartingSoon, on ? 'off' : 'on');
  }

  Future<void> _toggleNotifyParkCourseMonth() async {
    final on = _bagValue<String>(SettingsKeys.notifyParkCourseMonth) != 'off';
    await _putUniversal(SettingsKeys.notifyParkCourseMonth, on ? 'off' : 'on');
  }

  Future<void> _editEmailLifecycleDrip() async {
    // Opt-IN consent stored as 'on'|'off' (default 'off'); a separate key from
    // both email_notifications and email_weekly_digest — one engagement stream
    // opt-in is never consent to the other.
    final on = _bagValue<String>(SettingsKeys.emailLifecycleDrip) == 'on';
    await _putUniversal(SettingsKeys.emailLifecycleDrip, on ? 'off' : 'on');
    if (!on) await _clearUnsubscribeBlock();
  }

  /// Re-opting into an engagement stream must also lift any prior one-click
  /// unsubscribe address block, or the send stays silently hard-blocked while
  /// the toggle reads 'on' (issue #392). The suppression row is address-keyed
  /// so it covers every stream — either toggle turning on clears it. Mirrors
  /// web `/settings/preferences` `setEngagementPref`.
  Future<void> _clearUnsubscribeBlock() async {
    final client = widget.apiClient;
    if (client == null) return;
    try {
      await client.clearMyUnsubscribeSuppression();
    } catch (e) {
      // The pref itself is already saved; a failure here leaves the block in
      // place, so tell the user rather than letting the stream stay dead.
      debugPrint('clear_my_unsubscribe_suppression failed: $e');
      if (mounted) {
        showTopBanner(
          context,
          AppLocalizations.of(context).prefsEmailReOptInFailed,
        );
      }
    }
  }

  // New users have no stored week_start_day — fall back to the locale
  // default (Sunday-first regions like the US/CA, Monday elsewhere)
  // instead of hard-coding Monday. Mirrors web /settings/preferences'
  // `defaultWeekStartForLocale(navigator.language)` fallback. The raw
  // device locale (not Localizations.localeOf) because the app's
  // resolved locale drops the region subtag the derivation needs.
  String get _weekStartLocaleDefault => defaultWeekStartForLocale(
    WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag(),
  );

  Future<void> _editWeekStartDay() async {
    final l10n = AppLocalizations.of(context);
    const opts = ['monday', 'sunday'];
    final labels = [l10n.prefsWeekStartMonday, l10n.prefsWeekStartSunday];
    final picked = await _pickRadio<String>(
      title: l10n.prefsWeekStart,
      options: opts,
      labels: labels,
      current:
          _bagValue<String>(SettingsKeys.weekStartDay) ??
          _weekStartLocaleDefault,
    );
    if (picked != null) {
      await _putUniversal(SettingsKeys.weekStartDay, picked);
    }
  }

  /// `auto` is the absence of the key, not a fourth level: picking it writes
  /// null, which deletes the key and hands the level back to the derivation.
  /// Web twin: `/settings/display`'s `disclosureChoice`.
  String get _disclosureChoice {
    final stored = _bagValue<Object>(disclosureLevelKey);
    return isDisclosureLevel(stored) ? stored as String : 'auto';
  }

  /// What Automatic resolves to today, named in the hint.
  String get _derivedDisclosure {
    final goal = _bagValue<Object>(SettingsKeys.primaryGoal);
    return disclosureLevel(
      goal is String ? goal : null,
      widget.runStore?.summaries.length ?? 0,
    );
  }

  String _disclosureLabel(AppLocalizations l10n, String choice) =>
      switch (choice) {
        'simple' => l10n.prefsDisclosureSimple,
        'standard' => l10n.prefsDisclosureStandard,
        'full' => l10n.prefsDisclosureFull,
        _ => l10n.prefsDisclosureAuto,
      };

  Future<void> _editDisclosureLevel() async {
    final l10n = AppLocalizations.of(context);
    final current = _disclosureChoice;
    const options = ['auto', ...disclosureLevels];
    final picked = await _pickRadio<String>(
      title: l10n.prefsDisclosureLevel,
      options: options,
      labels: [for (final o in options) _disclosureLabel(l10n, o)],
      current: current,
    );
    if (picked == null || picked == current) return;
    await _putUniversal(disclosureLevelKey, picked == 'auto' ? null : picked);
  }

  String _progressCardLabel(AppLocalizations l10n, String id) => switch (id) {
        'volume' => l10n.dashboardTrendGroupVolume,
        'fitness' => l10n.dashboardTrendGroupFitness,
        'performance' => l10n.dashboardTrendGroupPerformance,
        'effort' => l10n.dashboardTrendGroupEffort,
        _ => l10n.dashboardTrendGroupRecent,
      };

  /// Where a trend group hidden from the Progress page comes back, and where
  /// one can be hidden too (`dashboard_hidden_cards`, decisions § 2386; the
  /// groups moved from Home to Progress in § 2492). Web twin: the Home
  /// section of `/settings/display`, since web keeps one dashboard.
  Future<void> _editProgressCards() async {
    final l10n = AppLocalizations.of(context);
    var hidden =
        parseHiddenCards(_bagValue<Object>(SettingsKeys.dashboardHiddenCards));
    await showDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setDialogState) => AlertDialog(
          title: Text(l10n.prefsProgressCards),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.prefsProgressCardsHint),
                for (final id in hideableDashboardCards)
                  CheckboxListTile(
                    key: Key('prefsProgressCard-$id'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(_progressCardLabel(l10n, id)),
                    value: !hidden.contains(id),
                    onChanged: (shown) {
                      hidden = withCardHidden(hidden, id, shown != true);
                      setDialogState(() {});
                      _putUniversal(SettingsKeys.dashboardHiddenCards, hidden);
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(),
              child: Text(MaterialLocalizations.of(dialog).closeButtonLabel),
            ),
          ],
        ),
      ),
    );
  }

  /// The bag is the source of truth once it has loaded; before that, the
  /// locally-mirrored value keeps the row honest offline.
  int get _undoWindowS {
    final raw = _bagValue<num>(SettingsKeys.undoWindowS);
    return raw == null
        ? widget.preferences.undoWindowS
        : undoWindowSFromPref(raw);
  }

  String _undoWindowLabel(AppLocalizations l10n, int seconds) {
    switch (seconds) {
      case 0:
        return l10n.prefsUndoWindowManual;
      case 30:
        return l10n.prefsUndoWindow30s;
      default:
        return l10n.prefsUndoWindow8s;
    }
  }

  Future<void> _editUndoWindow() async {
    final l10n = AppLocalizations.of(context);
    final picked = await _pickRadio<int>(
      title: l10n.prefsUndoWindow,
      options: kUndoWindowChoicesS,
      labels: [for (final s in kUndoWindowChoicesS) _undoWindowLabel(l10n, s)],
      current: _undoWindowS,
    );
    if (picked == null) return;
    // Mirror locally first so the offer honours the new choice even while the
    // bag write is still queued, and so it survives a cold start offline.
    await widget.preferences.setUndoWindowS(picked);
    await _putUniversal(SettingsKeys.undoWindowS, picked);
  }

  Future<void> _editStravaAutoShare() async {
    final current = _bagValue<bool>(SettingsKeys.stravaAutoShare) ?? false;
    await _putUniversal(SettingsKeys.stravaAutoShare, !current);
  }

  Future<void> _editDiscoverableInSearch() async {
    final current = _bagValue<bool>(SettingsKeys.discoverableInSearch) ?? true;
    await _putUniversal(SettingsKeys.discoverableInSearch, !current);
  }

  Future<void> _editDiscoverableNearby() async {
    final current = _bagValue<bool>(SettingsKeys.discoverableNearby) ?? false;
    await _putUniversal(SettingsKeys.discoverableNearby, !current);
  }

  /// Best-effort (L4): the label is a nicety on a row that still navigates, so
  /// a failed read discloses in the log and shows "no area set" rather than
  /// throwing out of initState.
  Future<void> _loadNearbyAreaLabel() async {
    final api = widget.apiClient;
    if (api == null) return;
    try {
      final label = await api.fetchMyDiscoverableArea();
      if (!mounted) return;
      setState(() => _nearbyAreaLabel = label);
    } catch (e) {
      debugPrint('discoverable area label read failed: $e');
    }
  }

  /// A failed read shows a retry row, not the switch: OFF over a private
  /// account would tell its owner their activity is public.
  Future<void> _loadProfilePrivate() async {
    final api = widget.apiClient;
    if (api == null) return;
    if (_profilePrivateFailed) setState(() => _profilePrivateFailed = false);
    try {
      final value = await api.fetchMyProfilePrivate();
      if (!mounted) return;
      setState(() => _profilePrivate = value);
    } catch (e) {
      debugPrint('profile privacy read failed: $e');
      if (mounted) setState(() => _profilePrivateFailed = true);
    }
  }

  /// A refused write must not read as saved — the switch is a promise about
  /// who sees the runner's activity — so it rolls back on failure.
  Future<void> _editProfilePrivate(bool next) async {
    final api = widget.apiClient;
    if (api == null || _profilePrivateSaving) return;
    setState(() {
      _profilePrivate = next;
      _profilePrivateSaving = true;
    });
    try {
      await api.setProfilePrivate(next);
    } catch (e) {
      debugPrint('profile privacy write failed: $e');
      if (!mounted) return;
      setState(() => _profilePrivate = !next);
      showTopBanner(context, AppLocalizations.of(context).prefsPrivateProfileFailed);
    } finally {
      if (mounted) setState(() => _profilePrivateSaving = false);
    }
  }

  Future<void> _loadReadReceipts() async {
    final api = widget.apiClient;
    if (api == null) return;
    if (_readReceiptsFailed) setState(() => _readReceiptsFailed = false);
    try {
      final value = await api.fetchMyDmReadReceipts();
      if (!mounted) return;
      setState(() => _readReceipts = value);
    } catch (e) {
      debugPrint('read receipts read failed: $e');
      if (mounted) setState(() => _readReceiptsFailed = true);
    }
  }

  /// Rolls back on a refused write, so the switch never claims a privacy
  /// choice the server did not take.
  Future<void> _editReadReceipts(bool next) async {
    final api = widget.apiClient;
    if (api == null || _readReceiptsSaving) return;
    setState(() {
      _readReceipts = next;
      _readReceiptsSaving = true;
    });
    try {
      await api.setDmReadReceipts(next);
    } catch (e) {
      debugPrint('read receipts write failed: $e');
      if (!mounted) return;
      setState(() => _readReceipts = !next);
      showTopBanner(context, AppLocalizations.of(context).prefsReadReceiptsFailed);
    } finally {
      if (mounted) setState(() => _readReceiptsSaving = false);
    }
  }

  Future<void> _loadMessageRequests() async {
    final api = widget.apiClient;
    if (api == null) return;
    if (_messageRequestsFailed) setState(() => _messageRequestsFailed = false);
    try {
      final value = await api.fetchMyDmRequests();
      if (!mounted) return;
      setState(() => _messageRequests = value);
    } catch (e) {
      debugPrint('message requests read failed: $e');
      if (mounted) setState(() => _messageRequestsFailed = true);
    }
  }

  /// Rolls back on a refused write, as [_editReadReceipts] does.
  Future<void> _editMessageRequests(bool next) async {
    final api = widget.apiClient;
    if (api == null || _messageRequestsSaving) return;
    setState(() {
      _messageRequests = next;
      _messageRequestsSaving = true;
    });
    try {
      await api.setDmRequests(next);
    } catch (e) {
      debugPrint('message requests write failed: $e');
      if (!mounted) return;
      setState(() => _messageRequests = !next);
      showTopBanner(
          context, AppLocalizations.of(context).prefsMessageRequestsFailed);
    } finally {
      if (mounted) setState(() => _messageRequestsSaving = false);
    }
  }

  Future<void> _openFollowRequests() async {
    final api = widget.apiClient;
    if (api == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => FollowRequestsScreen(api: api)),
    );
  }

  Future<void> _openNearbyArea() async {
    final api = widget.apiClient;
    if (api == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => NearbyAreaScreen(api: api)),
    );
    await _loadNearbyAreaLabel();
  }

  Future<void> _toggleHrMedicationAffected() async {
    final current = _bagValue<bool>(SettingsKeys.hrMedicationAffected) ?? false;
    await _putUniversal(SettingsKeys.hrMedicationAffected, !current);
  }

  List<Widget> _hrMedicationTiles(AppLocalizations l10n) {
    final on = _bagValue<bool>(SettingsKeys.hrMedicationAffected) ?? false;
    final consented = _healthConsentAt != null;
    return [
      ListRow.toggle(
        key: const Key('prefsHrMedicationAffected'),
        title: l10n.prefsHrMedicationAffected,
        subtitle: consented
            ? l10n.prefsHrMedicationAffectedHint
            : l10n.prefsHrMedicationNeedsConsent,
        value: on,
        onChanged: _bagReady && (consented || on)
            ? (_) => _toggleHrMedicationAffected()
            : null,
      ),
      if (on && _bagValue<num>(SettingsKeys.maxHrBpm) == null)
        ListRow.nav(
          key: const Key('prefsHrMedicationMaxPrompt'),
          icon: Icons.info_outline,
          title: l10n.prefsHrMedicationSetMaxHr,
          enabled: _bagReady,
          onTap: _editMaxHr,
        ),
    ];
  }

  Future<void> _editExcludeGymFromReadiness() async {
    final current =
        _bagValue<bool>(SettingsKeys.excludeGymFromReadiness) ?? false;
    await _putUniversal(SettingsKeys.excludeGymFromReadiness, !current);
  }

  Future<void> _editDateOfBirth() async {
    final raw = _dateOfBirthDisplay;
    final current = raw != null ? DateTime.tryParse(raw) : null;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime(now.year - 30, now.month, now.day),
      firstDate: DateTime(now.year - 120),
      lastDate: now,
      initialDatePickerMode: DatePickerMode.year,
      helpText: AppLocalizations.of(context).prefsDateOfBirth,
    );
    if (picked == null) return;
    final iso = ApiClient.dateOnly(picked);
    // The age record first and unconditionally: the under-18
    // discoverability floor keys off this column, so a runner who has not
    // granted Art 9 consent must still be able to record a birth date
    // (decisions § 718). Best-effort like every other row on this screen —
    // a failed write must not throw out of an onTap handler.
    final api = widget.apiClient;
    if (api != null) {
      try {
        await api.setMyDateOfBirth(picked);
        if (mounted) setState(() => _profileDob = iso);
      } catch (e) {
        debugPrint('date of birth age-record write failed: $e');
      }
    }
    // The bag mirror is the Art 9 health-use copy the coach + HR-max reads
    // consume. Fail closed: no consent on record — including a profile read
    // that never landed — writes nothing, and clears anything a previous
    // consent left behind.
    await _putUniversal(
      SettingsKeys.dateOfBirth,
      _healthConsentAt == null ? null : iso,
    );
  }

  /// What the row shows: the age record when it is known, the Art 9 mirror
  /// otherwise. Reading the mirror alone would blank the row for a runner
  /// who withdrew consent while their birth date is still on file.
  String? get _dateOfBirthDisplay =>
      _profileDob ?? _bagValue<String>(SettingsKeys.dateOfBirth);

  Future<void> _editRestingHr() async {
    final picked = await _pickInt(
      title: AppLocalizations.of(context).prefsRestingHr,
      current: _bagValue<num>(SettingsKeys.restingHrBpm)?.round(),
      suffix: 'bpm',
      // The named bound, not a third spelling of it (decisions § 1245, § 1409).
      minValue: kRestingHrBpmMin,
      maxValue: kRestingHrBpmMax,
    );
    if (picked == null) return;
    await _putUniversal(
      SettingsKeys.restingHrBpm,
      picked == -1 ? null : picked,
    );
  }

  Future<void> _editMaxHr() async {
    final picked = await _pickInt(
      title: AppLocalizations.of(context).prefsMaxHr,
      current: _bagValue<num>(SettingsKeys.maxHrBpm)?.round(),
      suffix: 'bpm',
      // The bound the zone readers apply, not a second copy of it: three
      // separate spellings of this range are what let the Wear OS rail use a
      // value the other two ignored (decisions § 1245, § 1407).
      minValue: kMaxHrBpmMin,
      maxValue: kMaxHrBpmMax,
    );
    if (picked == null) return;
    await _putUniversal(SettingsKeys.maxHrBpm, picked == -1 ? null : picked);
  }

  Future<void> _editCarbsPerHour() async {
    final picked = await _pickInt(
      title: AppLocalizations.of(context).prefsCarbsPerHour,
      current:
          (_bagValue<num>(SettingsKeys.carbsPerHour) ??
                  widget.preferences.carbsPerHourG)
              .round(),
      suffix: 'g/h',
      minValue: 0,
      maxValue: 200,
    );
    if (picked == null) return;
    final value = picked == -1 ? null : picked;
    await widget.preferences.setCarbsPerHourG(value?.toDouble());
    await _putUniversal(SettingsKeys.carbsPerHour, value);
  }

  Future<void> _editFluidPerHour() async {
    final picked = await _pickInt(
      title: AppLocalizations.of(context).prefsFluidPerHour,
      current:
          (_bagValue<num>(SettingsKeys.fluidPerHour) ??
                  widget.preferences.fluidPerHourMl)
              .round(),
      suffix: 'ml/h',
      minValue: 0,
      maxValue: 3000,
    );
    if (picked == null) return;
    final value = picked == -1 ? null : picked;
    await widget.preferences.setFluidPerHourMl(value?.toDouble());
    await _putUniversal(SettingsKeys.fluidPerHour, value);
  }

  Future<void> _editHrZones() async {
    final l10n = AppLocalizations.of(context);
    final current = _bagValue<Map>(SettingsKeys.hrZones);
    int? z(String k) {
      final v = current?[k];
      return v is num ? v.round() : null;
    }

    final controllers = <String, TextEditingController>{
      for (final k in const ['z1', 'z2', 'z3', 'z4', 'z5'])
        k: TextEditingController(text: z(k)?.toString() ?? ''),
    };
    final result = await showDialog<Map<String, int>?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.prefsHrZonesDialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in controllers.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: entry.value,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: entry.key.toUpperCase(),
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final ok =
                  await showDialog<bool>(
                    context: ctx,
                    builder: (confirmCtx) => AlertDialog(
                      title: Text(l10n.prefsHrZonesClearTitle),
                      content: Text(l10n.prefsHrZonesClearBody),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(confirmCtx, false),
                          child: Text(l10n.prefsCancel),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(confirmCtx, true),
                          style: TextButton.styleFrom(
                            foregroundColor: Theme.of(
                              confirmCtx,
                            ).colorScheme.error,
                          ),
                          child: Text(l10n.prefsHrZonesClearConfirm),
                        ),
                      ],
                    ),
                  ) ??
                  false;
              if (ok && ctx.mounted) Navigator.pop(ctx, <String, int>{});
            },
            child: Text(l10n.prefsClear),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(l10n.prefsCancel),
          ),
          FilledButton(
            onPressed: () {
              final out = <String, int>{};
              for (final entry in controllers.entries) {
                final v = int.tryParse(entry.value.text.trim());
                if (v != null && v > 0) out[entry.key] = v;
              }
              Navigator.pop(ctx, out);
            },
            child: Text(l10n.prefsSave),
          ),
        ],
      ),
    );
    if (mounted) FocusScope.of(context).unfocus();
    if (result == null) return;
    await _putUniversal(SettingsKeys.hrZones, result.isEmpty ? null : result);
  }

  Future<void> _editWeeklyGoal() async {
    final stored = _bagValue<num>(SettingsKeys.weeklyMileageGoalMetres);
    final unit = widget.preferences.unit;
    final picked = await _pickDouble(
      title: AppLocalizations.of(context).prefsWeeklyGoal,
      current: weeklyGoalToInput(stored, unit),
      suffix: unit.name,
      minValue: kWeeklyGoalMin,
      maxValue: kWeeklyGoalMax,
    );
    if (picked == null) return;
    if (picked == -1.0) {
      await _putUniversal(SettingsKeys.weeklyMileageGoalMetres, null);
      final existing = widget.preferences.goals.firstWhere(
        (g) => g.period == GoalPeriod.week && g.distanceMetres != null,
        orElse: () => const RunGoal(id: '', period: GoalPeriod.week),
      );
      if (existing.id.isNotEmpty) {
        await widget.preferences.removeGoal(existing.id);
      }
    } else {
      final metres = weeklyGoalFromInput(picked, unit, stored)!;
      await _putUniversal(SettingsKeys.weeklyMileageGoalMetres, metres);
      final existing = widget.preferences.goals.firstWhere(
        (g) => g.period == GoalPeriod.week && g.distanceMetres != null,
        orElse: () => const RunGoal(id: '', period: GoalPeriod.week),
      );
      await widget.preferences.upsertGoal(
        RunGoal(
          id: existing.id.isEmpty ? newGoalId() : existing.id,
          period: GoalPeriod.week,
          distanceMetres: metres.toDouble(),
          title: existing.title,
          timeSeconds: existing.timeSeconds,
          avgPaceSecPerKm: existing.avgPaceSecPerKm,
          runCount: existing.runCount,
        ),
      );
    }
  }

  void _showCueInfo(String title, String body) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );
  }

  Widget _cueSwitch(
    String title,
    String subtitle,
    String cueId,
    String infoBody,
  ) {
    final prefs = widget.preferences;
    return ListRow.toggle(
      info: _info(title, infoBody),
      title: title,
      subtitle: subtitle,
      value: prefs.voiceCueEnabled(cueId),
      onChanged: (v) async {
        await prefs.setVoiceCueEnabled(cueId, v);
        await _roamPush(widget.settingsSync?.pushVoiceCueTypes);
      },
    );
  }

  Widget _info(String title, String body) => IconButton(
        icon: const Icon(Icons.info_outline),
        tooltip: AppLocalizations.of(context).prefsCueInfoTooltip,
        onPressed: () => _showCueInfo(title, body),
      );

  /// Units & display: the language, theme and units everything is drawn in,
  /// and how much the pages show. Web: `/settings/display`.
  List<SettingsSection> _displaySections(AppLocalizations l10n) {
    final prefs = widget.preferences;
    return [
      SettingsSection(
        label: l10n.prefsGroupLanguageTheme,
        rows: [
          ListRow.value(
            title: l10n.prefsLanguage,
            value: prefs.locale == null
                ? l10n.prefsLanguageSystem
                : localeLabels[localeToTag(prefs.locale!)] ?? '—',
            onTap: _editLanguage,
          ),
          ListRow.toggle(
            title: l10n.prefsDarkMode,
            value: _darkMode,
            onChanged: (v) {
              final mode = v ? ThemeMode.dark : ThemeMode.light;
              setState(() => _darkMode = v);
              themeModeNotifier.value = mode;
              prefs.setThemeMode(mode);
            },
          ),
        ],
      ),
      SettingsSection(
        label: l10n.prefsGroupUnits,
        rows: [
          ListRow.toggle(
            title: l10n.prefsUseMiles,
            subtitle: _unitSubtitle(),
            value: prefs.useMiles,
            onChanged: (v) async {
              await prefs.setUseMiles(v);
              await _roamPush(widget.settingsSync?.pushPreferredUnit);
              if (mounted) setState(() {});
            },
          ),
          ListRow.value(
            title: l10n.prefsPaceFormat,
            value: _paceFormatLabel(
              l10n,
              _bagValue<String>(SettingsKeys.unitsPaceFormat) ?? 'min_per_km',
            ),
            enabled: _bagReady,
            onTap: _editPaceFormat,
          ),
          ListRow.value(
            title: l10n.prefsWeightUnit,
            value: _weightUnitLabel(
              l10n,
              _bagValue<String>(SettingsKeys.weightUnit) ?? 'kg',
            ),
            enabled: _bagReady,
            onTap: _editWeightUnit,
          ),
          ListRow.value(
            title: l10n.prefsWeekStart,
            value: _weekStartLabel(
              l10n,
              _bagValue<String>(SettingsKeys.weekStartDay) ??
                  _weekStartLocaleDefault,
            ),
            enabled: _bagReady,
            onTap: _editWeekStartDay,
          ),
        ],
      ),
      SettingsSection(
        label: l10n.prefsGroupMapsPages,
        rows: [
          ListRow.value(
            key: const Key('prefsDisclosureLevel'),
            title: l10n.prefsDisclosureLevel,
            value: _disclosureLabel(l10n, _disclosureChoice),
            hint: l10n.prefsDisclosureHint(
              _disclosureLabel(l10n, _derivedDisclosure),
            ),
            enabled: _bagReady,
            onTap: _editDisclosureLevel,
          ),
          ListRow.nav(
            key: const Key('prefsProgressCards'),
            title: l10n.prefsProgressCards,
            subtitle: l10n.prefsProgressCardsHint,
            enabled: _bagReady,
            onTap: _editProgressCards,
          ),
          ListRow.value(
            title: l10n.prefsMapStyle,
            value: _mapStyleLabel(l10n, _mapStylePref),
            enabled: _bagReady,
            onTap: _editMapStyle,
          ),
          ListRow.value(
            title: l10n.prefsUndoWindow,
            value: _undoWindowLabel(l10n, _undoWindowS),
            enabled: _bagReady,
            onTap: _editUndoWindow,
          ),
          ListRow.toggle(
            title: l10n.prefsShowCalories,
            subtitle: l10n.prefsShowCaloriesHint,
            value: _bagValue<bool>(SettingsKeys.showCalories) ?? true,
            onChanged: _bagReady
                ? (v) => _putUniversal(SettingsKeys.showCalories, v)
                : null,
          ),
          ListRow.toggle(
            key: const Key('prefsShowMascot'),
            title: l10n.prefsShowMascot,
            subtitle: l10n.prefsShowMascotHint,
            value: _bagValue<bool>(SettingsKeys.showMascot) != false,
            onChanged: _bagReady
                ? (v) => _putUniversal(SettingsKeys.showMascot, v)
                : null,
          ),
        ],
      ),
      SettingsSection(
        label: l10n.prefsSectionMessages,
        rows: [
          ListRow.value(
            key: const Key('prefsCoachInMessages'),
            title: l10n.prefsCoachInMessages,
            value: _coachPlacementLabel(
              l10n,
              parseCoachInboxPlacement(
                _bagValue<Object>(SettingsKeys.messagesCoachRow),
              ),
            ),
            enabled: _bagReady,
            onTap: _editCoachInMessages,
          ),
        ],
      ),
      // Showing the resolved state takes the stores (unset means "shown once
      // there is data"), so a mount without them leaves the section out
      // rather than render a switch that may be wrong.
      if (widget.gymStore case final gym?)
        if (widget.foodStore case final food?)
          SettingsSection(
            label: l10n.prefsSectionModalities,
            rows: [
              ListRow.toggle(
                title: l10n.prefsShowGym,
                subtitle: l10n.prefsShowGymSubtitle,
                value: prefs.gymShown(hasData: gym.workouts.isNotEmpty),
                onChanged: (v) async {
                  await prefs.setShowGym(v);
                  await _roamPush(widget.settingsSync?.pushModalityVisibility);
                },
              ),
              ListRow.toggle(
                title: l10n.prefsShowNutrition,
                subtitle: l10n.prefsShowNutritionSubtitle,
                value: prefs.nutritionShown(hasData: food.rows.isNotEmpty),
                onChanged: (v) async {
                  await prefs.setShowNutrition(v);
                  await _roamPush(widget.settingsSync?.pushModalityVisibility);
                },
              ),
            ],
          ),
    ];
  }

  /// Recording & voice: what a recording starts as, how the phone behaves
  /// while it runs, and what it says out loud. Web: `/settings/recording`.
  List<SettingsSection> _recordingSections(
    AppLocalizations l10n, {
    required bool runPrimaryForced,
  }) {
    final prefs = widget.preferences;
    return [
      SettingsSection(
        label: l10n.prefsSectionActivityRecording,
        rows: [
          ListRow.value(
            title: l10n.prefsDefaultActivity,
            value: activityTypeLabelFor(
              l10n,
              _bagValue<String>(SettingsKeys.defaultActivityType),
            ),
            enabled: _bagReady,
            onTap: _editDefaultActivityType,
          ),
          // multi_modal.md § "Protect the core runner": a pure runner can
          // keep the centre Log button as a one-tap run start (long-press
          // still opens the full capture sheet).
          ListRow.toggle(
            key: const Key('prefsKeepRunPrimary'),
            title: l10n.prefsKeepRunPrimary,
            subtitle: runPrimaryForced
                ? l10n.prefsKeepRunPrimaryForcedSubtitle
                : l10n.prefsKeepRunPrimarySubtitle,
            value: runPrimaryForced || prefs.keepRunPrimary,
            onChanged: runPrimaryForced ? null : prefs.setKeepRunPrimary,
          ),
          ListRow.toggle(
            title: l10n.prefsKeepScreenOn,
            subtitle: l10n.prefsKeepScreenOnSubtitle,
            value: prefs.keepScreenOn,
            onChanged: (v) async {
              await prefs.setKeepScreenOn(v);
              await _roamPush(widget.settingsSync?.pushKeepScreenOn);
            },
          ),
          ListRow.toggle(
            title: l10n.prefsDimScreenWhileRecording,
            subtitle: l10n.prefsDimScreenWhileRecordingSubtitle,
            value: prefs.dimScreenWhileRecording,
            onChanged: prefs.keepScreenOn
                ? (v) async {
                    await prefs.setDimScreenWhileRecording(v);
                    await _roamPush(
                        widget.settingsSync?.pushDimScreenWhileRecording);
                  }
                : null,
          ),
          ListRow.toggle(
            title: l10n.prefsAdvancedGps,
            subtitle: l10n.prefsAdvancedGpsSubtitle,
            value: prefs.advancedGps,
            onChanged: prefs.setAdvancedGps,
          ),
          ListRow.toggle(
            title: l10n.prefsShowRawTrack,
            subtitle: l10n.prefsShowRawTrackSubtitle,
            value: prefs.showRawTrack,
            onChanged: prefs.setShowRawTrack,
          ),
        ],
      ),
      SettingsSection(
        label: l10n.prefsGroupVoiceFeedback,
        rows: [
          ListRow.toggle(
            title: l10n.prefsAudioCues,
            subtitle: l10n.prefsAudioCuesSubtitle,
            value: prefs.audioCues,
            onChanged: (v) async {
              await prefs.setAudioCues(v);
              await _roamPush(widget.settingsSync?.pushAudioCues);
            },
          ),
          ListRow.toggle(
            title: l10n.phoneSurfaceVibrationCues,
            subtitle: l10n.phoneSurfaceVibrationCuesSubtitle,
            value: prefs.hapticFeedback,
            onChanged: (v) async {
              await prefs.setHapticFeedback(v);
              await _roamPush(widget.settingsSync?.pushHapticFeedback);
            },
          ),
          if (prefs.audioCues)
            ListRow.toggle(
              title: l10n.prefsMinimalVoiceCues,
              subtitle: l10n.prefsMinimalVoiceCuesSubtitle,
              value: prefs.voiceFeedbackVerbosity == 'minimal',
              onChanged: (v) async {
                final value = v ? 'minimal' : 'full';
                await prefs.setVoiceFeedbackVerbosity(value);
                await _putUniversal(
                  SettingsKeys.voiceFeedbackVerbosity,
                  value,
                );
              },
            ),
          if (prefs.audioCues)
            ListRow.toggle(
              title: l10n.prefTurnByTurnCues,
              subtitle: l10n.prefTurnByTurnCuesSubtitle,
              value: prefs.turnByTurnCues,
              onChanged: (v) async {
                await prefs.setTurnByTurnCues(v);
              },
            ),
          ListRow.value(
            title: l10n.prefsSplitInterval,
            value: prefs.splitIntervalMetres > 0
                ? _splitIntervalLabel(prefs.splitIntervalMetres, prefs.unit)
                : l10n.prefsSplitIntervalDefaultSubtitle(
                    _splitIntervalLabel(
                      ActivityType.run
                          .splitIntervalMetresFor(prefs.unit)
                          .round(),
                      prefs.unit,
                    ),
                    _splitIntervalLabel(
                      ActivityType.cycle
                          .splitIntervalMetresFor(prefs.unit)
                          .round(),
                      prefs.unit,
                    ),
                  ),
            onTap: _editSplitInterval,
          ),
          ListRow.value(
            title: l10n.prefsTargetPace,
            value: prefs.targetPaceSecPerKm > 0
                ? l10n.prefsLivePaceAlertOn(
                    UnitFormat.pace(
                      prefs.targetPaceSecPerKm.toDouble(),
                      prefs.unit,
                    ),
                    UnitFormat.paceLabel(prefs.unit),
                  )
                : l10n.prefsLivePaceAlertOff,
            info: _info(l10n.prefsTargetPace, l10n.prefsTargetPaceInfo),
            onTap: _editTargetPace,
          ),
        ],
      ),
      if (prefs.audioCues)
        SettingsSection(
          label: l10n.prefsVoiceCueTypesLabel,
          rows: [
            _cueSwitch(
              l10n.prefsCueSplits,
              l10n.prefsCueSplitsSubtitle,
              VoiceCue.splits,
              l10n.prefsCueSplitsInfo,
            ),
            _cueSwitch(
              l10n.prefsCueStartFinish,
              l10n.prefsCueStartFinishSubtitle,
              VoiceCue.startFinish,
              l10n.prefsCueStartFinishInfo,
            ),
            _cueSwitch(
              l10n.prefsCueOffRoute,
              l10n.prefsCueOffRouteSubtitle,
              VoiceCue.offRoute,
              l10n.prefsCueOffRouteInfo,
            ),
            _cueSwitch(
              l10n.prefsCuePaceAlerts,
              l10n.prefsCuePaceAlertsSubtitle,
              VoiceCue.paceAlerts,
              l10n.prefsCuePaceAlertsInfo,
            ),
            _cueSwitch(
              l10n.prefsCueWorkoutSteps,
              l10n.prefsCueWorkoutStepsSubtitle,
              VoiceCue.workoutSteps,
              l10n.prefsCueWorkoutStepsInfo,
            ),
            _cueSwitch(
              l10n.prefsCueCutoffCatchUp,
              l10n.prefsCueCutoffCatchUpSubtitle,
              VoiceCue.cutoffCatchUp,
              l10n.prefsCueCutoffCatchUpInfo,
            ),
            _cueSwitch(
              l10n.prefsCueMarkerTargets,
              l10n.prefsCueMarkerTargetsSubtitle,
              VoiceCue.markerTargets,
              l10n.prefsCueMarkerTargetsInfo,
            ),
            _cueSwitch(
              l10n.prefsCuePhaseTransitions,
              l10n.prefsCuePhaseTransitionsSubtitle,
              VoiceCue.phaseTransitions,
              l10n.prefsCuePhaseTransitionsInfo,
            ),
            _cueSwitch(
              l10n.prefsCueGuidedRun,
              l10n.prefsCueGuidedRunSubtitle,
              VoiceCue.guidedRun,
              l10n.prefsCueGuidedRunInfo,
            ),
            ListRow.value(
              title: l10n.prefsSplitPaceMode,
              value: _splitPaceModeLabel(l10n, prefs.splitPaceMode),
              info: _info(l10n.prefsSplitPaceMode, l10n.prefsSplitPaceModeInfo),
              onTap: _editSplitPaceMode,
            ),
          ],
        ),
    ];
  }

  /// Training: the goal, the heart-rate numbers zones and load are derived
  /// from, plan recovery, race fuelling and the coach's tone. Web:
  /// `/settings/training`.
  List<SettingsSection> _trainingSections(
    AppLocalizations l10n, {
    required bool hideGymReadiness,
  }) {
    return [
      SettingsSection(
        label: l10n.prefsGroupWeeklyGoal,
        rows: [
          ListRow.value(
            title: l10n.prefsWeeklyGoal,
            value: _weeklyGoalSummary(),
            enabled: _bagReady,
            onTap: _editWeeklyGoal,
          ),
        ],
      ),
      SettingsSection(
        label: l10n.prefsGroupHeartRate,
        rows: [
          ListRow.value(
            title: l10n.prefsDateOfBirth,
            value: _dateOfBirthDisplay ?? l10n.prefsNotSet,
            enabled: _bagReady,
            onTap: _editDateOfBirth,
          ),
          ListRow.value(
            title: l10n.prefsRestingHr,
            value: _bagValue<num>(SettingsKeys.restingHrBpm) != null
                ? l10n.prefsHrBpm(
                    _bagValue<num>(SettingsKeys.restingHrBpm)!.round(),
                  )
                : l10n.prefsNotSet,
            enabled: _bagReady,
            onTap: _editRestingHr,
          ),
          ListRow.value(
            title: l10n.prefsMaxHr,
            value: _bagValue<num>(SettingsKeys.maxHrBpm) != null
                ? l10n.prefsHrBpm(
                    _bagValue<num>(SettingsKeys.maxHrBpm)!.round(),
                  )
                : l10n.prefsMaxHrNotSet,
            enabled: _bagReady,
            onTap: _editMaxHr,
          ),
          if (_hrPrescription) ..._hrMedicationTiles(l10n),
          ListRow.value(
            title: l10n.prefsHrZones,
            value: _hrZonesSummary(),
            enabled: _bagReady,
            onTap: _editHrZones,
          ),
          if (!hideGymReadiness)
            ListRow.toggle(
              key: const Key('prefsExcludeGymFromReadiness'),
              title: l10n.prefsExcludeGymFromReadiness,
              subtitle: l10n.prefsExcludeGymFromReadinessHint,
              value:
                  _bagValue<bool>(SettingsKeys.excludeGymFromReadiness) ??
                      false,
              onChanged:
                  _bagReady ? (_) => _editExcludeGymFromReadiness() : null,
            ),
        ],
      ),
      SettingsSection(
        label: l10n.prefsGroupPlans,
        rows: [
          ListRow.toggle(
            key: const Key('prefsExtraRecovery'),
            title: l10n.prefsExtraRecovery,
            subtitle: l10n.prefsExtraRecoveryHint,
            value: _bagValue<Object>(SettingsKeys.extraRecovery) == true,
            onChanged: _bagReady
                ? (on) => _putUniversal(SettingsKeys.extraRecovery, on)
                : null,
          ),
        ],
      ),
      SettingsSection(
        label: l10n.prefsSectionFueling,
        rows: [
          ListRow.value(
            title: l10n.prefsCarbsPerHour,
            value: l10n.prefsCarbsPerHourValue(
              (_bagValue<num>(SettingsKeys.carbsPerHour) ??
                      widget.preferences.carbsPerHourG)
                  .round(),
            ),
            enabled: _bagReady,
            onTap: _editCarbsPerHour,
          ),
          ListRow.value(
            title: l10n.prefsFluidPerHour,
            value: l10n.prefsFluidPerHourValue(
              (_bagValue<num>(SettingsKeys.fluidPerHour) ??
                      widget.preferences.fluidPerHourMl)
                  .round(),
            ),
            enabled: _bagReady,
            onTap: _editFluidPerHour,
          ),
        ],
      ),
      SettingsSection(
        label: l10n.prefsSectionAiCoach,
        rows: [
          ListRow.value(
            title: l10n.prefsCoachPersonality,
            value: _coachLabel(
              l10n,
              _bagValue<String>(SettingsKeys.coachPersonality) ?? 'supportive',
            ),
            enabled: _bagReady,
            onTap: _editCoachPersonality,
          ),
        ],
      ),
    ];
  }

  /// Privacy & sharing: who sees your runs, whether you can be found, who
  /// can message you, the zones clipped from every track, and error
  /// reports. Web: `/settings/privacy`.
  List<SettingsSection> _privacySections(AppLocalizations l10n) {
    final prefs = widget.preferences;
    final api = widget.apiClient;
    return [
      SettingsSection(
        label: l10n.prefsGroupYourRuns,
        rows: [
          ListRow.value(
            title: l10n.prefsDefaultRunPrivacy,
            value: _privacyLabel(
              l10n,
              _bagValue<String>(SettingsKeys.privacyDefault) ?? 'followers',
            ),
            enabled: _bagReady,
            onTap: _editPrivacyDefault,
          ),
          ListRow.toggle(
            title: l10n.prefsStravaAutoShare,
            subtitle: l10n.prefsStravaAutoShareSubtitle,
            value: _bagValue<bool>(SettingsKeys.stravaAutoShare) ?? false,
            onChanged: _bagReady ? (_) => _editStravaAutoShare() : null,
          ),
        ],
      ),
      SettingsSection(
        label: l10n.prefsGroupBeingFound,
        rows: [
          if (api != null) ...[
            AsyncSwitchTile(
              switchKey: const ValueKey('prefs-private-profile'),
              title: l10n.prefsPrivateProfile,
              subtitle: l10n.prefsPrivateProfileSubtitle,
              value: _profilePrivate,
              failed: _profilePrivateFailed,
              saving: _profilePrivateSaving,
              onChanged: _editProfilePrivate,
              onRetry: _loadProfilePrivate,
            ),
            if (_profilePrivate == true)
              ListRow.nav(
                key: const ValueKey('prefs-follow-requests'),
                title: l10n.followRequestsTitle,
                onTap: _openFollowRequests,
              ),
          ],
          ListRow.toggle(
            title: l10n.prefsDiscoverable,
            subtitle: l10n.prefsDiscoverableSubtitle,
            value: _bagValue<bool>(SettingsKeys.discoverableInSearch) ?? true,
            onChanged: _bagReady ? (_) => _editDiscoverableInSearch() : null,
          ),
          // Opt-in coarse-location discovery (issue #466). Both rows are
          // absent — not merely disabled — while the default-off deploy gate
          // holds, and the area row needs an ApiClient to reach its definer
          // RPCs at all.
          if (_nearbyGate) ...[
            ListRow.toggle(
              title: l10n.prefsDiscoverableNearby,
              subtitle: l10n.prefsDiscoverableNearbySubtitle,
              value: _bagValue<bool>(SettingsKeys.discoverableNearby) ?? false,
              onChanged: _bagReady ? (_) => _editDiscoverableNearby() : null,
            ),
            if (api != null)
              ListRow.value(
                title: l10n.nearbyAreaTitle,
                value: _nearbyAreaLabel == null
                    ? l10n.nearbyAreaNone
                    : l10n.nearbyAreaCurrent(_nearbyAreaLabel!),
                onTap: _openNearbyArea,
              ),
          ],
        ],
      ),
      if (api != null)
        SettingsSection(
          label: l10n.prefsSectionMessages,
          rows: [
            AsyncSwitchTile(
              switchKey: const Key('prefsReadReceipts'),
              title: l10n.prefsReadReceipts,
              subtitle: l10n.prefsReadReceiptsHint,
              value: _readReceipts,
              failed: _readReceiptsFailed,
              saving: _readReceiptsSaving,
              onChanged: _editReadReceipts,
              onRetry: _loadReadReceipts,
            ),
            AsyncSwitchTile(
              switchKey: const Key('prefsMessageRequests'),
              title: l10n.prefsMessageRequests,
              subtitle: l10n.prefsMessageRequestsHint,
              value: _messageRequests,
              failed: _messageRequestsFailed,
              saving: _messageRequestsSaving,
              onChanged: _editMessageRequests,
              onRetry: _loadMessageRequests,
            ),
          ],
        ),
      // Mirrors web's privacy-zones section (#666 I11): a zone is a sharing
      // preference, not an account setting.
      if (widget.settingsSync case final sync?)
        SettingsSection(
          label: l10n.privacyZonesTitle,
          rows: [
            ListRow.nav(
              key: const ValueKey('prefs-privacy-zones'),
              title: l10n.privacyZonesTitle,
              subtitle: l10n.privacyZonesSubtitle,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => PrivacyZonesScreen(settingsSync: sync),
                ),
              ),
            ),
          ],
        ),
      SettingsSection(
        label: l10n.prefsGroupTelemetry,
        rows: [
          ListRow.toggle(
            key: const ValueKey('prefs-error-reports'),
            title: l10n.settingsAccountSendErrorReports,
            subtitle: l10n.settingsAccountSendErrorReportsSubtitle,
            value: !prefs.sentryOptOut,
            onChanged: (enabled) async {
              await prefs.setSentryOptOut(!enabled);
              if (!mounted) return;
              showTopBanner(
                context,
                enabled
                    ? l10n.settingsAccountErrorReportingEnabled
                    : l10n.settingsAccountErrorReportingDisabled,
              );
            },
          ),
        ],
      ),
    ];
  }

  /// Notifications: which emails and pushes arrive. Web:
  /// `/settings/notifications`.
  List<SettingsSection> _notificationSections(AppLocalizations l10n) => [
        SettingsSection(
          label: l10n.prefsGroupEmailPush,
          rows: [
            ListRow.value(
              title: l10n.prefsEmailNotifications,
              value: _emailNotifLabel(
                l10n,
                _bagValue<String>(SettingsKeys.emailNotifications) ??
                    'important',
              ),
              enabled: _bagReady,
              onTap: _editEmailNotifications,
            ),
            ListRow.value(
              title: l10n.prefsPushNotifications,
              value: _pushNotifLabel(
                l10n,
                _bagValue<String>(SettingsKeys.pushNotifications) ??
                    'important',
              ),
              enabled: _bagReady,
              onTap: _editPushNotifications,
            ),
            ListRow.toggle(
              title: l10n.prefsNotifyWorkoutReminder,
              subtitle: l10n.prefsNotifyWorkoutReminderHint,
              value:
                  _bagValue<String>(SettingsKeys.notifyWorkoutReminder) !=
                      'off',
              onChanged:
                  _bagReady ? (_) => _toggleNotifyWorkoutReminder() : null,
            ),
            ListRow.toggle(
              key: const ValueKey('prefs-notify-race-starting-soon'),
              title: l10n.prefsNotifyRaceStartingSoon,
              subtitle: l10n.prefsNotifyRaceStartingSoonHint,
              value:
                  _bagValue<String>(SettingsKeys.notifyRaceStartingSoon) !=
                      'off',
              onChanged:
                  _bagReady ? (_) => _toggleNotifyRaceStartingSoon() : null,
            ),
            ListRow.toggle(
              key: const ValueKey('prefs-notify-park-course-month'),
              title: l10n.prefsNotifyParkCourseMonth,
              subtitle: l10n.prefsNotifyParkCourseMonthHint,
              value:
                  _bagValue<String>(SettingsKeys.notifyParkCourseMonth) !=
                      'off',
              onChanged:
                  _bagReady ? (_) => _toggleNotifyParkCourseMonth() : null,
            ),
            ListRow.toggle(
              title: l10n.prefsEmailNewDeviceAlerts,
              subtitle: l10n.prefsEmailNewDeviceAlertsHint,
              value:
                  _bagValue<String>(SettingsKeys.emailNewDeviceAlerts) != 'off',
              onChanged:
                  _bagReady ? (_) => _toggleEmailNewDeviceAlerts() : null,
            ),
          ],
        ),
        SettingsSection(
          label: l10n.prefsGroupOptionalEmails,
          rows: [
            ListRow.toggle(
              title: l10n.prefsEmailWeeklyDigest,
              subtitle: l10n.prefsEmailWeeklyDigestHint,
              value: _bagValue<String>(SettingsKeys.emailWeeklyDigest) == 'on',
              onChanged: _bagReady ? (_) => _editEmailWeeklyDigest() : null,
            ),
            ListRow.toggle(
              title: l10n.prefsEmailLifecycleDrip,
              subtitle: l10n.prefsEmailLifecycleDripHint,
              value: _bagValue<String>(SettingsKeys.emailLifecycleDrip) == 'on',
              onChanged: _bagReady ? (_) => _editEmailLifecycleDrip() : null,
            ),
          ],
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final prefs = widget.preferences;
    final theme = Theme.of(context);
    // Null when this mount has no stores to resolve visibility against (the
    // run-detail HR shortcut); those rows then keep their plain behaviour.
    final gymShown = switch (widget.gymStore) {
      final gym? => prefs.gymShown(hasData: gym.workouts.isNotEmpty),
      null => null,
    };
    final nutritionShown = switch (widget.foodStore) {
      final food? => prefs.nutritionShown(hasData: food.rows.isNotEmpty),
      null => null,
    };
    // With both hidden a tap on the centre button already starts a run, so
    // the switch reading Off described a behaviour the runner could see was
    // on. It shows the truth and says why it can't be changed here.
    final runPrimaryForced = gymShown == false && nutritionShown == false;
    // Nothing to exclude for a runner who neither shows Gym nor has a lift.
    final hideGymReadiness =
        gymShown == false && (widget.gymStore?.workouts.isEmpty ?? false);
    final offline = widget.settingsSync?.synced == true &&
        widget.settingsSync?.service?.isServerHydrated == false;
    final sections = switch (widget.page) {
      PreferencesPage.display => _displaySections(l10n),
      PreferencesPage.recording =>
        _recordingSections(l10n, runPrimaryForced: runPrimaryForced),
      PreferencesPage.training =>
        _trainingSections(l10n, hideGymReadiness: hideGymReadiness),
      PreferencesPage.privacy => _privacySections(l10n),
      PreferencesPage.notifications => _notificationSections(l10n),
    };
    final title = preferencesPageTitle(l10n, widget.page);
    return PushedPage(
      title: title,
      body: contentColumn(
        context,
        SafeArea(
          child: SettingsList(
            header: [
              PageHeader(title: title),
              if (offline)
                Container(
                  key: const ValueKey('prefs-offline-notice'),
                  margin: const EdgeInsets.fromLTRB(
                      AppInsets.gutter, AppSpace.smPlus, AppInsets.gutter, 0),
                  padding: const EdgeInsets.all(AppSpace.smPlus),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off, size: 18),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(child: Text(l10n.prefsOfflineNotice)),
                    ],
                  ),
                ),
              // Rows that sync through the settings bag are disabled until
              // it is ready, which signed out it never is; say why once, at
              // the top, rather than leave a page of greyed-out rows.
              if (!_bagReady)
                Padding(
                  key: const ValueKey('prefs-sign-in-note'),
                  padding: const EdgeInsets.fromLTRB(
                      AppInsets.gutter, AppSpace.smPlus, AppInsets.gutter, 0),
                  child: Text(
                    l10n.prefsSignInToEdit,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
            ],
            sections: sections,
          ),
        ),
      ),
    );
  }
}

/// A Preferences page's title: its app bar, its row on You, and the page a
/// settings-search result names.
String preferencesPageTitle(AppLocalizations l10n, PreferencesPage page) =>
    switch (page) {
      PreferencesPage.display => l10n.prefsPageDisplay,
      PreferencesPage.recording => l10n.prefsPageRecording,
      PreferencesPage.training => l10n.prefsPageTraining,
      PreferencesPage.privacy => l10n.prefsPagePrivacy,
      PreferencesPage.notifications => l10n.prefsPageNotifications,
    };

/// What a Preferences page holds, as the subtitle of its row on You.
String preferencesPageSummary(AppLocalizations l10n, PreferencesPage page) =>
    switch (page) {
      PreferencesPage.display => l10n.prefsPageDisplaySummary,
      PreferencesPage.recording => l10n.prefsPageRecordingSummary,
      PreferencesPage.training => l10n.prefsPageTrainingSummary,
      PreferencesPage.privacy => l10n.prefsPagePrivacySummary,
      PreferencesPage.notifications => l10n.prefsPageNotificationsSummary,
    };

IconData preferencesPageIcon(PreferencesPage page) => switch (page) {
      PreferencesPage.display => Icons.straighten,
      PreferencesPage.recording => Icons.directions_run,
      PreferencesPage.training => Icons.monitor_heart,
      PreferencesPage.privacy => Icons.lock_outline,
      PreferencesPage.notifications => Icons.notifications_outlined,
    };

/// Every row title each Preferences page can show, gated rows included: the
/// index You's settings search reads, since the pages are not built until
/// opened. `preferences_search_index_test.dart` mounts each page with every
/// gate open and fails when a row and this list disagree.
List<String> preferencesRowTitles(AppLocalizations l10n, PreferencesPage page) =>
    switch (page) {
      PreferencesPage.display => [
          l10n.prefsLanguage,
          l10n.prefsDarkMode,
          l10n.prefsUseMiles,
          l10n.prefsPaceFormat,
          l10n.prefsWeightUnit,
          l10n.prefsWeekStart,
          l10n.prefsDisclosureLevel,
          l10n.prefsProgressCards,
          l10n.prefsMapStyle,
          l10n.prefsUndoWindow,
          l10n.prefsShowCalories,
          l10n.prefsShowMascot,
          l10n.prefsCoachInMessages,
          l10n.prefsShowGym,
          l10n.prefsShowNutrition,
        ],
      PreferencesPage.recording => [
          l10n.prefsDefaultActivity,
          l10n.prefsKeepRunPrimary,
          l10n.prefsKeepScreenOn,
          l10n.prefsDimScreenWhileRecording,
          l10n.prefsAdvancedGps,
          l10n.prefsShowRawTrack,
          l10n.prefsAudioCues,
          l10n.phoneSurfaceVibrationCues,
          l10n.prefsMinimalVoiceCues,
          l10n.prefTurnByTurnCues,
          l10n.prefsSplitInterval,
          l10n.prefsTargetPace,
          l10n.prefsCueSplits,
          l10n.prefsCueStartFinish,
          l10n.prefsCueOffRoute,
          l10n.prefsCuePaceAlerts,
          l10n.prefsCueWorkoutSteps,
          l10n.prefsCueCutoffCatchUp,
          l10n.prefsCueMarkerTargets,
          l10n.prefsCuePhaseTransitions,
          l10n.prefsCueGuidedRun,
          l10n.prefsSplitPaceMode,
        ],
      PreferencesPage.training => [
          l10n.prefsWeeklyGoal,
          l10n.prefsDateOfBirth,
          l10n.prefsRestingHr,
          l10n.prefsMaxHr,
          l10n.prefsHrMedicationAffected,
          l10n.prefsHrMedicationSetMaxHr,
          l10n.prefsHrZones,
          l10n.prefsExcludeGymFromReadiness,
          l10n.prefsExtraRecovery,
          l10n.prefsCarbsPerHour,
          l10n.prefsFluidPerHour,
          l10n.prefsCoachPersonality,
        ],
      PreferencesPage.privacy => [
          l10n.prefsDefaultRunPrivacy,
          l10n.prefsStravaAutoShare,
          l10n.prefsPrivateProfile,
          l10n.followRequestsTitle,
          l10n.prefsDiscoverable,
          l10n.prefsDiscoverableNearby,
          l10n.nearbyAreaTitle,
          l10n.prefsReadReceipts,
          l10n.prefsMessageRequests,
          l10n.privacyZonesTitle,
          l10n.settingsAccountSendErrorReports,
        ],
      PreferencesPage.notifications => [
          l10n.prefsEmailNotifications,
          l10n.prefsPushNotifications,
          l10n.prefsNotifyWorkoutReminder,
          l10n.prefsNotifyRaceStartingSoon,
          l10n.prefsNotifyParkCourseMonth,
          l10n.prefsEmailNewDeviceAlerts,
          l10n.prefsEmailWeeklyDigest,
          l10n.prefsEmailLifecycleDrip,
        ],
    };

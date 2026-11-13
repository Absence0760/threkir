import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart'
    show AppInsets, AppSearchField, AppSpace, ListRow, SettingsList, SettingsSection;

import '../ble_heart_rate.dart';
import '../ble_treadmill.dart';
import '../l10n/gen/app_localizations.dart';
import '../local_gear_store.dart';
import '../local_food_store.dart';
import '../local_gym_store.dart';
import '../local_route_store.dart';
import '../local_run_store.dart';
import '../dev_auto_login.dart';
import '../preferences.dart';
import '../settings_sync.dart';
import '../sim_watch_link.dart';
import '../social_service.dart';
import '../widgets/top_banner.dart';
import 'devices_screen.dart';
import 'follow_requests_screen.dart';
import 'gear_screen.dart';
import 'help_screen.dart';
import 'line_calibration_screen.dart';
import 'settings_about_screen.dart';
import 'settings_account_screen.dart';
import 'settings_body_metrics_screen.dart';
import 'settings_integrations_screen.dart';
import 'settings_preferences_screen.dart';
import 'settings_pro_screen.dart';
import 'settings_safety_screen.dart';
import 'sign_in_screen.dart';
import 'sim_watch_screen.dart';
import 'your_shares_screen.dart';

/// The You tab's settings list: a search over every row, then web's groups
/// in web's order — Profile, Preferences, Apps & data, Account & legal
/// (`apps/web/src/routes/settings/+layout.svelte`), so one IA serves both
/// platforms (issue #1374).
///
/// The search matches a row's title on this list and on every Preferences
/// page (`preferencesRowTitles`), and a result opens the screen or page that
/// holds it. The host (`YouScreen`) supplies the scaffold, the page title and
/// the identity card through [header].
class SettingsScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final Preferences preferences;
  final LocalRunStore? runStore;
  final LocalRouteStore? routeStore;
  final LocalGymStore? gymStore;
  final LocalFoodStore? foodStore;
  final LocalGearStore? gearStore;
  final BleHeartRate heartRate;
  final BleTreadmill treadmill;
  final SettingsSyncService? settingsSync;

  /// Backend URL used to gate the developer section. Defaults to the
  /// runtime SUPABASE_URL; only a loopback backend shows the section,
  /// same isolation rail as the seed auto-login.
  final String? devBackendUrl;

  /// Drawn above the search, inside the same scroll — the You tab's title
  /// and identity card.
  final List<Widget> header;

  /// Rows the host leads the Profile group with (the parkrun barcode
  /// shortcut, when this device holds one).
  final List<Widget> profileRows;

  /// Fires when a sub-screen pushed from here is popped, so the host can
  /// re-read what that screen may have changed (the account screen edits the
  /// display name and avatar the You header draws).
  final VoidCallback? onSubScreenClosed;

  /// Reads the share_attribution gate and backs Your shares; the global
  /// client when null.
  final SocialService? social;

  const SettingsScreen({
    super.key,
    this.apiClient,
    required this.preferences,
    required this.heartRate,
    required this.treadmill,
    this.runStore,
    this.routeStore,
    this.gymStore,
    this.foodStore,
    this.gearStore,
    this.settingsSync,
    this.devBackendUrl,
    this.header = const [],
    this.profileRows = const [],
    this.onSubScreenClosed,
    this.social,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// One searchable destination: what it is called, where it lives (null for
/// a row on this list) and how to open it.
typedef _Entry = ({String title, String? where, VoidCallback? open});

class _SettingsScreenState extends State<SettingsScreen> {
  late final SocialService _social = widget.social ?? SocialService();
  final TextEditingController _search = TextEditingController();

  // Your shares is offered only while the share_attribution gate is open
  // (decisions § 2268).
  bool _sharesEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSharesGate();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadSharesGate() async {
    if (widget.apiClient?.userId == null || !_social.isReady) return;
    final on = await _social.shareAttributionEnabled();
    if (mounted && on) setState(() => _sharesEnabled = true);
  }

  Future<void> _open(Widget Function(BuildContext) builder) async {
    await Navigator.push(context, MaterialPageRoute(builder: builder));
    widget.onSubScreenClosed?.call();
  }

  Future<void> _openAfterSignIn(Widget Function(BuildContext) builder) async {
    final api = widget.apiClient;
    if (api == null) {
      showTopBanner(
          context, AppLocalizations.of(context).settingsBackendNotConfigured);
      return;
    }
    if (api.userId != null) {
      _open(builder);
      return;
    }
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SignInScreen(apiClient: api)),
    );
    if (ok == true && mounted) {
      setState(() {});
      _open(builder);
    }
  }

  void _openPreferences(PreferencesPage page) =>
      _open((_) => SettingsPreferencesScreen(
            page: page,
            apiClient: widget.apiClient,
            preferences: widget.preferences,
            settingsSync: widget.settingsSync,
            gymStore: widget.gymStore,
            foodStore: widget.foodStore,
            runStore: widget.runStore,
          ));

  /// The landing's rows, grouped. Each row is also a search entry, so the
  /// list and the search cannot disagree about what is here.
  List<(String, List<(ListRow, _Entry)>)> _groups(AppLocalizations l10n) {
    final api = widget.apiClient;
    final signedIn = api?.userId != null;
    (ListRow, _Entry) row({
      Key? key,
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback? onTap,
    }) =>
        (
          ListRow.nav(
            key: key,
            icon: icon,
            title: title,
            subtitle: subtitle,
            onTap: onTap,
          ),
          (title: title, where: null, open: onTap),
        );
    final gearStore = widget.gearStore;
    return [
      (
        l10n.settingsSectionProfile,
        [
          row(
            icon: Icons.person_outline,
            title: l10n.settingsAccountTitle,
            subtitle: l10n.settingsTabAccountSubtitle,
            onTap: () => _open((_) => SettingsAccountScreen(
                  apiClient: widget.apiClient,
                  preferences: widget.preferences,
                  settingsSync: widget.settingsSync,
                  runStore: widget.runStore,
                  routeStore: widget.routeStore,
                )),
          ),
          row(
            icon: Icons.monitor_weight_outlined,
            title: l10n.bodyMetricsTitle,
            subtitle: l10n.bodyMetricsTileSubtitle,
            onTap: () => _openAfterSignIn((_) => SettingsBodyMetricsScreen(
                  api: widget.apiClient,
                  settingsSync: widget.settingsSync,
                  preferences: widget.preferences,
                )),
          ),
          row(
            icon: Icons.health_and_safety,
            title: l10n.safetyTitle,
            subtitle: l10n.safetyTileSubtitle,
            onTap: () => _openAfterSignIn((_) => SettingsSafetyScreen(
                  api: widget.apiClient,
                  settingsSync: widget.settingsSync,
                )),
          ),
          // Follow requests were reachable only from a switch deep in the
          // privacy rows, and only once the profile was private (#1374).
          if (signedIn)
            row(
              key: const ValueKey('you-follow-requests'),
              icon: Icons.person_add_alt,
              title: l10n.followRequestsTitle,
              subtitle: l10n.youFollowRequestsSubtitle,
              onTap: () => _open((_) => FollowRequestsScreen(api: api!)),
            ),
        ],
      ),
      (
        l10n.prefsTitle,
        [
          for (final page in PreferencesPage.values)
            row(
              key: ValueKey('you-prefs-${page.name}'),
              icon: preferencesPageIcon(page),
              title: preferencesPageTitle(l10n, page),
              subtitle: preferencesPageSummary(l10n, page),
              onTap: () => _openPreferences(page),
            ),
        ],
      ),
      (
        l10n.settingsSectionAppsData,
        [
          row(
            icon: Icons.link,
            title: l10n.integrationsTitle,
            subtitle: l10n.settingsTabIntegrationsSubtitle,
            onTap: () => _open((_) => SettingsIntegrationsScreen(
                  apiClient: widget.apiClient,
                  heartRate: widget.heartRate,
                  treadmill: widget.treadmill,
                  preferences: widget.preferences,
                  settingsSync: widget.settingsSync,
                )),
          ),
          row(
            icon: Icons.devices,
            title: l10n.devicesTitle,
            subtitle: signedIn
                ? l10n.settingsTabDevicesSubtitle
                : l10n.settingsDevicesSignedOutSubtitle,
            onTap: () => _openAfterSignIn((_) => DevicesScreen(
                  api: widget.apiClient!,
                  currentDeviceId: widget.preferences.deviceId,
                )),
          ),
          // A null onTap renders the row disabled with its reason, never a
          // tappable row that silently does nothing (#666 I16).
          row(
            icon: Icons.directions_run,
            title: l10n.gearTitle,
            subtitle: gearStore == null
                ? l10n.settingsGearUnavailable
                : l10n.settingsTabGearSubtitle,
            onTap: gearStore == null
                ? null
                : () => _open((_) => GearScreen(
                      api: widget.apiClient,
                      preferences: widget.preferences,
                      store: gearStore,
                      runStore: widget.runStore,
                    )),
          ),
          if (_sharesEnabled)
            row(
              icon: Icons.share_outlined,
              title: l10n.sharesTitle,
              subtitle: l10n.sharesTileSubtitle,
              onTap: () =>
                  _openAfterSignIn((_) => YourSharesScreen(social: _social)),
            ),
        ],
      ),
      (
        l10n.settingsSectionAccountLegal,
        [
          row(
            icon: Icons.favorite_outline,
            title: l10n.proTitle,
            subtitle: l10n.settingsTabProSubtitle,
            onTap: () =>
                _open((_) => SettingsProScreen(apiClient: widget.apiClient)),
          ),
          row(
            icon: Icons.info_outline,
            title: l10n.aboutTitle,
            subtitle: l10n.settingsTabAboutSubtitle,
            onTap: () => _open((_) => const SettingsAboutScreen()),
          ),
          row(
            icon: Icons.help_outline,
            title: l10n.helpTitle,
            subtitle: l10n.helpSettingsSubtitle,
            onTap: () => _open((_) => const HelpScreen()),
          ),
        ],
      ),
    ];
  }

  /// Rows that match [query]: the landing's own rows, then every row of
  /// every Preferences page, each opening the page that holds it.
  List<Widget> _results(
    AppLocalizations l10n,
    String query,
    List<(String, List<(ListRow, _Entry)>)> groups,
  ) {
    final q = query.toLowerCase();
    bool hit(String title) => title.toLowerCase().contains(q);
    final entries = <_Entry>[
      for (final (_, rows) in groups)
        for (final (_, entry) in rows) entry,
      for (final page in PreferencesPage.values)
        for (final title in preferencesRowTitles(l10n, page))
          (
            title: title,
            where: preferencesPageTitle(l10n, page),
            open: () => _openPreferences(page),
          ),
    ];
    return [
      for (final e in entries)
        if (hit(e.title))
          ListRow.nav(
            key: ValueKey('settings-search-result-${e.title}'),
            title: e.title,
            subtitle: e.where,
            onTap: e.open,
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final backendUrl = widget.devBackendUrl ?? maybeDevBackendUrl();
    final localBackend = isLocalSupabaseUrl(backendUrl);
    final query = _search.text.trim();
    final groups = _groups(l10n);
    final results = query.isEmpty ? null : _results(l10n, query, groups);
    return SettingsList(
      header: [
        ...widget.header,
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppInsets.gutter, AppSpace.sm, AppInsets.gutter, 0),
          child: AppSearchField(
            key: const ValueKey('settings-search'),
            controller: _search,
            hint: l10n.settingsSearchHint,
            clearTooltip: l10n.commonClearSearch,
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (results != null && results.isEmpty)
          Padding(
            key: const ValueKey('settings-search-empty'),
            padding: const EdgeInsets.fromLTRB(
                AppInsets.gutter, AppSpace.lg, AppInsets.gutter, 0),
            child: Text(
              l10n.settingsSearchNoResults(query),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
      ],
      sections: results != null
          ? [SettingsSection(rows: results)]
          : [
              for (final (i, (label, rows)) in groups.indexed)
                SettingsSection(
                  label: label,
                  rows: [
                    if (i == 0) ...widget.profileRows,
                    for (final (row, _) in rows) row,
                  ],
                ),
              if (kDebugMode)
                SettingsSection(rows: [
                  LineCalibrationEntry(
                    onOpen: () => _open((_) => const LineCalibrationScreen()),
                  ),
                ]),
              if (localBackend)
                SettingsSection(
                  label: l10n.settingsSectionDeveloper,
                  rows: [
                    ListRow.nav(
                      icon: Icons.watch_outlined,
                      title: l10n.simWatchTitle,
                      subtitle: l10n.settingsTabSimWatchSubtitle,
                      onTap: () => _open((_) => const SimWatchScreen()),
                    ),
                  ],
                ),
            ],
    );
  }
}

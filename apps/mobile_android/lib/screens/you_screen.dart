import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../auth_change_aware.dart';
import '../ble_heart_rate.dart';
import '../ble_treadmill.dart';
import '../l10n/gen/app_localizations.dart';
import '../local_gear_store.dart';
import '../local_food_store.dart';
import '../local_gym_store.dart';
import '../local_route_store.dart';
import '../local_run_store.dart';
import '../parkrun_barcode_cache.dart';
import '../preferences.dart';
import '../settings_sync.dart';
import 'parkrun_barcode_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

/// The You tab — profile + the existing Settings surface, hosted under one
/// bottom-nav destination. A profile header tile (own profile) sits above the
/// unchanged [SettingsScreen] body so its section tiles keep working as-is;
/// folding Settings in here is what frees its old standalone bottom-nav slot.
class YouScreen extends StatefulWidget {
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

  const YouScreen({
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
  });

  @override
  State<YouScreen> createState() => _YouScreenState();
}

class _YouScreenState extends State<YouScreen>
    with AuthChangeAware<YouScreen> {
  @override
  ApiClient? get authApi => widget.apiClient;

  /// The runner's barcode, when this device holds one. The shortcut is
  /// derived from that rather than shown to everyone: most runners never go
  /// to a parkrun, and the integrations screen is where one is first added.
  String? _barcodeNumber;

  @override
  void initState() {
    super.initState();
    ParkrunBarcodeCache.changes.addListener(_refreshBarcode);
    _refreshBarcode();
  }

  @override
  void dispose() {
    ParkrunBarcodeCache.changes.removeListener(_refreshBarcode);
    super.dispose();
  }

  Future<void> _refreshBarcode() async {
    final userId = widget.apiClient?.userId;
    final number =
        userId == null ? null : await const ParkrunBarcodeCache().read(userId);
    if (!mounted) return;
    setState(() => _barcodeNumber = number);
  }

  @override
  void onAuthUserChanged(String? userId) {
    setState(() {});
    _refreshBarcode();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final api = widget.apiClient;
    final viewerId = api?.userId;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (api != null && viewerId != null)
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(l10n.youProfileTitle),
                subtitle: api.userEmail?.isNotEmpty ?? false
                    ? Text(api.userEmail!)
                    : null,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ProfileScreen(api: api, userId: viewerId),
                  ),
                ),
              ),
            if (api != null && viewerId != null && _barcodeNumber != null)
              ListTile(
                key: const ValueKey('you-parkrun-barcode'),
                leading: const Icon(Icons.badge_outlined),
                title: Text(l10n.parkrunBarcodeTitle),
                subtitle: Text(_barcodeNumber!),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ParkrunBarcodeScreen(api: api),
                  ),
                ),
              ),
            Expanded(
              child: SettingsScreen(
                apiClient: widget.apiClient,
                preferences: widget.preferences,
                runStore: widget.runStore,
                routeStore: widget.routeStore,
                gymStore: widget.gymStore,
                foodStore: widget.foodStore,
                gearStore: widget.gearStore,
                heartRate: widget.heartRate,
                treadmill: widget.treadmill,
                settingsSync: widget.settingsSync,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

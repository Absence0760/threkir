import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show IdentityAvatar;

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
import '../training_service.dart';
import 'messages_screen.dart';
import 'parkrun_barcode_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

/// The You tab — profile + the existing Settings surface, hosted under one
/// bottom-nav destination. An identity header (the runner's name and avatar,
/// opening their own profile, with the inbox as an icon beside it) scrolls
/// with the [SettingsScreen] body below it; folding Settings in here is what
/// frees its old standalone bottom-nav slot. The email is deliberately not on
/// the header: it is the Account screen's subject, and showing it here as
/// well put the same address on two adjacent rows.
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

  /// What the inbox's AI Coach row opens the Coach with.
  final TrainingService? training;

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
    this.training,
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

  /// The signed-in runner's display name and avatar, null until read (or
  /// when the read failed — the header then falls back to "Your profile").
  String? _displayName;
  String? _avatarUrl;

  int _unreadDms = 0;

  @override
  void initState() {
    super.initState();
    ParkrunBarcodeCache.changes.addListener(_refreshBarcode);
    _refreshBarcode();
    _refreshIdentity();
    _refreshUnread();
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

  Future<void> _refreshIdentity() async {
    final api = widget.apiClient;
    final asked = api?.userId;
    if (api == null || asked == null) return;
    try {
      final profile = await api.fetchMyProfile();
      // A sign-out or account switch mid-read must not paint the previous
      // runner's name on the next one's header.
      if (!mounted || api.userId != asked) return;
      setState(() {
        _displayName = profile?.displayName?.trim();
        _avatarUrl = profile?.avatarUrl;
      });
    } catch (e) {
      // L4 — the header degrades to "Your profile" and the generated avatar.
      debugPrint('YouScreen profile read failed: ${safeErrorLabel(e)}');
    }
  }

  Future<void> _refreshUnread() async {
    final api = widget.apiClient;
    final asked = api?.userId;
    if (api == null || asked == null) return;
    try {
      final count = await api.fetchUnreadDmCount();
      if (!mounted || api.userId != asked) return;
      setState(() => _unreadDms = count);
    } catch (e) {
      // L4 — a failed count leaves the badge dark; the inbox still opens.
      debugPrint('YouScreen unread-DM read failed: ${safeErrorLabel(e)}');
    }
  }

  void _refreshAfterSubScreen() {
    _refreshIdentity();
    _refreshUnread();
  }

  @override
  void onAuthUserChanged(String? userId) {
    setState(() {
      _displayName = null;
      _avatarUrl = null;
      _unreadDms = 0;
    });
    _refreshBarcode();
    _refreshIdentity();
    _refreshUnread();
  }

  Future<void> _push(Widget screen) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => screen),
    );
    if (mounted) _refreshAfterSubScreen();
  }

  Widget _identityHeader(BuildContext context, ApiClient api, String viewerId) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final name = _displayName;
    final hasName = name != null && name.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              key: const ValueKey('you-profile-header'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => _push(ProfileScreen(api: api, userId: viewerId)),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    IdentityAvatar(
                      seed: viewerId,
                      name: hasName ? name : api.userEmail,
                      imageUrl: _avatarUrl,
                      size: 56,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasName ? name : l10n.youProfileTitle,
                            style: theme.textTheme.titleLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n.youViewProfile,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Merged so the count is announced on the button itself, not as
          // a separate node after it.
          MergeSemantics(
            child: Semantics(
              value: _unreadDms > 0
                  ? l10n.messagesUnreadCount(_unreadDms)
                  : null,
              child: IconButton(
                key: const ValueKey('you-messages'),
                tooltip: l10n.messagesTitle,
                onPressed: () => _push(
                  MessagesScreen(api: api, training: widget.training),
                ),
                icon: ExcludeSemantics(
                  child: Badge.count(
                    count: _unreadDms,
                    isLabelVisible: _unreadDms > 0,
                    child: const Icon(Icons.chat_bubble_outline),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final api = widget.apiClient;
    final viewerId = api?.userId;
    final signedIn = api != null && viewerId != null;
    return Scaffold(
      body: SafeArea(
        bottom: false,
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
          onSubScreenClosed: _refreshAfterSubScreen,
          header: [
            if (signedIn) _identityHeader(context, api, viewerId),
            if (signedIn && _barcodeNumber != null)
              ListTile(
                key: const ValueKey('you-parkrun-barcode'),
                leading: const Icon(Icons.badge_outlined),
                title: Text(l10n.parkrunBarcodeTitle),
                subtitle: Text(_barcodeNumber!),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _push(ParkrunBarcodeScreen(api: api)),
              ),
          ],
        ),
      ),
    );
  }
}

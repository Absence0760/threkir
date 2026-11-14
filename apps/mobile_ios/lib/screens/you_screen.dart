import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart'
    show
        AppInsets,
        AppSpace,
        IdentityAvatar,
        ListCard,
        ListRow,
        RootPage;

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
import 'edit_profile_screen.dart';
import 'settings_screen.dart';
import 'sign_in_screen.dart';

/// The You tab: a page title, the runner's identity card, then the settings
/// list ([SettingsScreen]) with its search and web's groups.
///
/// The owner settled what You is (issue #1374): an account hub, not a
/// settings list with a profile link stuck to its top. The card opens the
/// runner's own profile and offers Edit profile, so tapping your own face
/// lets you change it. Messages moved to Social, and Athletes & coaches and
/// Guided runs to the Coach, so nothing here is a feature dressed as a
/// setting. Signed out, the card is a sign-in prompt rather than nothing.
///
/// The email is deliberately not on the card: it is the Account screen's
/// subject, and showing it here as well put the same address on two adjacent
/// rows.
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

  /// The signed-in runner's display name and avatar, null until read (or
  /// when the read failed — the card then falls back to "Your profile").
  String? _displayName;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    ParkrunBarcodeCache.changes.addListener(_refreshBarcode);
    _refreshBarcode();
    _refreshIdentity();
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
      // runner's name on the next one's card.
      if (!mounted || api.userId != asked) return;
      setState(() {
        _displayName = profile?.displayName?.trim();
        _avatarUrl = profile?.avatarUrl;
      });
    } catch (e) {
      // L4 — the card degrades to "Your profile" and the generated avatar.
      debugPrint('YouScreen profile read failed: ${safeErrorLabel(e)}');
    }
  }

  @override
  void onAuthUserChanged(String? userId) {
    setState(() {
      _displayName = null;
      _avatarUrl = null;
    });
    _refreshBarcode();
    _refreshIdentity();
  }

  Future<void> _push(Widget screen) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => screen),
    );
    if (mounted) _refreshIdentity();
  }

  Future<void> _signIn(ApiClient api) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => SignInScreen(apiClient: api)),
    );
    if (mounted) setState(() {});
  }

  Widget _identityCard(BuildContext context, ApiClient api, String viewerId) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final name = _displayName;
    final hasName = name != null && name.isNotEmpty;
    // Flush: the profile link and Edit profile are two targets of their own.
    return ListCard.flush(
      key: const ValueKey('you-identity-card'),
      margin: const EdgeInsets.symmetric(horizontal: AppInsets.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const ValueKey('you-profile-header'),
            onTap: () => _push(ProfileScreen(api: api, userId: viewerId)),
            child: Padding(
              padding: AppInsets.card,
              child: Row(
                children: [
                  IdentityAvatar(
                    seed: viewerId,
                    name: hasName ? name : api.userEmail,
                    imageUrl: _avatarUrl,
                    size: 56,
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasName ? name : l10n.youProfileTitle,
                          style: theme.textTheme.titleLarge,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppSpace.xxs),
                        Text(
                          l10n.youViewProfile,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
          // The photo, name and username are edited on their own page, one tap
          // from your own face.
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppInsets.gutter, 0, AppInsets.gutter, AppSpace.smPlus),
            child: OutlinedButton.icon(
              key: const ValueKey('you-edit-profile'),
              onPressed: () => _push(EditProfileScreen(apiClient: api)),
              icon: const Icon(Icons.edit_outlined),
              label: Text(l10n.youEditProfile),
            ),
          ),
        ],
      ),
    );
  }

  /// Signed out the identity card has no one to show; say what signing in
  /// gives and offer it, rather than leave the top of the page empty with
  /// sign-in hidden inside Account.
  Widget _signInCard(BuildContext context, ApiClient api) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListCard(
      key: const ValueKey('you-sign-in-card'),
      margin: const EdgeInsets.symmetric(horizontal: AppInsets.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.settingsAccountSignInToSync,
              style: theme.textTheme.bodyLarge),
          const SizedBox(height: AppSpace.smPlus),
          FilledButton(
            onPressed: () => _signIn(api),
            child: Text(l10n.settingsAccountSignIn),
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
    return RootPage(
      title: l10n.navYou,
      body: SettingsScreen(
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
        onSubScreenClosed: _refreshIdentity,
        header: [
          if (api != null && viewerId != null)
            _identityCard(context, api, viewerId)
          else if (api != null)
            _signInCard(context, api),
        ],
        profileRows: [
          if (viewerId != null && _barcodeNumber != null)
            ListRow.nav(
              key: const ValueKey('you-parkrun-barcode'),
              icon: Icons.badge_outlined,
              title: l10n.parkrunBarcodeTitle,
              subtitle: _barcodeNumber,
              onTap: () => _push(ParkrunBarcodeScreen(api: api!)),
            ),
        ],
      ),
    );
  }
}

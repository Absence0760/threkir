import 'dart:io' show Platform;

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ui_kit/ui_kit.dart'
    show AppMotion, motionDuration, reduceMotion;

import '../l10n/gen/app_localizations.dart';
import '../preferences.dart';
import '../settings_sync.dart';
import '../widgets/sign_in_required_state.dart' show resolveApiForSignIn;
import 'sign_in_screen.dart';
import 'sign_up_screen.dart';

/// First-launch welcome flow. Three info pages, a privacy-default chooser
/// that also runs the location-permission request, and finally the account
/// offer. Marks preferences.onboarded = true on completion.
///
/// The account page is the only place a brand-new person is shown that an
/// account exists: before it, the shortest route from a cold launch to
/// "create account" was Settings, a tile whose subtitle never said so, the
/// sign-in screen, and a scroll to its last button.
class OnboardingScreen extends StatefulWidget {
  final Preferences preferences;
  final VoidCallback onDone;
  /// Optional — when present, the chosen privacy default is written to
  /// the universal settings bag so it roams and isn't silently
  /// overridden by another device's default (persona #56).
  final SettingsSyncService? settingsSync;

  /// The client the account page hands to sign-up / sign-in. Optional: the
  /// caller rarely has one at first launch, so it falls back to the shared
  /// resolver, which answers null on a build where Supabase never
  /// initialized.
  final ApiClient? apiClient;

  const OnboardingScreen({
    super.key,
    required this.preferences,
    required this.onDone,
    this.settingsSync,
    this.apiClient,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;
  /// Default visibility for new runs, chosen on the final onboarding
  /// page. Privacy-by-default for a brand-new runner (persona #56);
  /// matches the web wizard's default so cross-device sync agrees.
  String _privacyDefault = 'private';

  /// The three info pages before the privacy chooser.
  static const int _infoPageCount = 3;

  /// The client the account page's buttons hand to sign-up / sign-in. Null
  /// when Supabase never initialized, and the page is then dropped rather
  /// than offering an account this build cannot create (issue #238).
  ApiClient? get _api => resolveApiForSignIn(widget.apiClient);

  bool get _hasAccountPage => _api != null;

  /// Total onboarding pages: the info pages + the privacy chooser + the
  /// account offer, when there is a backend to make an account on.
  int get _pageCount => _infoPageCount + 1 + (_hasAccountPage ? 1 : 0);
  bool get _onPrivacyPage => _page == _infoPageCount;
  bool get _onAccountPage => _hasAccountPage && _page == _infoPageCount + 1;

  // Location disclosure copy mandated by Google Play's location policy:
  // the in-app rationale must run BEFORE the OS permission dialog, must
  // name the specific feature using location, and must explain what
  // happens if the user declines. Apple's App Review Guideline 5.1.5 wants
  // the same in the location strings (NSLocationWhenInUseUsageDescription
  // / NSLocationAlwaysAndWhenInUseUsageDescription on iOS).
  //
  // The two platforms get different copy because they genuinely differ:
  // Android's first runtime dialog cannot grant more than "while using the
  // app" (decisions.md § 611) and the "Allow all the time" upgrade is a
  // separate trip to Settings that `run_screen` offers before the first
  // run; on iOS "While Using the App" plus UIBackgroundModes:location IS a
  // supported background-recording configuration, so there is no upgrade
  // to promise and the Settings path named is iOS's.
  List<_PageData> _infoPages(AppLocalizations l10n) => [
        _PageData(
          icon: Icons.directions_run,
          title: l10n.onboardingTrackTitle,
          description: l10n.onboardingTrackBody,
        ),
        _PageData(
          icon: Icons.route,
          title: l10n.onboardingRoutesTitle,
          description: l10n.onboardingRoutesBody,
        ),
        _PageData(
          icon: Icons.location_on,
          title: l10n.onboardingLocationTitle,
          description: Platform.isIOS
              ? l10n.onboardingLocationBodyIos
              : l10n.onboardingLocationBodyAndroid,
        ),
      ];

  Future<void> _next() async {
    if (_onPrivacyPage) {
      await _commitPrivacyAndPermission();
      if (!mounted) return;
      if (!_hasAccountPage) return _complete();
      _advance();
      return;
    }
    if (_onAccountPage) return _complete();
    _advance();
  }

  void _advance() {
    // `nextPage` is a driven scroll, which the platform reduce-motion flag
    // does not reach (`AnimationController.unbounded` defaults to
    // `AnimationBehavior.preserve`) and which asserts against a zero
    // duration — so the reduced path has to be a jump, not a faster slide.
    if (reduceMotion(context)) {
      _controller.jumpToPage(_page + 1);
    } else {
      _controller.nextPage(
        duration: AppMotion.standard,
        curve: AppMotion.curveStandard,
      );
    }
  }

  Future<void> _commitPrivacyAndPermission() async {
    // Persist the privacy choice locally (drives is_public on every
    // run save) AND push it to the universal bag so it's an explicit
    // value that roams + isn't overridden by another device's default
    // (persona #56). The bag write is best-effort — the local pref is
    // what protects new-run visibility immediately.
    await widget.preferences.setPrivacyDefault(_privacyDefault);
    try {
      await widget.settingsSync?.updateUniversal(
        <String, dynamic>{SettingsKeys.privacyDefault: _privacyDefault},
      );
    } catch (e) {
      debugPrint('onboarding privacy bag write failed (kept local): $e');
    }
    final permission = await _requestLocationPermission();
    if (!mounted) return;
    // The outcome used to be thrown away, so a runner who tapped Deny
    // finished onboarding having been told what declining would cost and
    // then never told it had happened. A null result means the platform
    // call itself failed — we don't know what the grant is, so we say
    // nothing rather than accuse the OS of refusing.
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      await _disclosePermissionDenied();
    }
  }

  Future<void> _complete() async {
    await widget.preferences.setOnboarded(true);
    if (!mounted) return;
    widget.onDone();
  }

  /// Opens sign-up or sign-in and, on a real session, finishes onboarding
  /// straight into the signed-in dashboard. A sign-up that only sent a
  /// confirmation email pops without a result and leaves the runner on this
  /// page, where "Not now" is still there.
  Future<void> _openAuth({required bool signUp}) async {
    final api = _api;
    if (api == null) return;
    final signedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => signUp
            ? SignUpScreen(apiClient: api)
            : SignInScreen(apiClient: api),
      ),
    );
    if (!mounted || signedIn != true) return;
    await _complete();
  }

  /// Requests the foreground ("while in use") grant — the only one either
  /// platform's first runtime dialog can give — and returns what came back.
  /// Null when the platform call threw, which is not a denial.
  Future<LocationPermission?> _requestLocationPermission() async {
    try {
      final status = await Geolocator.checkPermission();
      if (status != LocationPermission.denied) return status;
      return await Geolocator.requestPermission();
    } catch (e) {
      debugPrint('Location permission request failed: $e');
      return null;
    }
  }

  Future<void> _disclosePermissionDenied() async {
    final l10n = AppLocalizations.of(context);
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.onboardingLocationDeniedTitle),
        content: Text(l10n.onboardingLocationDeniedBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.onboardingLocationDeniedContinue),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.onboardingLocationDeniedSettings),
          ),
        ],
      ),
    );
    if (openSettings != true) return;
    try {
      await Geolocator.openAppSettings();
    } catch (e) {
      debugPrint('openAppSettings failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final infoPages = _infoPages(l10n);
    final indicatorDuration = motionDuration(context, AppMotion.brief);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pageCount,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, index) {
                  if (index == infoPages.length) {
                    return _buildPrivacyPage(theme, l10n);
                  }
                  if (index == infoPages.length + 1) {
                    return _buildAccountPage(theme, l10n);
                  }
                  final p = infoPages[index];
                  // The Location page's Play-policy disclosure copy is
                  // long enough to overflow a small phone viewport when
                  // centered in a fixed-height Column. LayoutBuilder +
                  // SingleChildScrollView + ConstrainedBox(minHeight) +
                  // IntrinsicHeight keeps the vertical centering on
                  // pages whose content fits AND falls through to a
                  // scrollable column on the disclosure page.
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: IntrinsicHeight(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 120,
                                  height: 120,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: theme.colorScheme.primaryContainer,
                                  ),
                                  child: Icon(p.icon,
                                      size: 64, color: theme.colorScheme.primary),
                                ),
                                const SizedBox(height: 32),
                                Text(
                                  p.title,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  p.description,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pageCount, (i) {
                return AnimatedContainer(
                  duration: indicatorDuration,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _page ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _page
                        ? theme.colorScheme.primary
                        : theme.dividerColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                // The account page hosts its own two primary actions, so
                // the footer there is the decline — it must not out-shout
                // them.
                child: _onAccountPage
                    ? TextButton(
                        onPressed: _next,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text(l10n.onboardingAccountLater),
                      )
                    : FilledButton(
                        onPressed: _next,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text(
                          _onPrivacyPage
                              ? l10n.onboardingGrantPermission
                              : l10n.onboardingNext,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountPage(ThemeData theme, AppLocalizations l10n) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Icon(Icons.cloud_sync_outlined,
              size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 20),
          Text(
            l10n.onboardingAccountTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.onboardingAccountBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => _openAuth(signUp: true),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(l10n.onboardingAccountCreate),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _openAuth(signUp: false),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(l10n.onboardingAccountSignIn),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyPage(ThemeData theme, AppLocalizations l10n) {
    final options = [
      (
        value: 'private',
        icon: Icons.lock_outline,
        title: l10n.privacyPrivateTitle,
        subtitle: l10n.privacyPrivateSubtitle,
      ),
      (
        value: 'followers',
        icon: Icons.group,
        title: l10n.privacyFollowersTitle,
        subtitle: l10n.privacyFollowersSubtitle,
      ),
      (
        value: 'public',
        icon: Icons.public,
        title: l10n.privacyPublicTitle,
        subtitle: l10n.privacyPublicSubtitle,
      ),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 8),
          Text(
            l10n.onboardingPrivacyTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.onboardingPrivacyBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
          ),
          const SizedBox(height: 20),
          for (final o in options)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: _privacyDefault == o.value
                      ? theme.colorScheme.primary
                      : theme.dividerColor,
                  width: _privacyDefault == o.value ? 2 : 1,
                ),
              ),
              child: RadioListTile<String>(
                value: o.value,
                groupValue: _privacyDefault,
                onChanged: (v) => setState(() => _privacyDefault = v!),
                secondary: Icon(o.icon, color: theme.colorScheme.primary),
                title: Text(o.title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(o.subtitle),
              ),
            ),
        ],
      ),
    );
  }
}

class _PageData {
  final IconData icon;
  final String title;
  final String description;
  const _PageData({
    required this.icon,
    required this.title,
    required this.description,
  });
}

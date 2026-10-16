import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../legal_links.dart';
import '../pro_sellable.dart';
import '../revenuecat.dart';
import '../share_sheet.dart';
import '../store_links.dart';
import '../widgets/top_banner.dart';

class SettingsProScreen extends StatefulWidget {
  /// Injection seam for the live-perk lookup so widget tests can drive
  /// both storefront states without a network.
  final Future<ProPerks> Function()? loadPerks;

  /// Injection seam for the store, so widget tests can drive plan choice
  /// and the purchase it leads to without the native RevenueCat SDK.
  final ProStore? store;

  /// Reads the server tier (`is_pro`) for the Pro status.
  final ApiClient? apiClient;

  /// Injection seam for the server-tier check; defaults to
  /// [ApiClient.isPro] on [apiClient].
  final Future<bool> Function()? loadServerPro;

  const SettingsProScreen({
    super.key,
    this.loadPerks,
    this.store,
    this.apiClient,
    this.loadServerPro,
  });

  @override
  State<SettingsProScreen> createState() => _SettingsProScreenState();
}

class _SettingsProScreenState extends State<SettingsProScreen>
    with WidgetsBindingObserver {
  // USD list price — the fallback shown only until/unless RevenueCat returns
  // the territory-localised price. Apple Guideline 3.1.1 / Play subscription
  // policy require the displayed amount to come from the store (it varies by
  // region), so this constant is a last resort for unconfigured builds and
  // the brief window before the offering loads.
  static const String _usdListPrice = r'$9.99';

  late final ProStore _store = widget.store ??
      RevenueCatProStore(() => Supabase.instance.client.auth.currentUser?.id);

  // The plans the offering sells, each with its store-localised price, once
  // RevenueCat resolves it; null until then, on unconfigured builds, and when
  // the fetch fails, all of which fall back to the monthly USD list price.
  ProPlanOptions? _plans;

  // The buyer's explicit choice; null means the offering's default (annual
  // when the offering carries it).
  ProPlan? _chosenPlan;

  // In-flight guard for the IAP actions (checkout / restore / manage). A
  // double-tap on a payment tile must not open two checkout sheets or fire
  // two restore round-trips. Web guards its CTA with `disabled={purchasing}`.
  bool _proBusy = false;

  // Which Pro perks this deploy can actually deliver. Null until the
  // manifest resolves, and `sellable` reads false until then — the
  // storefront must never offer a purchase it can't justify, so the
  // teaser is what shows while we don't know (decisions §466).
  ProPerks? _perks;

  // Pro status comes from two places that disagree for a while after every
  // purchase. The store entitlement is true the moment the purchase
  // completes; `subscription_tier` is the authoritative tier the server
  // gates on, but only flips once the revenuecat-webhook lands, and it is
  // also the only one that knows about Pro bought on web or a lifetime
  // tier. Either one makes the user Pro here. Null server tier = unknown.
  ProEntitlement? _entitlement;
  bool? _serverPro;

  // While the store says Pro and the server does not yet, re-ask the server
  // a bounded number of times so the "unlocking" note clears on its own.
  static const _serverRecheckDelay = Duration(seconds: 5);
  static const _maxServerRechecks = 6;
  Timer? _serverRecheck;
  int _serverRechecks = 0;

  bool get _isPro => _entitlement != null || _serverPro == true;

  bool get _awaitingServer => _entitlement != null && _serverPro == false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPlans();
    _loadPerks();
    _loadStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _serverRecheck?.cancel();
    super.dispose();
  }

  // Back from the store's subscription page, a cancel or plan change has to
  // show without reopening the screen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadStatus();
  }

  Future<void> _loadStatus() async {
    _serverRechecks = 0;
    await Future.wait([_loadEntitlement(), _loadServerTier()]);
    _scheduleServerRecheck();
  }

  Future<void> _loadEntitlement() async {
    final ProEntitlement? entitlement;
    try {
      entitlement = await _store.loadEntitlement();
    } catch (e) {
      debugPrint('Pro entitlement load failed: $e');
      return;
    }
    if (!mounted) return;
    setState(() => _entitlement = entitlement);
  }

  Future<void> _loadServerTier() async {
    final check = widget.loadServerPro ?? widget.apiClient?.isPro;
    if (check == null) return;
    final bool pro;
    try {
      pro = await check();
    } catch (e) {
      debugPrint('Pro server tier load failed: $e');
      return;
    }
    if (!mounted) return;
    setState(() => _serverPro = pro);
  }

  void _scheduleServerRecheck() {
    if (!mounted || !_awaitingServer) {
      _serverRecheck?.cancel();
      _serverRecheck = null;
      return;
    }
    if (_serverRecheck != null || _serverRechecks >= _maxServerRechecks) {
      return;
    }
    _serverRecheck = Timer(_serverRecheckDelay, () async {
      _serverRecheck = null;
      _serverRechecks++;
      await _loadServerTier();
      _scheduleServerRecheck();
    });
  }

  Future<void> _loadPerks() async {
    final perks = await (widget.loadPerks ?? fetchProPerks)();
    if (!mounted) return;
    setState(() => _perks = perks);
  }

  Future<void> _loadPlans() async {
    // On unconfigured builds (dev / CI / tests) the live store returns before
    // touching Supabase.instance, so the screen mounts without a live
    // Supabase — matching the lazy access in the tap handlers.
    final ProPlanOptions? plans;
    try {
      plans = await _store.loadPlans();
    } catch (e) {
      debugPrint('Pro plans load failed: $e');
      return;
    }
    if (!mounted || plans == null) return;
    setState(() => _plans = plans);
  }

  ProPlan get _selectedPlan =>
      _chosenPlan ?? _plans?.defaultPlan ?? ProPlan.monthly;

  Future<void> _openExternal(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        await shareTextFrom(context, text: url);
      }
    } catch (_) {
      if (!context.mounted) return;
      try {
        await shareTextFrom(context, text: url);
      } catch (e) {
        if (!context.mounted) return;
        showTopBanner(context, AppLocalizations.of(context).proCouldNotOpen(e));
      }
    }
  }

  Future<void> _startProCheckout(BuildContext context) async {
    if (_proBusy) return;
    // Second gate behind the hidden CTA: no caller may reach checkout
    // while the deploy has no live perk to sell or nowhere to pay.
    if (!proPurchasable(_perks,
        storeConfigured: _store.configured,
        webLinksAllowed: webPaymentLinksAllowed())) {
      return;
    }
    final webCheckout =
        webPaymentLinksAllowed() && (_perks?.webCheckout ?? false);
    setState(() => _proBusy = true);
    try {
      if (!_store.configured) {
        if (webCheckout) {
          await _openExternal(context, webUpgradeUrl());
        }
        return;
      }
      final r = await _store.purchase(_selectedPlan);
      if (!context.mounted) return;
      final l10n = AppLocalizations.of(context);
      switch (r) {
        case PurchaseResult.purchased:
          showTopBanner(context, l10n.proWelcome);
          final bought = _selectedPlan;
          await _loadStatus();
          // The store just said yes; a lagging CustomerInfo read must not
          // put the Subscribe tiles back in front of a subscriber.
          if (mounted && _entitlement == null) {
            setState(() => _entitlement = ProEntitlement(plan: bought));
            _scheduleServerRecheck();
          }
          break;
        case PurchaseResult.cancelled:
          break;
        case PurchaseResult.failed:
          showTopBanner(context, l10n.proPurchaseFailed);
          break;
        case PurchaseResult.notConfigured:
          if (webCheckout) {
            await _openExternal(context, webUpgradeUrl());
          }
          break;
      }
    } finally {
      if (mounted) setState(() => _proBusy = false);
    }
  }

  Future<void> _restorePurchases(BuildContext context) async {
    if (_proBusy) return;
    setState(() => _proBusy = true);
    try {
      if (!_store.configured) {
        showTopBanner(
            context, AppLocalizations.of(context).proRestoreNeedsSignIn);
        return;
      }
      final r = await _store.restore();
      if (!context.mounted) return;
      final l10n = AppLocalizations.of(context);
      switch (r) {
        case PurchaseResult.purchased:
          showTopBanner(context, l10n.proRestored);
          await _loadStatus();
          break;
        case PurchaseResult.cancelled:
          showTopBanner(context, l10n.proRestoreNone);
          break;
        case PurchaseResult.failed:
          showTopBanner(context, l10n.proRestoreFailed);
          break;
        case PurchaseResult.notConfigured:
          showTopBanner(context, l10n.proRestoreNeedsSignIn);
          break;
      }
    } finally {
      if (mounted) setState(() => _proBusy = false);
    }
  }

  Future<void> _openManageSubscription(BuildContext context) async {
    if (_proBusy) return;
    setState(() => _proBusy = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      final target = await resolveManageSubscriptionUrl(userId);
      if (!context.mounted) return;
      await _openExternal(context, target);
    } finally {
      if (mounted) setState(() => _proBusy = false);
    }
  }

  Widget _planTile(
    BuildContext context,
    ProPlanOptions plans,
    ProPlan plan, {
    required bool selected,
  }) {
    final l10n = AppLocalizations.of(context);
    final price = plans.packageFor(plan)!.storeProduct.priceString;
    final saving = plan == ProPlan.annual ? plans.savingPercent : null;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: ListTile(
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        ),
        title: Text(plan == ProPlan.annual
            ? l10n.proPlanAnnual(price)
            : l10n.proPlanMonthly(price)),
        subtitle: saving == null ? null : Text(l10n.proPlanAnnualSaving(saving)),
        selected: selected,
        enabled: !_proBusy,
        onTap: () => setState(() => _chosenPlan = plan),
      ),
    );
  }

  Widget _proStatusTile(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final e = _entitlement;
    final expiresAt = e?.expiresAt;
    final when = expiresAt == null
        ? null
        : formatDateMed(expiresAt, localeToTag(Localizations.localeOf(context)));
    final details = <String>[
      if (e?.plan == ProPlan.monthly) l10n.proActivePlanMonthly,
      if (e?.plan == ProPlan.annual) l10n.proActivePlanAnnual,
      if (when != null)
        e!.willRenew ? l10n.proActiveRenews(when) : l10n.proActiveEnds(when),
    ];
    return ListTile(
      leading: Icon(Icons.workspace_premium_outlined, color: theme.colorScheme.primary),
      title: Text(
        l10n.proActiveTitle,
        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(details.isEmpty ? l10n.proActiveThanks : details.join(' · ')),
    );
  }

  Widget _footnote(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isPro = _isPro;
    final rcConfigured = _store.configured;
    final plans = _plans;
    final plan = _selectedPlan;
    // Prefer the store-localised price; fall back to the monthly USD list
    // price until (or unless) the offering resolves. When we have the real
    // localised price the USD-disclaimer note below is redundant + misleading,
    // so it only shows on the fallback.
    final storePrice = plans?.packageFor(plan)?.storeProduct.priceString;
    final priceLabel = storePrice ?? _usdListPrice;
    final showRegionalNote = storePrice == null;
    final annual = storePrice != null && plan == ProPlan.annual;
    final choices = plans?.plans ?? const <ProPlan>[];
    // Mirrors web's proSellable branch: a purchase CTA only where a perk
    // is live, else the coming-soon teaser. Unknown counts as not sellable.
    // Where the store SDK is unconfigured the purchase would be a web
    // checkout, which iOS may not offer (decisions § 1700) and which counts
    // only while the web deploy has one (decisions § 1826).
    final sellable = proPurchasable(_perks,
        storeConfigured: rcConfigured,
        webLinksAllowed: webPaymentLinksAllowed());
    return Scaffold(
      appBar: AppBar(title: Text(l10n.proTitle)),
      body: SafeArea(
        child: ListView(
          children: [
            // A subscriber is shown what they have, not a storefront that
            // sells it to them again.
            if (isPro) ...[
              _proStatusTile(context),
              if (_awaitingServer) _footnote(context, l10n.proActivePending),
            ] else ...[
              if (sellable && choices.length > 1)
                for (final choice in choices)
                  _planTile(context, plans!, choice, selected: choice == plan),
              if (sellable)
                ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined),
                  title: Text(annual
                      ? l10n.proSubscribeTitleAnnual(priceLabel)
                      : l10n.proSubscribeTitle(priceLabel)),
                  subtitle: Text(
                    annual
                        ? l10n.proSubscribeSubtitleConfiguredAnnual
                        : rcConfigured
                            ? l10n.proSubscribeSubtitleConfigured
                            : l10n.proSubscribeSubtitleWeb,
                  ),
                  trailing: Icon(
                    rcConfigured ? Icons.chevron_right : Icons.open_in_new,
                    size: 18,
                  ),
                  enabled: !_proBusy,
                  onTap: () => _startProCheckout(context),
                )
              else
                ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined),
                  title: Text(l10n.proComingSoonTitle),
                  subtitle: Text(l10n.proComingSoon),
                ),
              // Honesty note mirroring web /settings/upgrade (audit-findings
              // 2026-05-30 Medium [regional]). Shown only when we're falling
              // back to the $9.99 USD list price (RevenueCat unconfigured or
              // offering not yet loaded); once the store returns a localised
              // price the note is dropped. See followups.md § Mobile.
              if (sellable && showRegionalNote)
                _footnote(context, l10n.proRegionalNote),
            ],
            // App Store Guideline 3.1.2: the terms and the privacy policy must
            // be reachable from the auto-renewing purchase itself.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Wrap(
                alignment: WrapAlignment.center,
                children: [
                  for (final doc in const [LegalDoc.terms, LegalDoc.privacy])
                    TextButton(
                      onPressed: () => openLegalDoc(context, doc),
                      child: Text(legalDocLabel(l10n, doc)),
                    ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: Text(l10n.proRestorePurchases),
              subtitle: Text(l10n.proRestorePurchasesSubtitle),
              trailing: const Icon(Icons.chevron_right, size: 18),
              enabled: !_proBusy,
              onTap: () => _restorePurchases(context),
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: Text(l10n.proManageSubscription),
              subtitle: Text(l10n.proManageSubscriptionSubtitle),
              trailing: const Icon(Icons.open_in_new, size: 18),
              enabled: !_proBusy,
              onTap: () => _openManageSubscription(context),
            ),
            if (webPaymentLinksAllowed())
              ListTile(
                leading: const Icon(Icons.volunteer_activism_outlined),
                title: Text(l10n.proSupport),
                subtitle: Text(l10n.proSupportSubtitle),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () => _openExternal(context, webUpgradeUrl()),
              ),
          ],
        ),
      ),
    );
  }
}

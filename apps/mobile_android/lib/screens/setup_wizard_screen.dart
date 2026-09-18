import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../auth_error.dart';
import '../l10n/gen/app_localizations.dart';
import '../locale_defaults.dart';
import '../onboarding.dart';
import '../preferences.dart';
import '../text_limits.dart';
import '../settings_sync.dart';
import '../typed_decimal.dart';
import '../widgets/confirm_destructive.dart';
import '../widgets/top_banner.dart';

/// Post-signup setup wizard — mobile twin of web's 7-step `/onboarding`
/// page. Shown once when a signed-in user's `user_profiles.onboarded_at`
/// is still null; stamps it on Finish or Skip so a returning user never
/// re-sees it. The home-screen gate ([SetupWizardScreen] is pushed by
/// `home_screen.dart`) owns the "show once" decision.
///
/// Distinct from `onboarding_screen.dart`, the FIRST-LAUNCH permission /
/// privacy flow keyed on the local `Preferences.onboarded` flag. This
/// wizard collects account-level setup data and writes the SAME fields
/// web collects (display name, units, goal, demographics + Art 9 consent,
/// privacy default, notifications).
class SetupWizardScreen extends StatelessWidget {
  final ApiClient apiClient;
  final Preferences preferences;
  final SettingsSyncService? settingsSync;

  /// The user's display name from the auth row, if the provider returned
  /// one — prefills the name field so the user can edit before continuing.
  final String? initialDisplayName;

  /// The user's explicitly chosen `preferred_unit` ('km' | 'mi'), if any,
  /// prefilled into the units toggle. Null when the user never picked one
  /// — the wizard then seeds from the device locale.
  final String? initialPreferredUnit;

  const SetupWizardScreen({
    super.key,
    required this.apiClient,
    required this.preferences,
    this.settingsSync,
    this.initialDisplayName,
    this.initialPreferredUnit,
  });

  @override
  Widget build(BuildContext context) {
    // The wizard is pushed from a plain `MaterialPageRoute` under a
    // `MaterialApp` with no `restorationScopeId`, so nothing above it offers
    // a bucket for [RestorationMixin] to hang the typed answers on. The
    // scope has to sit ABOVE the state that registers into it — a
    // `RootRestorationScope` built by that same state is below itself and
    // feeds nothing, which reads as restoration silently doing nothing.
    return RootRestorationScope(
      restorationId: 'setup_wizard_root',
      child: _SetupWizardBody(
        apiClient: apiClient,
        preferences: preferences,
        settingsSync: settingsSync,
        initialDisplayName: initialDisplayName,
        initialPreferredUnit: initialPreferredUnit,
      ),
    );
  }
}

class _SetupWizardBody extends StatefulWidget {
  final ApiClient apiClient;
  final Preferences preferences;
  final SettingsSyncService? settingsSync;
  final String? initialDisplayName;
  final String? initialPreferredUnit;

  const _SetupWizardBody({
    required this.apiClient,
    required this.preferences,
    this.settingsSync,
    this.initialDisplayName,
    this.initialPreferredUnit,
  });

  @override
  State<_SetupWizardBody> createState() => _SetupWizardBodyState();
}

class _SetupWizardBodyState extends State<_SetupWizardBody>
    with RestorationMixin {
  /// The step ids this run of the wizard walks — [visibleSetupWizardSteps]
  /// with the already-answered ones dropped. Resolved once in [initState]
  /// so the list can't change length under a restored cursor.
  late final List<String> _steps;
  final RestorableInt _stepIndex = RestorableInt(0);

  // Seeded in initState rather than at the declaration: a RestorableValue
  // refuses `value =` before registration, so the seed has to reach it
  // through the constructor, and every seed reads `widget`.
  late final RestorableTextEditingController _displayNameCtl;
  late final RestorableString _preferredUnit;
  final RestorableStringN _primaryGoal = RestorableStringN(null);
  final RestorableString _gender = RestorableString('');
  final RestorableDateTimeN _dateOfBirth = RestorableDateTimeN(null);
  final RestorableTextEditingController _weightCtl =
      RestorableTextEditingController();
  final RestorableBool _healthDataConsent = RestorableBool(false);
  late final RestorableString _privacyDefault;
  // Mobile's notification control is the universal `push_notifications`
  // bag key (no native OS permission prompt to request here — unlike web
  // — so the wizard step sets the preference). Default 'important' matches
  // the bag default registered in settings.md.
  final RestorableString _pushNotifications = RestorableString('important');

  bool _saving = false;

  // Flipped on the first failed Skip/Finish write. Reveals the offline
  // fail-safe exit: the route blocks the back gesture (canPop false) and
  // both regular exits are server writes, so losing connectivity while the
  // wizard is open would otherwise trap the user with no way out but
  // killing the app (issue #246 — basics always work).
  bool _saveFailed = false;

  @override
  void initState() {
    super.initState();
    // The launch flow's privacy chooser already wrote a real answer, so the
    // wizard seeds from it rather than from a hard-coded 'private' it would
    // then write back over the top on Finish.
    _privacyDefault = RestorableString(widget.preferences.privacyDefault);
    _steps = visibleSetupWizardSteps(
      privacyAlreadyChosen: widget.preferences.onboarded,
    );
    _displayNameCtl = RestorableTextEditingController(
      text: widget.initialDisplayName ?? '',
    );
    // Units step default: an explicit prior choice wins, otherwise the
    // device locale decides (mi for US/GB/LR/MM, km elsewhere) instead of
    // hard-coding km for every signup — mirrors web /onboarding's
    // `defaultUnitForLocale(navigator.language)` seed. The raw device
    // locale (not Localizations.localeOf) because the app's resolved
    // locale drops the region subtag the derivation needs.
    final unit = widget.initialPreferredUnit;
    _preferredUnit = RestorableString(
      (unit == 'km' || unit == 'mi')
          ? unit!
          : defaultUnitForLocale(
              WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag(),
            ),
    );
  }

  @override
  String get restorationId => 'setup_wizard';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_stepIndex, 'step');
    registerForRestoration(_displayNameCtl, 'display_name');
    registerForRestoration(_preferredUnit, 'preferred_unit');
    registerForRestoration(_primaryGoal, 'primary_goal');
    registerForRestoration(_gender, 'gender');
    registerForRestoration(_dateOfBirth, 'date_of_birth');
    registerForRestoration(_weightCtl, 'weight');
    registerForRestoration(_healthDataConsent, 'health_consent');
    registerForRestoration(_privacyDefault, 'privacy_default');
    registerForRestoration(_pushNotifications, 'push_notifications');
  }

  @override
  void dispose() {
    _stepIndex.dispose();
    _displayNameCtl.dispose();
    _preferredUnit.dispose();
    _primaryGoal.dispose();
    _gender.dispose();
    _dateOfBirth.dispose();
    _weightCtl.dispose();
    _healthDataConsent.dispose();
    _privacyDefault.dispose();
    _pushNotifications.dispose();
    super.dispose();
  }

  String get _step => _steps[_stepIndex.value];

  bool get _isLastStep => _stepIndex.value == _steps.length - 1;

  void _next() {
    if (!_isLastStep) setState(() => _stepIndex.value += 1);
  }

  void _back() {
    if (_stepIndex.value > 0) setState(() => _stepIndex.value -= 1);
  }

  /// Skip-onboarding header link. Stamps `onboarded_at = now()` only — the
  /// minimum required for the gate to stop re-showing the wizard. Every
  /// other field stays at its existing default. Mirrors web's
  /// `skipOnboarding`.
  Future<void> _skip() async {
    if (_saving) return;
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    try {
      await widget.apiClient.markOnboarded();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('SetupWizardScreen save failed: $e');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveFailed = true;
      });
      showTopBanner(context, l10n.setupSaveError(friendlyError(l10n, e)));
    }
  }

  /// Server-free fail-safe exit (issue #246). Records the dismissal
  /// locally and defers the `onboarded_at` stamp — the home-screen gate
  /// retries [ApiClient.markOnboarded] on each launch until one lands
  /// instead of re-pushing the wizard. Works with zero connectivity.
  Future<void> _finishLater() async {
    await widget.preferences.setSetupWizardDismissed(true);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// Final "Open dashboard". Persists every answer, stamps `onboarded_at`.
  /// Mirrors web's `finishAndExit`. When [createPlan] is set (the goal-keyed
  /// "create my training plan" CTA), pops with the chosen `primary_goal` so
  /// the home screen can route straight into the plan wizard preselected.
  Future<void> _finish({bool createPlan = false}) async {
    if (_saving) return;
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    try {
      // 1. Profile columns + Art 9 consent stamp (the api_client method
      // owns the consent-gating: gender + consent only under the toggle,
      // DOB written unconditionally for the minor-exclusion floor).
      await widget.apiClient.completeOnboarding(
        displayName: _displayNameCtl.value.text,
        preferredUnit: _preferredUnit.value,
        dateOfBirth: _dateOfBirth.value,
        gender: _gender.value,
        healthDataConsent: _healthDataConsent.value,
      );

      // 2. Universal-prefs bag (units + privacy + goal + weight + the
      // consent-gated DOB mirror). Best-effort + locally mirrored where a
      // local pref exists, so the privacy default protects new-run
      // visibility immediately even if the bag write fails offline.
      _preferredUnit.value == 'mi'
          ? widget.preferences.setUseMiles(true)
          : widget.preferences.setUseMiles(false);
      await widget.preferences.setPrivacyDefault(_privacyDefault.value);

      final bag = <String, dynamic>{
        SettingsKeys.preferredUnit: _preferredUnit.value,
        SettingsKeys.privacyDefault: _privacyDefault.value,
        SettingsKeys.pushNotifications: _pushNotifications.value,
      };
      final goal = _primaryGoal.value;
      if (goal != null) bag[SettingsKeys.primaryGoal] = goal;
      final w = parseTypedDecimal(_weightCtl.value.text);
      if (w != null && w > 0) bag[SettingsKeys.bodyWeightKg] = w;
      // DOB mirrors into the bag only under health consent — the bag copy
      // feeds the coach / leaderboard read paths (Art 9 surfaces). The
      // minor-exclusion floor reads the profile column written above, not
      // the bag, so the child-safety write doesn't depend on this mirror.
      final dob = _dateOfBirth.value;
      if (_healthDataConsent.value && dob != null) {
        bag[SettingsKeys.dateOfBirth] = ApiClient.dateOnly(dob);
      }
      // `onboarded_at` is stamped by now, so the wizard can never re-ask —
      // and the goal / notification answers have no local mirror to fall
      // back on. A dropped bag write is therefore lost data, and saying
      // "Welcome" over it would be the app reporting a success it didn't
      // have. Complete the exit either way (trapping the user is worse),
      // but name what didn't land.
      String? bagError;
      try {
        await widget.settingsSync?.updateUniversal(bag);
      } catch (e) {
        debugPrint('onboarding bag write failed: $e');
        bagError = friendlyError(l10n, e);
      }

      if (!mounted) return;
      showTopBanner(
        context,
        bagError == null
            ? l10n.setupWelcomeToast
            : l10n.setupPrefsSaveError(bagError),
        duration: Duration(seconds: bagError == null ? 3 : 6),
      );
      Navigator.of(context).pop(createPlan ? _primaryGoal.value : null);
    } catch (e) {
      debugPrint('SetupWizardScreen save failed: $e');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveFailed = true;
      });
      showTopBanner(context, l10n.setupSaveError(friendlyError(l10n, e)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return PopScope(
      // The gate decides when the wizard shows; letting the OS pop it
      // would leave onboarded_at null and re-trigger it next launch. The
      // gesture isn't dead, though: it steps back through the wizard, and
      // on the first step it offers the same exit the header does.
      canPop: false,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(l10n.setupPageTitle),
          actions: [
            TextButton(
              onPressed: _saving ? null : _skip,
              child: Text(l10n.setupSkip),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              _ProgressDots(step: _stepIndex.value, total: _steps.length),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  child: _buildStep(theme, l10n),
                ),
              ),
              if (_saveFailed) _buildOfflineExit(theme, l10n),
              _buildNav(l10n),
            ],
          ),
        ),
      ),
    );
  }

  /// The OS back gesture / button. Steps back through the wizard rather
  /// than doing nothing; on the first step there is nothing to step back
  /// to, so it offers the exit — confirmed, because the alternative is a
  /// swipe that silently throws away everything typed so far.
  void _onPopInvoked(bool didPop, Object? result) {
    if (didPop || _saving) return;
    if (_stepIndex.value > 0) {
      _back();
      return;
    }
    _confirmExit();
  }

  Future<void> _confirmExit() async {
    final l10n = AppLocalizations.of(context);
    final leave = await confirmDestructive(
      context,
      title: l10n.setupLeaveTitle,
      body: l10n.setupLeaveBody,
      confirmLabel: l10n.setupLeaveConfirm,
      cancelLabel: l10n.setupLeaveStay,
    );
    if (leave && mounted) await _skip();
  }

  Widget _buildStep(ThemeData theme, AppLocalizations l10n) {
    switch (_step) {
      case 'name':
        return _stepShell(
          theme,
          title: l10n.setupNameTitle,
          hint: l10n.setupNameHint,
          child: TextField(
            controller: _displayNameCtl.value,
            maxLength: kDisplayNameMaxLength,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l10n.setupNameLabel,
              hintText: l10n.setupNamePlaceholder,
            ),
          ),
        );
      case 'units':
        return _stepShell(
          theme,
          title: l10n.setupUnitsTitle,
          hint: l10n.setupUnitsHint,
          child: Column(
            children: [
              _OptionCard(
                selected: _preferredUnit.value == 'km',
                title: l10n.setupUnitKm,
                subtitle: l10n.setupUnitKmSample,
                onTap: () => setState(() => _preferredUnit.value = 'km'),
              ),
              _OptionCard(
                selected: _preferredUnit.value == 'mi',
                title: l10n.setupUnitMi,
                subtitle: l10n.setupUnitMiSample,
                onTap: () => setState(() => _preferredUnit.value = 'mi'),
              ),
            ],
          ),
        );
      case 'goal':
        return _stepShell(
          theme,
          title: l10n.setupGoalTitle,
          hint: l10n.setupGoalHint,
          child: Column(
            children: [
              for (final g in primaryGoalValues)
                _OptionCard(
                  selected: _primaryGoal.value == g,
                  title: _goalLabel(l10n, g),
                  onTap: () => setState(() => _primaryGoal.value = g),
                ),
            ],
          ),
        );
      case 'about':
        return _buildAboutYou(theme, l10n);
      case 'run-privacy':
        return _stepShell(
          theme,
          title: l10n.setupPrivacyTitle,
          hint: l10n.setupPrivacyHint,
          child: Column(
            children: [
              _OptionCard(
                selected: _privacyDefault.value == 'private',
                title: l10n.privacyPrivateTitle,
                subtitle: l10n.privacyPrivateSubtitle,
                onTap: () => setState(() => _privacyDefault.value = 'private'),
              ),
              _OptionCard(
                selected: _privacyDefault.value == 'followers',
                title: l10n.privacyFollowersTitle,
                subtitle: l10n.privacyFollowersSubtitle,
                onTap: () =>
                    setState(() => _privacyDefault.value = 'followers'),
              ),
              _OptionCard(
                selected: _privacyDefault.value == 'public',
                title: l10n.privacyPublicTitle,
                subtitle: l10n.privacyPublicSubtitle,
                onTap: () => setState(() => _privacyDefault.value = 'public'),
              ),
            ],
          ),
        );
      case 'notifications':
        return _stepShell(
          theme,
          title: l10n.setupNotificationsTitle,
          hint: l10n.setupNotificationsHint,
          child: Column(
            children: [
              _OptionCard(
                selected: _pushNotifications.value == 'important',
                title: l10n.prefsPushNotifImportant,
                onTap: () =>
                    setState(() => _pushNotifications.value = 'important'),
              ),
              _OptionCard(
                selected: _pushNotifications.value == 'all',
                title: l10n.prefsPushNotifAll,
                onTap: () => setState(() => _pushNotifications.value = 'all'),
              ),
              _OptionCard(
                selected: _pushNotifications.value == 'off',
                title: l10n.prefsPushNotifOff,
                onTap: () => setState(() => _pushNotifications.value = 'off'),
              ),
            ],
          ),
        );
      default:
        return _stepShell(
          theme,
          title: l10n.setupDoneTitle,
          // When a goal was picked the body hosts the primary "Create my
          // training plan" CTA, so the hint names that action; otherwise
          // "Open dashboard" in the nav is the primary and the hint names it.
          hint: _primaryGoal.value == null
              ? l10n.setupDoneHint
              : l10n.setupDoneHintGoal,
          // A goal-keyed CTA into the plan wizard (runner-new discoverability
          // nudge) when the runner picked a goal; a plain finish otherwise.
          child: _primaryGoal.value == null
              ? const SizedBox.shrink()
              : Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: _saving ? null : () => _finish(createPlan: true),
                    child: Text(
                      _saving ? l10n.setupSaving : l10n.setupCreatePlanCta,
                    ),
                  ),
                ),
        );
    }
  }

  Widget _buildAboutYou(ThemeData theme, AppLocalizations l10n) {
    return _stepShell(
      theme,
      title: l10n.setupAboutTitle,
      hint: l10n.setupAboutHint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _gender.value,
            decoration: InputDecoration(labelText: l10n.setupGenderLabel),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(l10n.setupGenderPreferNot),
              ),
              DropdownMenuItem(
                value: 'female',
                child: Text(l10n.setupGenderFemale),
              ),
              DropdownMenuItem(
                value: 'male',
                child: Text(l10n.setupGenderMale),
              ),
            ],
            onChanged: (v) => setState(() => _gender.value = v ?? ''),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _pickDob,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: l10n.setupDobLabel,
                helperText: l10n.setupDobNote,
                helperMaxLines: 3,
              ),
              child: Text(
                _dateOfBirth.value == null
                    ? l10n.setupDobPlaceholder
                    : ApiClient.dateOnly(_dateOfBirth.value!),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _weightCtl.value,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.setupWeightLabel,
              hintText: l10n.setupWeightPlaceholder,
            ),
          ),
          if (_gender.value.isNotEmpty || _dateOfBirth.value != null) ...[
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _healthDataConsent.value,
              onChanged: (v) =>
                  setState(() => _healthDataConsent.value = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text(
                l10n.setupHealthConsent,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _dateOfBirth.value ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - 120),
      lastDate: now,
      initialDatePickerMode: DatePickerMode.year,
    );
    if (!mounted) return;
    if (picked != null) setState(() => _dateOfBirth.value = picked);
  }

  Widget _stepShell(
    ThemeData theme, {
    required String title,
    required String hint,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          hint,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        child,
      ],
    );
  }

  Widget _buildOfflineExit(ThemeData theme, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.setupOfflineHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _saving ? null : _finishLater,
            child: Text(l10n.setupFinishLater),
          ),
        ],
      ),
    );
  }

  /// Whether the current step has an answer yet. Every step can be walked
  /// past unanswered, so a second button that only advances was a Skip and
  /// a Continue doing the identical thing side by side. One button, whose
  /// label names which of the two this press actually is.
  bool get _currentStepAnswered => switch (_step) {
    'name' => _displayNameCtl.value.text.trim().isNotEmpty,
    'goal' => _primaryGoal.value != null,
    'about' =>
      _gender.value.isNotEmpty ||
          _dateOfBirth.value != null ||
          _weightCtl.value.text.trim().isNotEmpty,
    _ => true,
  };

  Widget _buildNav(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          if (_stepIndex.value > 0) ...[
            OutlinedButton(
              onPressed: _saving ? null : _back,
              child: Text(l10n.setupBack),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                if (!_isLastStep)
                  // The two text fields are the only answers typed rather
                  // than tapped, so the label tracks them directly instead
                  // of rebuilding the whole wizard on every keystroke.
                  ListenableBuilder(
                    listenable: Listenable.merge([
                      _displayNameCtl.value,
                      _weightCtl.value,
                    ]),
                    builder: (context, _) => FilledButton(
                      onPressed: _saving ? null : _next,
                      child: Text(
                        _currentStepAnswered
                            ? l10n.setupContinue
                            : l10n.setupSkipStep,
                      ),
                    ),
                  )
                // On the final step, when the runner picked a goal the body
                // hosts the primary "Create my training plan" CTA — so "Open
                // dashboard" demotes to a secondary action here to avoid two
                // competing primary buttons. With no goal, finishing is the
                // one primary action.
                else if (_primaryGoal.value == null)
                  FilledButton(
                    onPressed: _saving ? null : _finish,
                    child: Text(
                      _saving ? l10n.setupSaving : l10n.setupOpenDashboard,
                    ),
                  )
                else
                  OutlinedButton(
                    onPressed: _saving ? null : _finish,
                    child: Text(l10n.setupOpenDashboard),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _goalLabel(AppLocalizations l10n, String g) => switch (g) {
    'weight_loss' => l10n.setupGoalWeightLoss,
    '5k' => l10n.setupGoal5k,
    '10k' => l10n.setupGoal10k,
    'half_marathon' => l10n.setupGoalHalf,
    'marathon' => l10n.setupGoalMarathon,
    _ => l10n.setupGoalGeneralFitness,
  };
}

class _ProgressDots extends StatelessWidget {
  final int step;
  final int total;
  const _ProgressDots({required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(total, (i) {
          final active = i == step;
          final done = i < step;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: active ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: active || done
                  ? theme.colorScheme.primary
                  : theme.dividerColor,
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final bool selected;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const _OptionCard({
    required this.selected,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? theme.colorScheme.primary : theme.dividerColor,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

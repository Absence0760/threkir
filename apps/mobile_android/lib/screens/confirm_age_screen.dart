import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' show UserProfileRow;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../auth_error.dart';
import '../l10n/gen/app_localizations.dart';
import '../legal_links.dart';

/// Whether [profile] records both the Art 8 age affirmation and terms
/// acceptance. A missing row is "not recorded". Same rule as web
/// `consentRecorded` (`apps/web/src/lib/core/auth_confirmation.ts`).
bool consentRecordedOn(UserProfileRow? profile) =>
    profile?.ageConfirmedAt != null && profile?.termsAcceptedAt != null;

/// The GDPR Art 8 consent gate — mobile twin of web `/auth/confirm-age`.
///
/// Pushed by [HomeScreen] over the app whenever the signed-in account's
/// profile does not record both `age_confirmed_at` and `terms_accepted_at`:
/// an Apple or Google sign-in from the sign-in screen (which asks neither),
/// an email account whose post-sign-up stamp could not run, or a row that
/// was never created (issue #1065). There is no way past it except
/// affirming both, which stamps them via `confirm_age_and_terms()`, or
/// signing out.
///
/// Pops `true` once the stamp lands, `false` after signing out.
class ConfirmAgeScreen extends StatefulWidget {
  final ApiClient apiClient;
  const ConfirmAgeScreen({super.key, required this.apiClient});

  @override
  State<ConfirmAgeScreen> createState() => _ConfirmAgeScreenState();
}

class _ConfirmAgeScreenState extends State<ConfirmAgeScreen> {
  bool _confirmAdult = false;
  bool _acceptTerms = false;
  bool _busy = false;
  String? _error;

  late final TapGestureRecognizer _termsTap = TapGestureRecognizer()
    ..onTap = () => openLegalDoc(context, LegalDoc.terms);
  late final TapGestureRecognizer _privacyTap = TapGestureRecognizer()
    ..onTap = () => openLegalDoc(context, LegalDoc.privacy);

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.apiClient.confirmAgeAndTerms();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('ConfirmAgeScreen: confirm_age_and_terms failed: $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '${l10n.confirmAgeRecordError} ${friendlyAuthError(l10n, e)}';
      });
    }
  }

  Future<void> _signOut() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.apiClient.signOut();
    } catch (e) {
      debugPrint('ConfirmAgeScreen: sign-out failed: $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = l10n.settingsAccountSignOutFailed;
      });
      return;
    }
    if (mounted) Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final linkStyle = TextStyle(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
    );
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(l10n.confirmAgeHeading, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(l10n.confirmAgeLede, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: _confirmAdult,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _confirmAdult = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.signUpConfirmAge),
              ),
              CheckboxListTile(
                value: _acceptTerms,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _acceptTerms = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: l10n.signUpAcceptPrefix),
                      TextSpan(
                        text: l10n.legalTerms,
                        style: linkStyle,
                        recognizer: _termsTap,
                      ),
                      TextSpan(text: l10n.signUpAcceptConjunction),
                      TextSpan(
                        text: l10n.legalPrivacy,
                        style: linkStyle,
                        recognizer: _privacyTap,
                      ),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed:
                    _busy || !_confirmAdult || !_acceptTerms ? null : _confirm,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.confirmAgeContinue),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : _signOut,
                child: Text(l10n.settingsAccountSignOut),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import 'l10n/gen/app_localizations.dart';
import 'preferences.dart';
import 'screens/settings_body_metrics_screen.dart';
import 'settings_sync.dart';

/// Heart rate and the food log are kept only with health-data consent
/// (decisions § 2514). The database refuses a food-log write and strips a
/// run's heart rate without it; this file is where the app asks first, so a
/// runner is told why instead of meeting a refusal.

/// Whether the signed-in runner has health-data consent: true / false, or
/// null when it could not be read (offline before this session ever asked).
/// Signed out is false: consent is recorded on the account.
Future<bool?> healthDataConsented(ApiClient? api) async {
  if (api == null) return false;
  try {
    return await api.fetchHealthDataConsented();
  } catch (e) {
    debugPrint('health consent read failed: $e');
    return null;
  }
}

/// Opens the screen where health-data consent is given (Body metrics).
Future<void> openHealthConsent(
  BuildContext context, {
  required ApiClient? api,
  required SettingsSyncService? settingsSync,
  required Preferences? preferences,
}) async {
  final prefs = preferences ?? activePreferences;
  if (prefs == null) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SettingsBodyMetricsScreen(
        api: api,
        settingsSync: settingsSync,
        preferences: prefs,
      ),
    ),
  );
}

/// True when food may be logged now. Without consent on record it explains
/// why, offers the consent screen, and checks again on the way back; nothing
/// is stored unless consent is then on record.
Future<bool> ensureFoodLogConsent(
  BuildContext context, {
  required ApiClient? api,
  required SettingsSyncService? settingsSync,
  required Preferences? preferences,
}) async {
  if (await healthDataConsented(api) == true) return true;
  if (!context.mounted) return false;
  final l10n = AppLocalizations.of(context);
  final give = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          // Long at 2x text on a narrow phone: the content scrolls rather
          // than pushing the actions under the nav bar.
          scrollable: true,
          title: Text(l10n.healthConsentFoodTitle),
          content: Text(l10n.healthConsentFoodBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.healthConsentGiveAction),
            ),
          ],
        ),
      ) ??
      false;
  if (!give || !context.mounted) return false;
  await openHealthConsent(context,
      api: api, settingsSync: settingsSync, preferences: preferences);
  return await healthDataConsented(api) == true;
}

/// The note under a finished run or an import whose heart rate was not kept,
/// with the way to consent.
class HeartRateNotKeptNote extends StatelessWidget {
  const HeartRateNotKeptNote({
    super.key,
    required this.message,
    required this.onGiveConsent,
  });

  final String message;
  final VoidCallback onGiveConsent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Card(
      key: const Key('heart-rate-not-kept'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(Icons.favorite_border,
                      color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(message, style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: onGiveConsent,
                child: Text(l10n.healthConsentGiveAction),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

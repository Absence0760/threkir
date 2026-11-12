import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../coach_assist_consent.dart';
import '../l10n/gen/app_localizations.dart';

/// The athlete's consent to the coach assistant on one coaching link (issue
/// #1215 Phase 4). Off until the athlete turns it on; turning it off
/// withdraws at once. The copy names every lane the drafting endpoint sends.
/// Mirrors web's `CoachAssistConsent.svelte`.
class CoachAssistConsentSwitch extends StatefulWidget {
  const CoachAssistConsentSwitch({
    super.key,
    required this.api,
    required this.link,
    required this.coachName,
    required this.onChanged,
  });

  final ApiClient api;
  final CoachAthleteLink link;
  final String coachName;

  /// The version the server stored, after a save lands.
  final ValueChanged<int?> onChanged;

  @override
  State<CoachAssistConsentSwitch> createState() =>
      _CoachAssistConsentSwitchState();
}

class _CoachAssistConsentSwitchState extends State<CoachAssistConsentSwitch> {
  bool _busy = false;
  bool? _pending;
  bool _failed = false;

  bool get _stored => (widget.link.aiAssistConsentVersion ?? 0) >= 1;

  Future<void> _toggle(bool on) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _pending = on;
      _failed = false;
    });
    try {
      final stored = await widget.api.setCoachAiAssistConsent(
        widget.link.id,
        on ? kCoachAssistConsentVersion : null,
      );
      if (!mounted) return;
      widget.onChanged(stored);
      setState(() {
        _busy = false;
        _pending = null;
      });
    } catch (e) {
      debugPrint('coach_assist_consent: save failed: $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _pending = null;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final name = widget.coachName;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 52, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            key: const ValueKey('coach-assist-consent-toggle'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _pending ?? _stored,
            onChanged: _busy ? null : _toggle,
            title: Text(l10n.coachAssistConsentToggle(name)),
          ),
          ExpansionTile(
            key: const ValueKey('coach-assist-consent-what'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            dense: true,
            title: Text(l10n.coachAssistConsentWhat,
                style: theme.textTheme.bodyMedium),
            children: [
              Text(l10n.coachAssistConsentIntro(name), style: muted),
              const SizedBox(height: 4),
              for (final bullet in [
                l10n.coachAssistConsentBulletThread,
                l10n.coachAssistConsentBulletPlan,
                l10n.coachAssistConsentBulletRuns,
              ])
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 12, bottom: 4),
                  child: Text('• $bullet', style: muted),
                ),
              const SizedBox(height: 4),
              Text(l10n.coachAssistConsentOutro(name), style: muted),
            ],
          ),
          if (_failed)
            Semantics(
              liveRegion: true,
              child: Text(
                l10n.coachAssistConsentFailed,
                key: const ValueKey('coach-assist-consent-error'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

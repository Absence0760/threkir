import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show FieldColumn, SheetScaffold;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth_error.dart';
import '../l10n/gen/app_localizations.dart';
import '../organiser_dispute.dart';
import '../race_service.dart';
import '../rate_limit_message.dart';
import 'form_sheet.dart';
import 'top_banner.dart';

/// Modal report sheet — entry point for the moderation flow on
/// profiles, clubs, routes, comments, club posts, runs, route reviews and
/// direct messages. Mirrors
/// the web `submitReport` surface. The user picks a reason from a
/// fixed list + optional free-text notes, then taps Submit.
///
/// Errors are surfaced inline:
///   - 23505 (duplicate pending report) → "You already have a
///     pending report against this content."
///   - P0001 (rate-limited create_report bucket) → routed through
///     `rateLimitErrorMessage` for the shared localized wording.
///   - Anything else → raw error message.
///
/// On a club or a route, [organiserClubs] loads the runner's verified clubs.
/// When there is one other than [targetClubId] (the club the content belongs
/// to), the sheet adds the organiser dispute reason (decisions § 2441), which
/// files through `submitOrganiserDispute` for the chosen club instead. A
/// failed load only hides that reason.
///
/// Use the static [show] method rather than instantiating directly:
///
///   ```
///   showReportSheet(
///     context,
///     api: api,
///     targetKind: 'user',
///     targetId: user.id,
///   );
///   ```
Future<void> showReportSheet(
  BuildContext context, {
  required ApiClient api,
  required String targetKind,
  required String targetId,
  Future<List<OrganiserClub>> Function()? organiserClubs,
  String? targetClubId,
}) async {
  // Capture the host context so the success banner survives the
  // modal's Navigator.pop — Overlay.of on a popped sheet's context
  // returns the same overlay, but the widget itself is unmounted by
  // the time the banner inserts.
  return showFormSheet<void>(
    context,
    builder: (ctx) => _ReportSheet(
      api: api,
      targetKind: targetKind,
      targetId: targetId,
      organiserClubs: organiserClubs,
      targetClubId: targetClubId,
      onSuccess: () {
        Navigator.of(ctx).pop();
        showTopBanner(
          context,
          AppLocalizations.of(context).reportSuccess,
        );
      },
    ),
  );
}

/// The ordered reason VALUE keys shown in the picker. These mirror the
/// web `ReportReason` union; the migration's CHECK constraint rejects
/// anything outside this set so keeping them in sync is load-bearing.
/// The human label for each is resolved per-locale at render time. The
/// organiser dispute reason is not here: it is offered only to a verified
/// club's owner or admin, below the general reasons.
const _reasonKeys = <String>[
  'spam',
  'harassment',
  'inappropriate',
  'impersonation',
  'other',
];

String _reasonLabel(AppLocalizations l10n, String key) {
  switch (key) {
    case 'spam':
      return l10n.reportReasonSpam;
    case 'harassment':
      return l10n.reportReasonHarassment;
    case 'inappropriate':
      return l10n.reportReasonInappropriate;
    case 'impersonation':
      return l10n.reportReasonImpersonation;
    default:
      return l10n.reportReasonOther;
  }
}

class _ReportSheet extends StatefulWidget {
  final ApiClient api;
  final String targetKind;
  final String targetId;
  final Future<List<OrganiserClub>> Function()? organiserClubs;
  final String? targetClubId;
  final VoidCallback onSuccess;

  const _ReportSheet({
    required this.api,
    required this.targetKind,
    required this.targetId,
    required this.onSuccess,
    this.organiserClubs,
    this.targetClubId,
  });

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  String _reason = 'spam';
  final _notesCtl = TextEditingController();
  bool _busy = false;
  String? _error;
  List<OrganiserClub> _disputeClubs = const [];
  String? _disputeClubId;

  @override
  void initState() {
    super.initState();
    _loadOrganiserClubs();
  }

  Future<void> _loadOrganiserClubs() async {
    final load = widget.organiserClubs;
    if (load == null ||
        !kOrganiserDisputeSheetKinds.contains(widget.targetKind)) {
      return;
    }
    try {
      final clubs = organiserDisputeClubsFor(await load(), widget.targetClubId);
      if (!mounted) return;
      setState(() {
        _disputeClubs = clubs;
        _disputeClubId = clubs.isEmpty ? null : clubs.first.id;
      });
    } catch (e) {
      debugPrint('report sheet: organiser clubs load failed: $e');
    }
  }

  @override
  void dispose() {
    _notesCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final notes = _notesCtl.text.trim();
      if (_reason == kOrganiserDisputeReason) {
        await widget.api.submitOrganiserDispute(
          targetKind: widget.targetKind,
          targetId: widget.targetId,
          clubId: _disputeClubId!,
          notes: notes.isEmpty ? null : notes,
        );
      } else {
        await widget.api.submitReport(
          targetKind: widget.targetKind,
          targetId: widget.targetId,
          reason: _reason,
          notes: notes.isEmpty ? null : notes,
        );
      }
      if (!mounted) return;
      widget.onSuccess();
    } on PostgrestException catch (e) {
      debugPrint('report submit failed: $e');
      if (!mounted) return;
      if (e.code == '23505') {
        setState(() =>
            _error = AppLocalizations.of(context).reportErrDuplicate);
        return;
      }
      if (e.code == '42501' && _reason == kOrganiserDisputeReason) {
        setState(() =>
            _error = AppLocalizations.of(context).reportErrNotOrganiser);
        return;
      }
      final l10n = AppLocalizations.of(context);
      final friendly =
          rateLimitErrorMessage(l10n, code: e.code, message: e.message);
      setState(() => _error = friendly ?? friendlyError(l10n, e));
    } catch (e) {
      debugPrint('report submit failed: $e');
      if (mounted) {
        setState(() => _error = friendlyError(AppLocalizations.of(context), e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SheetDiscardGuard(
        isDirty: () => _notesCtl.text.trim().isNotEmpty,
        child: _sheet(context),
      );

  Widget _sheet(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return SheetScaffold(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      actions: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
              child: Text(l10n.reportCancel),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.reportSubmit),
            ),
          ),
        ],
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _title(l10n, widget.targetKind),
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.reportDisclaimer,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text(l10n.reportReason, style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          for (final key in _reasonKeys)
            RadioListTile<String>(
              value: key,
              groupValue: _reason,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _reason = v ?? _reason),
              title: Text(_reasonLabel(l10n, key)),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          if (_disputeClubs.isNotEmpty) ...[
            const Divider(height: 16),
            RadioListTile<String>(
              key: const Key('report-organiser-dispute'),
              value: kOrganiserDisputeReason,
              groupValue: _reason,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _reason = v ?? _reason),
              title: Text(l10n.reportReasonOrganiserDispute),
              subtitle: Text(l10n.reportReasonOrganiserDisputeHint),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            if (_reason == kOrganiserDisputeReason && _disputeClubs.length == 1)
              Text(
                l10n.reportOrganiserDisputeFor(_disputeClubs.first.name),
                style: theme.textTheme.bodySmall,
              ),
          ],
          const SizedBox(height: 12),
          FieldColumn(children: [
            if (_reason == kOrganiserDisputeReason && _disputeClubs.length > 1)
              DropdownButtonFormField<String>(
                key: const Key('report-organiser-club'),
                initialValue: _disputeClubId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.reportOrganiserDisputeClubLabel,
                ),
                items: [
                  for (final c in _disputeClubs)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _disputeClubId = v),
              ),
            TextField(
              controller: _notesCtl,
              maxLines: 3,
              maxLength: _reason == kOrganiserDisputeReason
                  ? kOrganiserDisputeNotesMax
                  : null,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: l10n.reportNotesLabel,
              ),
            ),
          ]),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      ),
    );
  }

  static String _title(AppLocalizations l10n, String kind) {
    switch (kind) {
      case 'user':
        return l10n.reportTitleUser;
      case 'club':
        return l10n.reportTitleClub;
      case 'route':
        return l10n.reportTitleRoute;
      case 'comment':
        return l10n.reportTitleComment;
      case 'club_post':
        return l10n.reportTitlePost;
      case 'run':
        return l10n.reportTitleRun;
      case 'route_review':
        return l10n.reportTitleReview;
      case 'direct_message':
        return l10n.reportTitleMessage;
      case 'group_invite':
        return l10n.reportTitleGroupInvite;
    }
    return l10n.reportTitleContent;
  }
}

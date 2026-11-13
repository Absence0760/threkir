import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show ListCard;

import '../l10n/gen/app_localizations.dart';
import '../social_service.dart';

/// The club's official verification, read-only, for the club's owner and
/// admins (issue #1190 § 2, decisions § 2398). Requesting, proving the domain
/// and the review all happen on the web; this says where the club stands.
class ClubVerificationStatusCard extends StatefulWidget {
  final SocialService social;
  final String clubId;
  final bool isVerified;

  const ClubVerificationStatusCard({
    super.key,
    required this.social,
    required this.clubId,
    required this.isVerified,
  });

  @override
  State<ClubVerificationStatusCard> createState() =>
      _ClubVerificationStatusCardState();
}

class _ClubVerificationStatusCardState
    extends State<ClubVerificationStatusCard> {
  List<ClubVerificationRequestRow>? _rows;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.social.fetchClubVerificationRequests(widget.clubId);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _failed = false;
      });
    } catch (e) {
      debugPrint('club verification status load failed: $e');
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = _rows;
    final String line;
    if (_failed) {
      line = l10n.clubVerificationStatusLoadFailed;
    } else if (rows == null) {
      line = '';
    } else {
      line = clubVerificationStatusLine(l10n, rows, isVerified: widget.isVerified);
    }
    return ListCard.row(
      key: const Key('club-verification-status'),
      leading: Icon(
        widget.isVerified ? Icons.verified : Icons.verified_outlined,
      ),
      title: l10n.clubVerificationStatusTitle,
      subtitle: line.isEmpty
          ? l10n.clubVerificationStatusWebHint
          : '$line\n${l10n.clubVerificationStatusWebHint}',
      subtitleMaxLines: 4,
      trailing: _failed
          ? IconButton(
              tooltip: l10n.clubVerificationStatusRetry,
              icon: const Icon(Icons.refresh),
              onPressed: _load,
            )
          : null,
    );
  }
}

/// One line for where a club's verification stands: the approval in force,
/// the pending request, or the most recent one that ended.
String clubVerificationStatusLine(
  AppLocalizations l10n,
  List<ClubVerificationRequestRow> rows, {
  required bool isVerified,
}) {
  final sorted = [...rows]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final live = sorted
      .where((r) => r.status == 'pending' || r.status == 'approved')
      .firstOrNull;
  final shown = live ?? sorted.firstOrNull;
  if (shown == null) {
    return isVerified
        ? l10n.clubVerificationStatusVerifiedLegacy
        : l10n.clubVerificationStatusNone;
  }
  if (isVerified && shown.status != 'approved') {
    return l10n.clubVerificationStatusVerifiedLegacy;
  }
  return _statusLine(l10n, shown);
}

String _statusLine(AppLocalizations l10n, ClubVerificationRequestRow r) {
  switch (r.status) {
    case 'approved':
      return l10n.clubVerificationStatusVerified(r.organisation, r.domain);
    case 'pending':
      return r.proofVerifiedAt != null
          ? l10n.clubVerificationStatusPendingProof(r.organisation)
          : l10n.clubVerificationStatusPending(r.organisation);
    case 'rejected':
      return l10n.clubVerificationStatusRejected(r.decisionReason ?? '');
    case 'revoked':
      return l10n.clubVerificationStatusRevoked(r.closeReason ?? '');
    case 'lapsed':
      return l10n.clubVerificationStatusLapsed;
    case 'withdrawn':
      return l10n.clubVerificationStatusWithdrawn;
    default:
      return l10n.clubVerificationStatusNone;
  }
}

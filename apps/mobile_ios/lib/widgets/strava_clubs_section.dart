import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show IdentityAvatar;

import '../l10n/gen/app_localizations.dart';
import '../settings_destination.dart';
import '../undo_queue.dart';
import 'top_banner.dart';
import 'undo_bar.dart';

/// The sentence for each link refusal, shared by the section and the
/// new-club form's link-after-create.
String stravaClubLinkErrorMessage(
    AppLocalizations l10n, StravaClubLinkError reason) {
  switch (reason) {
    case StravaClubLinkError.stravaAdminRequired:
      return l10n.stravaClubsErrAdminRequired;
    case StravaClubLinkError.stravaClubAlreadyLinked:
      return l10n.stravaClubsErrAlreadyLinked;
    case StravaClubLinkError.notClubAdmin:
      return l10n.stravaClubsErrNotClubAdmin;
    case StravaClubLinkError.reconnect:
      return l10n.stravaClubsErrReconnect;
    case StravaClubLinkError.generic:
      return l10n.stravaClubsErrGeneric;
  }
}

enum StravaClubsPhase { loading, error, done }

/// The runner's own Strava clubs for the life of the clubs screen
/// (decisions § 1959). Owned by the screen rather than the section so a tab
/// switch or a reload of the club lists does not ask Strava again — the list
/// is rate-limited per caller.
class StravaClubsController extends ChangeNotifier {
  StravaClubsController(this.api);

  final ApiClient api;
  StravaClubsPhase phase = StravaClubsPhase.loading;
  StravaClubsResult? result;
  bool busy = false;
  bool _disposed = false;

  List<StravaClub> get clubs => result?.clubs ?? const [];

  Future<void> load() async {
    phase = StravaClubsPhase.loading;
    _notify();
    try {
      result = await api.fetchMyStravaClubs();
      phase = StravaClubsPhase.done;
    } catch (e) {
      debugPrint('strava clubs: load failed: ${safeErrorLabel(e)}');
      phase = StravaClubsPhase.error;
    }
    _notify();
  }

  /// Point [stravaClubId]'s row at [linked] (null clears it). A Threkir club
  /// is linked to at most one Strava club, so linking it here clears it from
  /// any other row that still showed it.
  void setLinked(int stravaClubId, StravaLinkedClub? linked) {
    final r = result;
    if (r == null) return;
    result = StravaClubsResult(r.status, [
      for (final c in r.clubs)
        if (c.stravaClubId == stravaClubId)
          c.withLinkedClub(linked)
        else if (linked != null && c.linkedClub?.id == linked.id)
          c.withLinkedClub(null)
        else
          c,
    ]);
    _notify();
  }

  void setBusy(bool value) {
    busy = value;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool get mounted => !_disposed;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// "Your Strava clubs" on My clubs — the mobile twin of web's
/// `StravaClubsSection.svelte`. Renders nothing while loading and for a
/// runner who is not connected, which is most runners; a failed load shows
/// its own error with a retry and never touches the club lists above it.
class StravaClubsSection extends StatefulWidget {
  const StravaClubsSection({
    super.key,
    required this.controller,
    required this.adminClubs,
    required this.onSetUp,
    required this.onOpenClub,
  });

  final StravaClubsController controller;

  /// The Threkir clubs the viewer owns or administers — the only ones a
  /// Strava club can be linked to, and the only links they may clear.
  final List<ClubRow> adminClubs;
  final void Function(StravaClub club) onSetUp;
  final void Function(String slug) onOpenClub;

  @override
  State<StravaClubsSection> createState() => _StravaClubsSectionState();
}

class _StravaClubsSectionState extends State<StravaClubsSection> {
  StravaClubsController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChange);
  }

  @override
  void didUpdateWidget(StravaClubsSection old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChange);
      widget.controller.addListener(_onChange);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _pickAndLink(StravaClub club) async {
    final l10n = AppLocalizations.of(context);
    final target = await showDialog<ClubRow>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.stravaClubsPickClubLabel),
        children: [
          for (final c in widget.adminClubs)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(c),
              child: Text(c.name),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.commonCancel),
          ),
        ],
      ),
    );
    if (target == null || !mounted || _c.busy) return;
    _c.setBusy(true);
    try {
      await _c.api.linkStravaClub(target.id, club.stravaClubId);
      _c.setLinked(
        club.stravaClubId,
        StravaLinkedClub(id: target.id, slug: target.slug, name: target.name),
      );
      if (mounted) showTopBanner(context, l10n.stravaClubsLinked(target.name));
    } catch (e) {
      debugPrint('strava clubs: link failed: ${safeErrorLabel(e)}');
      final reason = e is StravaClubLinkFailure
          ? e.reason
          : StravaClubLinkError.generic;
      if (mounted) {
        showTopBanner(context, stravaClubLinkErrorMessage(l10n, reason));
      }
    } finally {
      _c.setBusy(false);
    }
  }

  void _unlink(StravaClub club) {
    final before = club.linkedClub;
    if (before == null) return;
    final l10n = AppLocalizations.of(context);
    final controller = _c;
    controller.setLinked(club.stravaClubId, null);
    deferDestructive(
      context,
      DeferredDestruction(
        message: l10n.stravaClubsUnlinked(before.name),
        commit: () => controller.api.unlinkStravaClub(before.id),
        restore: () {
          if (controller.mounted) {
            controller.setLinked(club.stravaClubId, before);
          }
        },
        onCommitError: (e) {
          debugPrint('strava clubs: unlink failed: ${safeErrorLabel(e)}');
          if (mounted) showTopBanner(context, l10n.stravaClubsErrUnlink);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final phase = _c.phase;
    final status = _c.result?.status;

    final List<Widget> body;
    if (phase == StravaClubsPhase.error) {
      body = [
        Text(l10n.stravaClubsLoadError, style: _note(theme)),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: _c.load,
            child: Text(l10n.errorStateRetry),
          ),
        ),
      ];
    } else if (phase == StravaClubsPhase.done &&
        status == StravaClubsStatus.reconnectRequired) {
      body = [
        Text(l10n.stravaClubsReconnectText, style: _note(theme)),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton(
            onPressed: () => openSettings(SettingsDestination.integrations),
            child: Text(l10n.stravaClubsReconnect),
          ),
        ),
      ];
    } else if (phase == StravaClubsPhase.done &&
        status == StravaClubsStatus.connected) {
      final clubs = _c.clubs;
      body = [
        Text(l10n.stravaClubsIntro, style: _note(theme)),
        const SizedBox(height: 8),
        if (clubs.isEmpty)
          Text(l10n.stravaClubsEmpty, style: _note(theme))
        else
          for (final club in clubs) ...[
            _row(context, club),
            const SizedBox(height: 8),
          ],
      ];
    } else {
      return const SizedBox.shrink();
    }

    return Padding(
      key: const ValueKey('strava-clubs'),
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.stravaClubsHeading,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 4),
          ...body,
        ],
      ),
    );
  }

  TextStyle? _note(ThemeData theme) => theme.textTheme.bodyMedium
      ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

  Widget _row(BuildContext context, StravaClub club) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final location = stravaClubLocation(
        city: club.city, state: club.state, country: club.country);
    final linked = club.linkedClub;
    final busy = _c.busy;
    final adminIds = {for (final c in widget.adminClubs) c.id};

    final List<Widget> actions;
    if (linked != null) {
      actions = [
        OutlinedButton(
          onPressed: () => widget.onOpenClub(linked.slug),
          child: Text(l10n.stravaClubsViewOnThrekir(linked.name)),
        ),
        if (adminIds.contains(linked.id))
          TextButton(
            onPressed: busy ? null : () => _unlink(club),
            child: Text(l10n.stravaClubsUnlink),
          ),
      ];
    } else if (club.viewerIsAdmin == false) {
      actions = [Text(l10n.stravaClubsAdminOnly, style: _note(theme))];
    } else {
      actions = [
        FilledButton(
          onPressed: busy ? null : () => widget.onSetUp(club),
          child: Text(l10n.stravaClubsSetUp),
        ),
        if (widget.adminClubs.isNotEmpty)
          OutlinedButton(
            onPressed: busy ? null : () => _pickAndLink(club),
            child: Text(l10n.stravaClubsLinkToMine),
          ),
      ];
    }

    return Container(
      key: ValueKey('strava-club-${club.stravaClubId}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Seeded, like web: Strava's image CDN is not drawn there
              // (CSP), and both clients show the same face for a club.
              IdentityAvatar(
                  seed: '${club.stravaClubId}', name: club.name, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      club.name,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (location.isNotEmpty || club.memberCount != null)
                      Text(
                        [
                          if (location.isNotEmpty) location,
                          if (club.memberCount != null)
                            l10n.clubsMemberCount(club.memberCount!),
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          ),
        ],
      ),
    );
  }
}

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../local_run_store.dart';
import '../offline_sync_store.dart';

/// Persistent disclosure for offline-store rows that haven't reached the
/// server. Rendered as a function of the stores' pending state, NOT of
/// connectivity: a push rejected while online (RLS denial, 500, expired
/// token, timeout) leaves the row pending with the device online, and the
/// old `_isOnline`-gated banners showed nothing for exactly that case
/// (issue #666 U2). Mirrors the runs surface's always-on unsynced badge.
///
/// Renders nothing when nothing is pending. Pending while offline shows the
/// "saved on this device" copy; pending while online means at least one push
/// failed, so the copy says so and offers a Retry wired to
/// [OfflineSyncStore.syncWithServer] on every store that still has rows.
///
/// Runs are not an [OfflineSyncStore] — their queue is [LocalRunStore] and
/// their drain is `SyncService` — so they come in through [runStore] and
/// [onRetryRuns]. Unsynced runs count with everything else pending; a parked
/// run gets its own line, because retrying will not move it.
class PendingSyncBanner extends StatefulWidget {
  final ApiClient? api;
  final bool isOnline;
  final List<OfflineSyncStore<SyncEntry>> stores;
  final LocalRunStore? runStore;
  final Future<void> Function()? onRetryRuns;

  const PendingSyncBanner({
    super.key,
    required this.api,
    required this.isOnline,
    required this.stores,
    this.runStore,
    this.onRetryRuns,
  });

  @override
  State<PendingSyncBanner> createState() => _PendingSyncBannerState();
}

class _PendingSyncBannerState extends State<PendingSyncBanner> {
  bool _retrying = false;

  Future<void> _retry() async {
    final api = widget.api;
    if (api == null || _retrying) return;
    setState(() => _retrying = true);
    try {
      for (final store in widget.stores) {
        if (store.hasPending) await store.syncWithServer(api);
      }
      final runs = widget.runStore;
      final retryRuns = widget.onRetryRuns;
      if (runs != null && retryRuns != null && runs.unsyncedCount > 0) {
        await retryRuns();
      }
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        ...widget.stores,
        if (widget.runStore != null) widget.runStore!,
      ]),
      builder: (context, _) {
        var pending = widget.runStore?.unsyncedCount ?? 0;
        for (final s in widget.stores) {
          pending += s.pendingCount;
        }
        final parked = widget.runStore?.blockedCount ?? 0;
        if (pending == 0 && parked == 0) return const SizedBox.shrink();
        final theme = Theme.of(context);
        final l10n = AppLocalizations.of(context);
        final canRetry =
            pending > 0 && widget.isOnline && widget.api?.userId != null;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: theme.colorScheme.surfaceContainerHigh,
          // The action sits on its own end-aligned line rather than at the
          // tail of the message row: a `TextButton` takes its intrinsic width
          // first, so a long German / French label ("Erneut versuchen") starves
          // the `Expanded` message down to a few pixels and the banner grows to
          // a column of single characters (decisions § 486, § 488).
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (pending > 0)
                Row(
                  children: [
                    Icon(
                      canRetry ? Icons.sync_problem : Icons.cloud_off,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        canRetry
                            ? l10n.pendingSyncFailed(pending)
                            : l10n.pendingSyncOffline(pending),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              if (pending > 0 && parked > 0) const SizedBox(height: 4),
              if (parked > 0)
                Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 16,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.historySyncBlocked(parked),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              if (canRetry)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: _retrying
                      ? const Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : TextButton(
                          onPressed: _retry,
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(l10n.pendingSyncRetry),
                        ),
                ),
            ],
          ),
        );
      },
    );
  }
}

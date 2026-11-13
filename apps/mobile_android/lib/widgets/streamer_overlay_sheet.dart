import 'package:api_client/api_client.dart' show LiveOverlay;
import 'package:core_models/core_models.dart' show DistanceUnit;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:ui_kit/ui_kit.dart' show ListSkeleton, SheetScaffold;
import 'package:url_launcher/url_launcher.dart';

import '../l10n/gen/app_localizations.dart';
import '../rate_limit_message.dart';
import '../streamer_overlay.dart';
import 'confirm_destructive.dart';

/// Opens the streamer-overlay sheet from the live-share sheet: create, copy,
/// replace and turn off the OBS browser-source link, and pick the delay the
/// server holds pings back by (decisions § 2265). Mirrors web's Settings card.
Future<void> showStreamerOverlaySheet(
  BuildContext context, {
  required StreamerOverlayController controller,
  required String webBase,
  DistanceUnit? unit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => StreamerOverlaySheet(
      controller: controller,
      webBase: webBase,
      unit: unit,
    ),
  );
}

class StreamerOverlaySheet extends StatefulWidget {
  final StreamerOverlayController controller;
  final String webBase;
  final DistanceUnit? unit;

  /// Opens a URL in the browser; tests pass a fake.
  final Future<bool> Function(Uri url) openUrl;

  const StreamerOverlaySheet({
    super.key,
    required this.controller,
    required this.webBase,
    this.unit,
    this.openUrl = _launchExternal,
  });

  @override
  State<StreamerOverlaySheet> createState() => _StreamerOverlaySheetState();
}

Future<bool> _launchExternal(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

class _StreamerOverlaySheetState extends State<StreamerOverlaySheet> {
  bool _loading = true;
  bool _loadFailed = false;
  bool _busy = false;
  LiveOverlay? _overlay;
  // Inline rather than a top banner: the sheet sits over the run screen, and
  // a result line inside it is where the eye already is.
  String? _notice;
  bool _noticeIsError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final overlay = await widget.controller.load();
      if (mounted) setState(() => _overlay = overlay);
    } catch (e) {
      debugPrint('streamer overlay: load failed: $e');
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openWebSettings() async {
    final l10n = AppLocalizations.of(context);
    final url = streamerOverlayPrivacySettingsUrl(widget.webBase);
    var ok = false;
    try {
      ok = await widget.openUrl(url);
    } catch (e) {
      debugPrint('streamer overlay: opening $url failed: $e');
    }
    if (!ok && mounted) _say(l10n.legalCouldNotOpen('$url'), error: true);
  }

  void _say(String text, {bool error = false}) {
    setState(() {
      _notice = text;
      _noticeIsError = error;
    });
  }

  String _failure(Object e, String fallback) {
    final l10n = AppLocalizations.of(context);
    if (isLiveOverlayDisabledError(e)) return l10n.streamerOverlayUnavailable;
    if (e is PostgrestException) {
      final friendly =
          rateLimitErrorMessage(l10n, code: e.code, message: e.message);
      if (friendly != null) return friendly;
    }
    return fallback;
  }

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final token = await widget.controller.create();
      final fresh = await _reloadAfterCreate(token);
      if (!mounted) return;
      setState(() {
        _overlay = fresh ??
            _overlay?.copyWith(token: token) ??
            LiveOverlay(
              token: token,
              delaySeconds: 60,
              showMap: false,
              showHeartRate: false,
            );
      });
      _say(l10n.streamerOverlayCreated);
    } catch (e) {
      debugPrint('streamer overlay: create failed: $e');
      if (mounted) {
        _say(_failure(e, l10n.streamerOverlayCreateFailed), error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The settings the new token carries, read back from the server; null
  /// when that read fails, so the new link still shows.
  Future<LiveOverlay?> _reloadAfterCreate(String token) async {
    try {
      final fresh = await widget.controller.load();
      return fresh?.token == token ? fresh : null;
    } catch (e) {
      debugPrint('streamer overlay: reload after create failed: $e');
      return null;
    }
  }

  Future<void> _confirmReplace() async {
    final l10n = AppLocalizations.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.streamerOverlayReplaceTitle,
      body: l10n.streamerOverlayReplaceMessage,
      confirmLabel: l10n.streamerOverlayReplace,
    );
    if (ok && mounted) await _create();
  }

  Future<void> _confirmRevoke() async {
    final l10n = AppLocalizations.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.streamerOverlayRevokeTitle,
      body: l10n.streamerOverlayRevokeMessage,
      confirmLabel: l10n.streamerOverlayRevoke,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.controller.revoke();
      if (!mounted) return;
      setState(() => _overlay = null);
      _say(l10n.streamerOverlayRevoked);
    } catch (e) {
      debugPrint('streamer overlay: revoke failed: $e');
      if (mounted) _say(l10n.streamerOverlayRevokeFailed, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setDelay(int seconds) async {
    final l10n = AppLocalizations.of(context);
    final current = _overlay;
    if (current == null || current.delaySeconds == seconds) return;
    setState(() => _busy = true);
    try {
      final saved = await widget.controller.setDelay(seconds);
      if (!mounted) return;
      setState(() => _overlay = saved);
      if (saved != null) _say(l10n.streamerOverlayDelaySaved);
    } catch (e) {
      debugPrint('streamer overlay: delay failed: $e');
      if (mounted) {
        _say(_failure(e, l10n.streamerOverlayDelayFailed), error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(String url) async {
    final l10n = AppLocalizations.of(context);
    try {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) _say(l10n.streamerOverlayCopied);
    } catch (e) {
      debugPrint('streamer overlay: copy failed: $e');
      if (mounted) _say(l10n.streamerOverlayCopyFailed, error: true);
    }
  }

  String _delayLabel(AppLocalizations l10n, int seconds) {
    if (seconds == 0) return l10n.streamerOverlayDelayNone;
    if (seconds < 60) return l10n.streamerOverlayDelaySeconds(seconds);
    return l10n.streamerOverlayDelayMinutes(seconds ~/ 60);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final overlay = _overlay;

    final List<Widget> body;
    if (_loading) {
      body = [
        ListSkeleton.section(label: l10n.commonLoading, rows: 3),
      ];
    } else if (_loadFailed) {
      body = [
        Text(
          l10n.streamerOverlayLoadFailed,
          key: const ValueKey('streamer-overlay-load-error'),
          style: TextStyle(color: theme.colorScheme.error),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const ValueKey('streamer-overlay-retry'),
          onPressed: _load,
          child: Text(l10n.streamerOverlayRetry),
        ),
      ];
    } else if (overlay == null) {
      body = [
        FilledButton.icon(
          key: const ValueKey('streamer-overlay-create'),
          onPressed: _busy ? null : _create,
          icon: const Icon(Icons.add_link),
          label: Text(l10n.streamerOverlayCreate),
        ),
      ];
    } else {
      final url =
          streamerOverlayUrl(widget.webBase, overlay.token, unit: widget.unit);
      body = [
        Text(l10n.streamerOverlayUrlLabel, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        SelectableText(
          url,
          key: const ValueKey('streamer-overlay-url'),
          style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const ValueKey('streamer-overlay-copy'),
              onPressed: () => _copy(url),
              icon: const Icon(Icons.copy),
              label: Text(l10n.streamerOverlayCopy),
            ),
            OutlinedButton(
              key: const ValueKey('streamer-overlay-replace'),
              onPressed: _busy ? null : _confirmReplace,
              child: Text(l10n.streamerOverlayReplace),
            ),
            TextButton(
              key: const ValueKey('streamer-overlay-revoke'),
              onPressed: _busy ? null : _confirmRevoke,
              style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error),
              child: Text(l10n.streamerOverlayRevoke),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(l10n.streamerOverlayDelayLabel, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(l10n.streamerOverlayDelayHelp, style: muted),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final seconds in streamerOverlayDelayPresets)
              ChoiceChip(
                key: ValueKey('streamer-overlay-delay-$seconds'),
                label: Text(_delayLabel(l10n, seconds)),
                selected: overlay.delaySeconds == seconds,
                onSelected: _busy ? null : (_) => _setDelay(seconds),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(l10n.streamerOverlayMapHeartRateNote, style: muted),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey('streamer-overlay-web-settings'),
            onPressed: _openWebSettings,
            icon: const Icon(Icons.open_in_new),
            label: Text(l10n.streamerOverlayOpenWebSettings),
          ),
        ),
      ];
    }

    return SheetScaffold(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.streamerOverlayTitle,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 4),
          Text(l10n.streamerOverlayIntro, style: muted),
          const SizedBox(height: 12),
          ...body,
          if (_notice != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                _notice!,
                key: const ValueKey('streamer-overlay-notice'),
                style: TextStyle(
                  color: _noticeIsError ? theme.colorScheme.error : null,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

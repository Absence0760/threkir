import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth_error.dart' show friendlyError;
import '../event_photo_window.dart';
import '../exif_strip.dart';
import '../l10n/gen/app_localizations.dart';
import '../preferences.dart' show formatDistanceForPref;
import '../social_service.dart' show RecentRunRow;
import '../undo_queue.dart';
import 'photo_lightbox.dart';
import 'top_banner.dart';
import 'undo_bar.dart';

/// Mirrors the web event-detail Photos section (persona #49): the
/// multi-attendee gallery of photos tagged to one event instance, readable
/// even when the underlying run is private (`fetchEventPhotos` RLS). Any
/// signed-in viewer can add: a finisher attaches to their own event run
/// (`myEventRunId`) with zero extra taps, everyone else picks one of their
/// runs that started inside the occurrence's photo window — the database
/// refuses any other (#1150). A steward (club owner / admin / event
/// organiser, or the event's host) also posts with no run, and hides any
/// photo; a hidden photo leaves the gallery for everyone else. Read-only for
/// anon viewers.
class EventPhotos extends StatefulWidget {
  final ApiClient api;
  final String eventId;
  final DateTime instanceStart;

  /// The viewer's own finished run for this event, if any — a photo from a
  /// finisher attaches straight to it (web's `myEventRunId` fast path).
  final String? myEventRunId;

  /// Whether the viewer may add a photo (signed in). Anon viewers see the
  /// gallery read-only.
  final bool canAdd;

  /// The viewer's runs inside this occurrence's photo window, for the
  /// non-finisher "which run is this from?" picker. Injected so the widget
  /// stays free of `SocialService`.
  final Future<List<RecentRunRow>> Function() fetchWindowRuns;

  /// The signed-in viewer, so their own photos carry a delete action.
  final String? currentUserId;

  /// Test seam for "now" — whether a steward's run-less upload is open yet.
  final DateTime Function()? clock;

  /// Test seam — inject the gallery-pick source so the picker's error paths
  /// (permission denial, generic failure) are drivable without a real photo
  /// picker. Defaults to the live [ImagePicker] gallery pick.
  final Future<XFile?> Function()? pickImageOverride;

  const EventPhotos({
    super.key,
    required this.api,
    required this.eventId,
    required this.instanceStart,
    required this.canAdd,
    required this.fetchWindowRuns,
    this.myEventRunId,
    this.currentUserId,
    this.pickImageOverride,
    this.clock,
  });

  @override
  State<EventPhotos> createState() => _EventPhotosState();
}

class _EventPhotosState extends State<EventPhotos> {
  final _picker = ImagePicker();
  bool _loading = true;
  bool _uploading = false;
  bool _loadFailed = false;
  bool _steward = false;
  String? _busyId;
  List<EventPhotoView> _photos = const [];
  final Map<String, _SignedEntry> _signedUrls = <String, _SignedEntry>{};
  static const int _signedUrlTtlSeconds = 15 * 60;
  static const int _signedUrlRefreshAheadSeconds = 5 * 60;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<String> _pathsToSign(List<EventPhotoView> ps) {
    final out = <String>[];
    for (final p in ps) {
      out.add(p.storagePath);
      final t = p.thumb512Path;
      if (t != null && t.isNotEmpty) out.add(t);
    }
    return out;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    if (widget.canAdd) {
      try {
        final steward = await widget.api.canStewardEventPhotos(widget.eventId);
        if (mounted) _steward = steward;
      } catch (e) {
        debugPrint('event-photos steward check failed: $e');
      }
    }
    try {
      final ps = await widget.api
          .fetchEventPhotos(widget.eventId, widget.instanceStart);
      await _signPaths(_pathsToSign(ps));
      if (!mounted) return;
      setState(() {
        _photos = ps;
        _loadFailed = false;
        _loading = false;
      });
    } catch (e) {
      debugPrint('event-photos load failed: $e');
      if (!mounted) return;
      setState(() {
        _loadFailed = true;
        _loading = false;
      });
    }
  }

  bool get _stewardCanPost =>
      _steward &&
      hasEventPhotoWindowOpened(
          widget.instanceStart, (widget.clock ?? DateTime.now)());

  Future<void> _signPaths(List<String> paths) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final refreshIfOlderMs =
        (_signedUrlTtlSeconds - _signedUrlRefreshAheadSeconds) * 1000;
    final missing = paths.where((p) {
      final entry = _signedUrls[p];
      if (entry == null) return true;
      return nowMs - entry.signedAtMs > refreshIfOlderMs;
    }).toList();
    if (missing.isEmpty) return;
    try {
      final signed = await Supabase.instance.client.storage
          .from('run-photos')
          .createSignedUrls(missing, _signedUrlTtlSeconds);
      for (final s in signed) {
        if (s.path.isNotEmpty) {
          _signedUrls[s.path] = _SignedEntry(s.signedUrl, nowMs);
        }
      }
    } catch (e) {
      debugPrint('event-photos signed-url batch failed: $e');
    }
  }

  String _photoUrl(String storagePath) => _signedUrls[storagePath]?.url ?? '';

  String _galleryUrl(EventPhotoView p) {
    final t = p.thumb512Path;
    if (t != null && t.isNotEmpty) {
      final url = _signedUrls[t]?.url;
      if (url != null && url.isNotEmpty) return url;
    }
    return _photoUrl(p.storagePath);
  }

  Future<XFile?> _pick() async {
    return (widget.pickImageOverride ??
        () => _picker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 85,
              maxWidth: 2048,
            ))();
  }

  /// Resolve which run the photo attaches to, then pick + upload. A
  /// finisher goes straight to the picker via [myEventRunId]; everyone
  /// else chooses one of their recent runs first.
  Future<void> _openPhotoFlow() async {
    if (_uploading) return;
    final direct = widget.myEventRunId;
    if (direct != null) {
      await _pickAndUpload(direct);
      return;
    }
    final List<RecentRunRow> runs;
    try {
      runs = await widget.fetchWindowRuns();
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      showTopBanner(context, l10n.eventPhotoRunsLoadFailed(friendlyError(l10n, e)));
      return;
    }
    if (!mounted) return;
    final runId = await _showRunPicker(runs);
    if (runId == null) return;
    await _pickAndUpload(runId);
  }

  Future<void> _openHostPhotoFlow() async {
    if (_uploading || !_stewardCanPost) return;
    await _pickAndUpload(null);
  }

  // Reversible (a steward can restore it), so it takes the undo bar rather
  // than a confirm (conventions § Destructive actions). The steward keeps the
  // tile, badged, with Restore.
  // The photo whose hide is still inside the undo window. Restore on it must
  // cancel that pending commit rather than race it: a restore saved first
  // would be overwritten by the hide landing when the window closed.
  String? _pendingHideId;

  void _hide(EventPhotoView p) {
    final l10n = AppLocalizations.of(context);
    final api = widget.api;
    final snapshot = _photos;
    _pendingHideId = p.id;
    setState(() {
      _photos = [
        for (final x in _photos) x.id == p.id ? x.copyWithHidden(DateTime.now()) : x,
      ];
    });
    deferDestructive(
      context,
      DeferredDestruction(
        message: l10n.eventPhotoHidden,
        commit: () {
          if (_pendingHideId == p.id) _pendingHideId = null;
          return api.setEventPhotoHidden(p.id, hidden: true);
        },
        restore: () {
          if (_pendingHideId == p.id) _pendingHideId = null;
          if (!mounted) return;
          setState(() => _photos = snapshot);
        },
        onCommitError: (e) {
          debugPrint('event-photos hide failed: $e');
          if (!mounted) return;
          showTopBanner(
              context, l10n.eventPhotoModerateFailed(friendlyError(l10n, e)));
        },
      ),
    );
  }

  Future<void> _restore(EventPhotoView p) async {
    if (_pendingHideId == p.id) {
      undoQueue.undo();
      return;
    }
    if (_busyId != null) return;
    setState(() => _busyId = p.id);
    final l10n = AppLocalizations.of(context);
    try {
      await widget.api.setEventPhotoHidden(p.id, hidden: false);
      if (!mounted) return;
      setState(() {
        _photos = [
          for (final x in _photos) x.id == p.id ? x.copyWithHidden(null) : x,
        ];
      });
    } catch (e) {
      debugPrint('event-photos restore failed: $e');
      if (!mounted) return;
      showTopBanner(
          context, l10n.eventPhotoModerateFailed(friendlyError(l10n, e)));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  // The owner's delete is held for the undo window, so Undo cancels a timer.
  void _delete(EventPhotoView p) {
    final l10n = AppLocalizations.of(context);
    final api = widget.api;
    final snapshot = _photos;
    setState(() => _photos = _photos.where((x) => x.id != p.id).toList());
    deferDestructive(
      context,
      DeferredDestruction(
        message: l10n.eventPhotoDeleted,
        commit: () => api.deleteEventPhoto(p),
        restore: () {
          if (!mounted) return;
          setState(() => _photos = snapshot);
        },
        onCommitError: (e) {
          debugPrint('event-photos delete failed: $e');
          if (!mounted) return;
          showTopBanner(
              context, l10n.eventPhotoDeleteFailed(friendlyError(l10n, e)));
        },
      ),
    );
  }

  Future<String?> _showRunPicker(List<RecentRunRow> runs) {
    final l10n = AppLocalizations.of(context);
    return showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(l10n.eventWhichRunPhoto,
                    style: theme.textTheme.titleMedium),
              ),
              if (runs.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Text(l10n.eventNoRunsInPhotoWindow,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final r in runs)
                        ListTile(
                          leading: const Icon(Icons.directions_run),
                          title: Text(
                            '${formatDistanceForPref(r.distanceM)}'
                            ' · ${_dur(r.durationS)}',
                          ),
                          subtitle: Text(_dateLabel(r.startedAt)),
                          onTap: () => Navigator.pop(ctx, r.id),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// [runId] null is a steward's run-less photo of the occurrence.
  Future<void> _pickAndUpload(String? runId) async {
    XFile? file;
    try {
      file = await _pick();
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      if (e is PlatformException && e.code == 'photo_access_denied') {
        showTopBanner(
          context,
          l10n.runPhotosPermissionDenied,
          actionLabel: l10n.runPhotosOpenSettings,
          onAction: () => openAppSettings(),
          duration: const Duration(seconds: 6),
        );
      } else {
        showTopBanner(context, l10n.runPhotosPickerFailed);
      }
      return;
    }
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      // Sniff the bytes rather than trusting the picked filename, and
      // refuse anything we cannot clean — nothing downstream strips a
      // non-JPEG, so an unstripped upload ships the capture GPS.
      final raw = Uint8List.fromList(bytes);
      final contentType = detectImageMime(raw);
      if (contentType == null) throw const UnstrippableImageException('');
      final clean = stripImageExif(raw, contentType);
      final ext = imageExtensionForMime(contentType);
      await widget.api.addRunPhoto(
        runId: runId,
        bytes: clean,
        contentType: contentType,
        extension: ext,
        positionIdx: 0,
        eventId: widget.eventId,
        eventInstanceStart: widget.instanceStart,
      );
      await _load();
      if (mounted) setState(() => _uploading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploading = false);
      showTopBanner(context, AppLocalizations.of(context).eventPhotoUploadFailed);
    }
  }

  void _openLightbox(EventPhotoView p) =>
      showPhotoLightbox(context, url: _photoUrl(p.storagePath));

  String _dur(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    }
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  String _dateLabel(DateTime d) {
    final local = d.isUtc ? d.toLocal() : d;
    return '${local.year}-${local.month.toString().padLeft(2, '0')}'
        '-${local.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    if (_loading) return const SizedBox.shrink();
    if (_photos.isEmpty && !_loadFailed && !widget.canAdd) {
      return const SizedBox.shrink();
    }
    final visibleCount = _photos.where((p) => p.hiddenAt == null).length;
    final stewardCanPost = _stewardCanPost;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.photo_library_outlined,
                    size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(l10n.eventPhotosTitle(visibleCount),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            if (widget.canAdd)
              TextButton.icon(
                key: const ValueKey('event-photo-add'),
                onPressed: _uploading ? null : _openPhotoFlow,
                icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                label: Text(
                  _uploading
                      ? l10n.eventPhotoUploading
                      : stewardCanPost
                          ? l10n.eventAddPhotoFromRun
                          : l10n.eventAddPhoto,
                ),
              ),
          ],
        ),
        if (stewardCanPost)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              key: const ValueKey('event-photo-add-host'),
              onPressed: _uploading ? null : _openHostPhotoFlow,
              icon: const Icon(Icons.photo_camera, size: 18),
              label: Text(l10n.eventAddOccurrencePhoto),
            ),
          ),
        const SizedBox(height: 8),
        if (_loadFailed)
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.eventPhotosLoadFailed,
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
                ),
              ),
              TextButton(onPressed: _load, child: Text(l10n.eventPhotosRetry)),
            ],
          )
        else if (_photos.isEmpty)
          Text(
            widget.canAdd
                ? '${l10n.eventNoPhotosYet} ${l10n.eventNoPhotosAddHint}'
                : l10n.eventNoPhotosYet,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in _photos)
                _PhotoTile(
                  url: _galleryUrl(p),
                  caption: p.caption,
                  uploader: p.uploaderName ?? l10n.eventPhotoRunnerFallback,
                  hidden: p.hiddenAt != null,
                  busy: _busyId == p.id,
                  onTap: () => _openLightbox(p),
                  onHide: _steward && p.hiddenAt == null ? () => _hide(p) : null,
                  onRestore:
                      _steward && p.hiddenAt != null ? () => _restore(p) : null,
                  onDelete: widget.currentUserId != null &&
                          p.ownerId == widget.currentUserId
                      ? () => _delete(p)
                      : null,
                ),
            ],
          ),
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final String url;
  final String? caption;
  final String uploader;
  final bool hidden;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback? onHide;
  final VoidCallback? onRestore;
  final VoidCallback? onDelete;
  const _PhotoTile({
    required this.url,
    required this.caption,
    required this.uploader,
    required this.onTap,
    this.hidden = false,
    this.busy = false,
    this.onHide,
    this.onRestore,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A bare Image under a GestureDetector is, to TalkBack, an
          // unlabelled roleless rectangle. The caption and uploader below are
          // separate nodes, so without this the tappable thing itself carries
          // no name and no role.
          Semantics(
            button: true,
            image: true,
            label: (caption?.trim().isNotEmpty ?? false)
                ? caption!.trim()
                : l10n.photoOpen,
            child: GestureDetector(
              onTap: onTap,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 150,
                  height: 150,
                  color: cs.surfaceContainerHighest,
                  child: Opacity(
                    opacity: hidden ? 0.45 : 1,
                    child: url.isEmpty
                        ? Icon(Icons.image_outlined, color: cs.onSurfaceVariant)
                        : Image.network(
                            url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                                Icons.broken_image_outlined,
                                color: cs.onSurfaceVariant),
                          ),
                  ),
                ),
              ),
            ),
          ),
          if (caption != null && caption!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(caption!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(uploader,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
          ),
          if (hidden)
            Text(l10n.eventPhotoHiddenBadge,
                style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
          if (onHide != null || onRestore != null || onDelete != null)
            Wrap(
              spacing: 4,
              children: [
                if (onHide != null)
                  Semantics(
                    label: l10n.eventPhotoHideLabel(uploader),
                    button: true,
                    excludeSemantics: true,
                    child: TextButton(
                      onPressed: onHide,
                      child: Text(l10n.eventPhotoHide),
                    ),
                  ),
                if (onRestore != null)
                  TextButton(
                    onPressed: busy ? null : onRestore,
                    child: Text(l10n.eventPhotoRestore),
                  ),
                if (onDelete != null)
                  TextButton(
                    onPressed: onDelete,
                    style: TextButton.styleFrom(foregroundColor: cs.error),
                    child: Text(l10n.eventPhotoDelete),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SignedEntry {
  final String url;
  final int signedAtMs;
  const _SignedEntry(this.url, this.signedAtMs);
}

import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../l10n/gen/app_localizations.dart';
import 'photo_lightbox.dart';

/// How often a photo the server is still preparing is checked again, and
/// for how many tries (about three minutes) before the note stays put.
const Duration kDmPhotoPendingRecheck = Duration(seconds: 4);
const int kDmPhotoPendingMaxChecks = 45;

/// A message's photo (migration 20271213121604): "Preparing photo…" while
/// the server re-encodes it, the image from a short-lived signed URL once it
/// is ready (signed again a minute before it expires), a note when the
/// server could not process it, and another when it cannot be read. A failed
/// read stays inside this widget; the conversation is untouched. Mirrors
/// web's `DmImage.svelte`.
class DmPhoto extends StatefulWidget {
  const DmPhoto({
    super.key,
    required this.api,
    required this.imageId,
    this.color,
  });

  final ApiClient api;
  final String imageId;
  final Color? color;

  @override
  State<DmPhoto> createState() => _DmPhotoState();
}

class _DmPhotoState extends State<DmPhoto> {
  DmImageView? _view;
  bool _failed = false;
  Timer? _timer;
  int _checks = 0;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DmPhoto old) {
    super.didUpdateWidget(old);
    if (old.imageId == widget.imageId) return;
    _timer?.cancel();
    _gen++;
    _checks = 0;
    _view = null;
    _failed = false;
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _schedule(Duration after) {
    _timer?.cancel();
    _timer = Timer(after, _load);
  }

  Future<void> _load() async {
    final gen = _gen;
    try {
      final view = await widget.api.fetchDmImage(widget.imageId);
      if (!mounted || gen != _gen) return;
      setState(() {
        _failed = view == null;
        _view = view;
      });
      if (view?.status == 'pending' && ++_checks < kDmPhotoPendingMaxChecks) {
        _schedule(kDmPhotoPendingRecheck);
      } else if (view?.status == 'ready') {
        _schedule(
          const Duration(seconds: ApiClient.dmImageSignedUrlSeconds - 60),
        );
      }
    } catch (e) {
      debugPrint('message photo read failed: ${safeErrorLabel(e)}');
      if (!mounted || gen != _gen) return;
      if (++_checks < kDmPhotoPendingMaxChecks) {
        _schedule(kDmPhotoPendingRecheck);
      } else if (_view?.status != 'ready') {
        setState(() => _failed = true);
      }
    }
  }

  Widget _note(String key, IconData icon, String text) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: widget.color?.withValues(alpha: 0.8),
      fontStyle: FontStyle.italic,
    );
    return Row(
      key: ValueKey(key),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: AppIconSize.dense,
          color: widget.color?.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 4),
        Flexible(child: Text(text, style: style)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final view = _view;
    final url = view?.url;
    if (view?.status == 'ready' && url != null) {
      final w = view!.width;
      final h = view.height;
      final aspect = w != null && h != null && w > 0 && h > 0 ? w / h : 4 / 3;
      return Semantics(
        image: true,
        label: l10n.messagesPhotoAlt,
        excludeSemantics: true,
        child: GestureDetector(
          key: const ValueKey('dm-photo'),
          onTap: () => showPhotoLightbox(context, url: url),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240, maxHeight: 320),
            child: AspectRatio(
              aspectRatio: aspect,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Center(
                    child: _note(
                      'dm-photo-unavailable',
                      Icons.broken_image_outlined,
                      l10n.messagesPhotoUnavailableToView,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (view?.status == 'rejected') {
      return _note(
        'dm-photo-rejected',
        Icons.image_not_supported_outlined,
        l10n.messagesPhotoRejected,
      );
    }
    if (_failed) {
      return _note(
        'dm-photo-unavailable',
        Icons.broken_image_outlined,
        l10n.messagesPhotoUnavailableToView,
      );
    }
    return _note(
      'dm-photo-pending',
      Icons.hourglass_empty,
      l10n.messagesPhotoProcessing,
    );
  }
}

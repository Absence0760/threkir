import 'dart:async';
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show LengthLimitingTextInputFormatter, PlatformException;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;
import 'package:ui_kit/ui_kit.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth_error.dart';
import '../coach_share.dart';
import '../dm_attachment.dart';
import '../dm_edit.dart';
import '../dm_image.dart';
import '../dm_image_encode.dart';
import '../dm_pending_hides.dart';
import '../dm_reactions.dart';
import '../dm_read_receipt.dart';
import '../dm_send_error.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../undo_queue.dart';
import '../widgets/coach_share_card.dart';
import '../widgets/dm_bubble.dart';
import '../widgets/dm_photo.dart';
import '../widgets/dm_reaction_chips.dart';
import '../widgets/dm_route_attachment.dart';
import '../widgets/error_state.dart';
import '../widgets/message_actions_sheet.dart';
import '../widgets/plan_change_requests.dart';
import '../widgets/report_sheet.dart';
import '../widgets/sign_in_required_state.dart';
import '../widgets/top_banner.dart';
import '../widgets/undo_bar.dart';
import 'profile_screen.dart';

/// How often an open conversation re-reads its newest page. There is no
/// Realtime channel on this rail on any platform, so a poll is how a reply
/// arrives while the conversation is on screen.
const Duration kMessageThreadPollInterval = Duration(seconds: 10);

/// One direct-message conversation with a composer. Mirrors the conversation
/// pane of web's `/messages/[[id]]`.
///
/// A send is optimistic: the bubble appears at once marked as sending, is
/// replaced by the stored row when the insert answers, and on a refusal is
/// withdrawn with the typed text put back in the composer and the reason
/// shown — the follow / block gate, the send throttle, offline and anything
/// else each read differently (`dm_send_error.dart`).
///
/// Long-pressing a message opens its options: Edit on your own for 15
/// minutes after sending (migration 20271114000210), Unsend on your own
/// (confirmed, since it cannot be undone) and Report on the other person's.
/// An edited message is marked "Edited" on both sides. A partner
/// who deleted their account opens through [MessageThreadScreen.deletedPartner]:
/// the viewer's own messages under that partner's key, with no composer
/// (migration 20271021000003).
///
/// The overflow menu blocks or unblocks the partner, the same toggle the
/// profile carries (decisions § 1952): Block is confirmed, Unblock is not.
/// It also mutes, archives and deletes the conversation for the viewer
/// (migration 20271105000010). Delete is held behind the undo bar and tells
/// the server only when the window closes, so it is not confirmed.
/// While the viewer's block stands the composer gives way to a notice, since
/// the INSERT policy refuses a send either way across a block.
///
/// Issue #1216: a message's links show their domain and open in the browser;
/// a live message carries reaction chips, and React in its options; a photo
/// is re-encoded on the device before upload, offered only while the
/// server's `dm_images` gate is open.
class MessageThreadScreen extends StatefulWidget {
  const MessageThreadScreen({
    super.key,
    required this.api,
    required String this.partnerId,
    this.partnerName,
    this.partnerAvatarUrl,
    this.pollInterval = kMessageThreadPollInterval,
    this.onOpenRoute,
    this.onOpenCoachSource,
    this.conversationId,
    this.initialMuted,
    this.initialArchived,
    this.initialMarkedUnread,
    this.initialRequest,
    this.pickPhoto,
    this.openLink,
  }) : deletedPartnerKey = null;

  const MessageThreadScreen.deletedPartner({
    super.key,
    required this.api,
    required String this.deletedPartnerKey,
    this.pollInterval = kMessageThreadPollInterval,
    this.onOpenRoute,
    this.onOpenCoachSource,
    this.conversationId,
    this.initialMuted,
    this.initialArchived,
    this.initialMarkedUnread,
    this.openLink,
  })  : initialRequest = null,
        pickPhoto = null,
        partnerId = null,
        partnerName = null,
        partnerAvatarUrl = null;

  final ApiClient api;

  /// Null for a deleted partner's thread; [deletedPartnerKey] names it then.
  final String? partnerId;
  final String? deletedPartnerKey;
  final String? partnerName;
  final String? partnerAvatarUrl;
  final Duration pollInterval;
  final void Function(BuildContext context, String routeId)? onOpenRoute;

  /// Opens the Coach from the link back on a shared Coach answer the viewer
  /// sent. Defaults to pushing the Coach screen.
  final void Function(BuildContext context, String? planId)? onOpenCoachSource;

  /// The conversation and the viewer's state for it, when the inbox opened
  /// the thread. Opened from elsewhere, the id comes from the messages and the
  /// state is read once they load.
  final String? conversationId;
  final bool? initialMuted;
  final bool? initialArchived;

  /// The viewer marked the conversation unread; opening it clears the mark.
  final bool? initialMarkedUnread;

  /// The conversation is a message request to the viewer they have not
  /// answered (migration 20271115002384).
  final bool? initialRequest;

  /// The bytes of a photo the runner picked, or null when they cancelled.
  /// Defaults to the gallery picker; tests inject it.
  final Future<Uint8List?> Function()? pickPhoto;

  /// Opens a link from a message. Defaults to the external browser; tests
  /// inject it.
  final Future<bool> Function(Uri uri)? openLink;

  @override
  State<MessageThreadScreen> createState() => _MessageThreadScreenState();
}

class _PendingMessage {
  _PendingMessage(this.localId, this.body, this.createdAt);
  final String localId;
  final String body;
  final DateTime createdAt;
}

class _MessageThreadScreenState extends State<MessageThreadScreen>
    with WidgetsBindingObserver {
  final _composer = TextEditingController();
  Timer? _poll;

  bool _loading = true;
  Object? _loadError;
  List<DirectMessageRow> _messages = const [];

  /// The partner message this conversation was last marked read through. A
  /// client cannot read `read_at` (a column grant withholds it, migration
  /// 20271113000001), so it remembers how far it marked instead.
  String? _markedThroughId;
  bool _hasMore = false;
  bool _loadingEarlier = false;
  bool _refreshing = false;
  int _window = 0;
  int _refreshTick = 0;

  final List<_PendingMessage> _pending = [];
  bool _sending = false;
  int _pendingSeq = 0;

  String? _partnerName;

  /// Whether the viewer has blocked the partner. `user_blocks` is owner-read,
  /// so a block the partner placed is never known here; that one surfaces as
  /// the send refusal, the same sentence as the follow gate (§ 1916).
  bool _blocked = false;
  bool _blockBusy = false;

  /// Bumped by a completed block or unblock, so a state read that started
  /// before it cannot undo what the viewer just did.
  int _blockVersion = 0;

  String? _conversationId;
  bool _muted = false;
  bool _archived = false;
  bool _conversationBusy = false;

  /// The viewer deleted the conversation for themselves; the undo bar is up.
  bool _deleted = false;

  /// A message request to the viewer they have not answered. The composer
  /// gives way to Accept / Decline / Block; the server withholds the read
  /// receipt while it stands, so the requester learns nothing until it is
  /// accepted.
  bool _request = false;
  bool _requestBusy = false;

  /// Bumped whenever the list is written from something newer than a poll's
  /// read (a send, an unsend), so a poll already in flight is dropped rather
  /// than putting an unsent message's text back.
  int _localWrites = 0;

  /// Reactions on the live messages on screen (migration 20271213121602),
  /// re-read with every thread read so the partner's appear on the next poll.
  List<DmReactionRow> _reactions = const [];
  int _reactionReadSeq = 0;

  /// Bumped by the viewer's own reaction, so a read that started before it
  /// cannot put the old chip back.
  int _reactionWrites = 0;

  /// The server's `dm_images` gate; off until read, and off on a failure.
  bool _photosEnabled = false;

  /// The picked photo, already re-encoded without its metadata.
  Uint8List? _photoDraft;
  bool _preparingPhoto = false;

  DmThreadTarget get _target => widget.partnerId != null
      ? DmPartnerThread(widget.partnerId!)
      : DmDeletedPartnerThread(widget.deletedPartnerKey!);

  @override
  void initState() {
    super.initState();
    _partnerName = widget.partnerName;
    _conversationId = widget.conversationId;
    _muted = widget.initialMuted ?? false;
    _archived = widget.initialArchived ?? false;
    _request = widget.initialRequest ?? false;
    WidgetsBinding.instance.addObserver(this);
    _composer.addListener(_onComposerChanged);
    if (widget.api.userId == null) return;
    _load();
    if (_partnerName == null && widget.partnerId != null) _loadPartnerName();
    if (widget.partnerId != null) _loadBlockState();
    if (widget.partnerId != null) _loadPhotosEnabled();
    _poll = Timer.periodic(widget.pollInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _composer.removeListener(_onComposerChanged);
    _composer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _onComposerChanged() => setState(() {});

  bool get _appInForeground {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed;
  }

  Future<void> _loadPartnerName() async {
    try {
      final profile = await widget.api.fetchPublicProfile(widget.partnerId!);
      if (!mounted || profile?.displayName == null) return;
      setState(() => _partnerName = profile!.displayName);
    } catch (e) {
      debugPrint('message thread partner name read failed: ${safeErrorLabel(e)}');
    }
  }

  /// Never gates the conversation: on a failure the composer stays, and the
  /// server still refuses a blocked send.
  Future<void> _loadBlockState() async {
    final versionAtStart = _blockVersion;
    try {
      final blocked = await widget.api.isBlockedByViewer(widget.partnerId!);
      if (!mounted || versionAtStart != _blockVersion) return;
      if (blocked != _blocked) setState(() => _blocked = blocked);
    } catch (e) {
      debugPrint('message thread block check failed: ${safeErrorLabel(e)}');
    }
  }

  Future<void> _loadPhotosEnabled() async {
    final on = await widget.api.fetchDmImagesEnabled();
    if (mounted && on != _photosEnabled) setState(() => _photosEnabled = on);
  }

  /// An auxiliary read: a failure keeps the chips shown and the next thread
  /// read tries again.
  Future<void> _loadReactions() async {
    if (widget.api.userId == null) return;
    final ids = [
      for (final m in _messages)
        if (m.unsentAt == null) m.id,
    ];
    final seq = ++_reactionReadSeq;
    final writes = _reactionWrites;
    try {
      final rows = await widget.api.fetchDmReactions(ids);
      if (!mounted || seq != _reactionReadSeq || writes != _reactionWrites) {
        return;
      }
      setState(() => _reactions = [
            for (final r in rows)
              DmReactionRow(
                messageId: r.messageId,
                userId: r.userId,
                reaction: r.reaction,
              ),
          ]);
    } catch (e) {
      debugPrint('message reactions read failed: ${safeErrorLabel(e)}');
    }
  }

  /// The server decides (a block either way, an unaccepted request, an
  /// unsent message all refuse it); this only decides whether to offer it.
  bool _canReact(DirectMessageRow m) =>
      widget.partnerId != null &&
      widget.api.userId != null &&
      !_blocked &&
      !_request &&
      !_deleted &&
      m.unsentAt == null;

  /// Applied at once; a refusal puts the viewer's previous reaction back and
  /// says why.
  Future<void> _react(DirectMessageRow m, String? next) async {
    final me = widget.api.userId;
    if (me == null || !_canReact(m)) return;
    final previous = myDmReaction(_reactions, m.id, me);
    _reactionWrites++;
    setState(() => _reactions = withMyDmReaction(_reactions, m.id, me, next));
    try {
      await widget.api.setDmReaction(m.id, next);
    } catch (e) {
      debugPrint('message reaction failed: ${safeErrorLabel(e)}');
      if (!mounted) return;
      _reactionWrites++;
      setState(() =>
          _reactions = withMyDmReaction(_reactions, m.id, me, previous));
      showTopBanner(
          context, dmReactionErrorMessage(AppLocalizations.of(context), e));
    }
  }

  Future<void> _pickReaction(DirectMessageRow m) async {
    final current = myDmReaction(_reactions, m.id, widget.api.userId);
    final picked = await showDmReactionPicker(context, current: current);
    if (picked == null || !mounted) return;
    await _react(m, picked == current ? null : picked);
  }

  /// Only http(s) reaches here ([DmMessageText] makes nothing else a link),
  /// and it opens outside the app.
  Future<void> _openLink(String href) async {
    final l10n = AppLocalizations.of(context);
    var opened = false;
    try {
      final uri = Uri.parse(href);
      if (uri.scheme == 'http' || uri.scheme == 'https') {
        opened = await (widget.openLink ?? _launchExternal)(uri);
      }
    } catch (e) {
      debugPrint('message link open failed: ${safeErrorLabel(e)}');
    }
    if (!opened && mounted) showTopBanner(context, l10n.messagesLinkOpenFailed);
  }

  static Future<bool> _launchExternal(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  static Future<Uint8List?> _pickFromGallery() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: kDmImageMaxEdge.toDouble(),
      maxHeight: kDmImageMaxEdge.toDouble(),
    );
    return file?.readAsBytes();
  }

  /// The photo is decoded and drawn again as a JPEG before it is kept, so
  /// what waits beside the composer, and what is uploaded, has no metadata.
  Future<void> _pickPhoto() async {
    if (_preparingPhoto || _sending) return;
    final l10n = AppLocalizations.of(context);
    Uint8List? raw;
    try {
      raw = await (widget.pickPhoto ?? _pickFromGallery)();
    } catch (e) {
      debugPrint('message photo pick failed: ${safeErrorLabel(e)}');
      if (!mounted) return;
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
    if (raw == null || !mounted) return;
    setState(() => _preparingPhoto = true);
    try {
      final jpeg = await encodeDmImageInBackground(raw);
      if (!mounted) return;
      setState(() => _photoDraft = jpeg);
    } catch (e) {
      debugPrint('message photo encode failed: $e');
      if (!mounted) return;
      showTopBanner(
        context,
        e is DmImageEncodeError && e.kind == DmImageEncodeFailure.tooLarge
            ? l10n.messagesPhotoTooLarge
            : l10n.messagesPhotoUnreadable,
      );
    } finally {
      if (mounted) setState(() => _preparingPhoto = false);
    }
  }

  String _displayName(AppLocalizations l10n) =>
      _partnerName ?? l10n.profileRunnerFallback;

  /// The newest message from the requester on screen: a decline stops there,
  /// so one that arrives after the viewer decided is not hidden unseen.
  DirectMessageRow? get _requestThrough {
    for (final m in _messages.reversed) {
      if (m.senderId == widget.partnerId) return m;
    }
    return null;
  }

  Future<void> _acceptRequest() async {
    final id = _conversationId;
    if (id == null || _requestBusy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _requestBusy = true);
    try {
      await widget.api.acceptDmRequest(id);
      if (!mounted) return;
      setState(() => _request = false);
      showTopBanner(context, l10n.messagesRequestAcceptedToast);
    } catch (e) {
      debugPrint('message request accept failed: ${safeErrorLabel(e)}');
      if (mounted) {
        showTopBanner(
            context, l10n.messagesRequestActionFailed(friendlyError(l10n, e)));
      }
    } finally {
      if (mounted) setState(() => _requestBusy = false);
    }
  }

  /// Decline cannot be undone from the app (the conversation leaves every
  /// list), so it is confirmed rather than held behind an undo window
  /// (conventions.md § Destructive actions).
  Future<void> _confirmDecline() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.messagesRequestDeclineConfirmTitle),
            content: Text(l10n.messagesRequestDeclineConfirmMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.profileCancel),
              ),
              FilledButton.tonal(
                key: const ValueKey('message-request-decline-confirm'),
                style: FilledButton.styleFrom(
                  foregroundColor: Theme.of(ctx).colorScheme.error,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l10n.messagesRequestDecline),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    await _declineRequest(block: false);
  }

  /// Decline, or decline and block in one server transaction. Either way the
  /// conversation leaves the viewer's lists, so the thread closes.
  Future<void> _declineRequest({required bool block}) async {
    final id = _conversationId;
    final through = _requestThrough;
    if (id == null || through == null || _requestBusy) return;
    final l10n = AppLocalizations.of(context);
    final name = _displayName(l10n);
    setState(() => _requestBusy = true);
    try {
      await widget.api
          .declineDmRequest(id, throughMessageId: through.id, block: block);
      if (!mounted) return;
      if (block) _blockVersion++;
      final messenger = Navigator.of(context);
      showTopBanner(
        context,
        block ? l10n.profileBlocked(name) : l10n.messagesRequestDeclinedToast,
      );
      messenger.pop();
    } catch (e) {
      debugPrint('message request decline failed: ${safeErrorLabel(e)}');
      if (mounted) {
        showTopBanner(
            context, l10n.messagesRequestActionFailed(friendlyError(l10n, e)));
      }
    } finally {
      if (mounted) setState(() => _requestBusy = false);
    }
  }

  Future<void> _toggleBlock() async {
    if (_blockBusy || widget.partnerId == null) return;
    if (_blocked) return _unblock();
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.profileBlockConfirmTitle(_displayName(l10n))),
            content: Text(l10n.messagesBlockConfirmBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.profileCancel),
              ),
              FilledButton.tonal(
                key: const ValueKey('message-block-confirm'),
                style: FilledButton.styleFrom(
                  foregroundColor: Theme.of(ctx).colorScheme.error,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l10n.profileBlockConfirmAction),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    if (_request && _requestThrough != null) {
      return _declineRequest(block: true);
    }
    setState(() => _blockBusy = true);
    try {
      await widget.api.blockUser(widget.partnerId!);
      if (!mounted) return;
      _blockVersion++;
      setState(() => _blocked = true);
      showTopBanner(context, l10n.profileBlocked(_displayName(l10n)));
    } catch (e) {
      debugPrint('message thread block failed: ${safeErrorLabel(e)}');
      if (mounted) {
        showTopBanner(context, l10n.profileBlockFailed(friendlyError(l10n, e)));
      }
    } finally {
      if (mounted) setState(() => _blockBusy = false);
    }
  }

  Future<void> _unblock() async {
    if (_blockBusy || widget.partnerId == null) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _blockBusy = true);
    try {
      await widget.api.unblockUser(widget.partnerId!);
      if (!mounted) return;
      _blockVersion++;
      setState(() => _blocked = false);
      showTopBanner(context, l10n.profileUnblocked(_displayName(l10n)));
    } catch (e) {
      debugPrint('message thread unblock failed: ${safeErrorLabel(e)}');
      if (mounted) {
        showTopBanner(
            context, l10n.profileUnblockFailed(friendlyError(l10n, e)));
      }
    } finally {
      if (mounted) setState(() => _blockBusy = false);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final page = await widget.api.fetchDmThread(_target);
      if (!mounted) return;
      setState(() {
        _messages = page.messages;
        _hasMore = page.hasMore;
        _loading = false;
        if (_messages.isNotEmpty) {
          _conversationId ??= _messages.last.conversationId;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
      return;
    }
    unawaited(_loadReactions());
    if (widget.initialMuted == null) {
      _loadConversationState();
    } else if (widget.initialMarkedUnread == true) {
      _clearUnreadMark();
    }
    await _markReadIfUnread();
  }

  /// A thread opened from outside the inbox reads the viewer's mute and
  /// archive state. A failure leaves both off; the menu still works.
  Future<void> _loadConversationState() async {
    final id = _conversationId;
    if (id == null) return;
    try {
      final state = await widget.api.fetchDmConversationState(id);
      if (!mounted || state == null || _conversationBusy) return;
      final newest = _messages.isEmpty ? null : _messages.last.createdAt;
      final archivedAt = state.archivedAt;
      setState(() {
        _muted = state.muted;
        _request = state.request;
        _archived = archivedAt != null &&
            (newest == null || !archivedAt.isBefore(newest));
      });
      if (state.markedUnread) _clearUnreadMark();
    } catch (e) {
      debugPrint(
          'message thread conversation state read failed: ${safeErrorLabel(e)}');
    }
  }

  /// Opening a conversation the viewer marked unread clears the mark. A
  /// failure leaves it set: the inbox keeps counting it until the next open.
  Future<void> _clearUnreadMark() async {
    final id = _conversationId;
    if (id == null) return;
    try {
      await widget.api.setDmConversationUnread(id, unread: false);
    } catch (e) {
      debugPrint(
          'message thread unread-mark clear failed: ${safeErrorLabel(e)}');
    }
  }

  /// Mark as unread leaves the conversation, so the open screen does not
  /// read it again on the way out; the inbox counts it as one until the
  /// conversation is opened again. Pops with `true` so the inbox keeps the
  /// mark rather than zeroing the row it opened.
  Future<void> _markUnread() async {
    final id = _conversationId;
    if (id == null || _conversationBusy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _conversationBusy = true);
    try {
      await widget.api.setDmConversationUnread(id, unread: true);
      if (!mounted) return;
      showTopBanner(context, l10n.messagesMarkedUnreadToast);
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('message thread mark-unread failed: ${safeErrorLabel(e)}');
      if (mounted) {
        showTopBanner(context,
            l10n.messagesConversationActionFailed(friendlyError(l10n, e)));
      }
    } finally {
      if (mounted) setState(() => _conversationBusy = false);
    }
  }

  Future<void> _toggleMuted() async {
    final id = _conversationId;
    if (id == null || _conversationBusy) return;
    final l10n = AppLocalizations.of(context);
    final next = !_muted;
    setState(() => _conversationBusy = true);
    try {
      await widget.api.setDmConversationMuted(id, muted: next);
      if (!mounted) return;
      setState(() => _muted = next);
      if (next) showTopBanner(context, l10n.messagesMutedToast);
    } catch (e) {
      debugPrint('message thread mute failed: ${safeErrorLabel(e)}');
      if (mounted) {
        showTopBanner(context,
            l10n.messagesConversationActionFailed(friendlyError(l10n, e)));
      }
    } finally {
      if (mounted) setState(() => _conversationBusy = false);
    }
  }

  Future<void> _toggleArchived() async {
    final id = _conversationId;
    if (id == null || _conversationBusy) return;
    final l10n = AppLocalizations.of(context);
    final next = !_archived;
    setState(() => _conversationBusy = true);
    try {
      await widget.api.setDmConversationArchived(id, archived: next);
      if (!mounted) return;
      setState(() => _archived = next);
      if (next) showTopBanner(context, l10n.messagesArchivedToast);
    } catch (e) {
      debugPrint('message thread archive failed: ${safeErrorLabel(e)}');
      if (mounted) {
        showTopBanner(context,
            l10n.messagesConversationActionFailed(friendlyError(l10n, e)));
      }
    } finally {
      if (mounted) setState(() => _conversationBusy = false);
    }
  }

  /// Delete-for-me is honestly undoable — nothing reaches the server until
  /// the window closes — so it takes the undo bar and no confirm
  /// (conventions.md § Destructive actions). The inbox under this screen
  /// leaves the conversation out until then, and out of any read that
  /// started before the delete landed ([DmPendingHides]). The delete stops
  /// at the newest message on screen when it was tapped, so one a poll brings
  /// in during the window is not hidden unseen.
  void _deleteConversation() {
    final id = _conversationId;
    final through =
        _messages.where((m) => m.conversationId == id).lastOrNull;
    if (id == null || through == null || _deleted) return;
    final l10n = AppLocalizations.of(context);
    final api = widget.api;
    final hides = DmPendingHides.instance;
    // The thread is usually popped before the window closes, and a failed
    // commit then puts the conversation back in the inbox under it; the
    // root navigator outlives this screen, so the failure is said there.
    final bannerContext = Navigator.of(context, rootNavigator: true).context;
    hides.add(id);
    setState(() => _deleted = true);
    deferDestructive(
      context,
      DeferredDestruction(
        message: l10n.messagesConversationDeleted,
        // A refused commit is put back by restore.
        commit: () async {
          await api.hideDmConversation(id, throughMessageId: through.id);
          hides.landed(id);
        },
        restore: () {
          hides.remove(id);
          if (!mounted) return;
          setState(() => _deleted = false);
        },
        onCommitError: (e) {
          debugPrint('message thread delete failed: ${safeErrorLabel(e)}');
          if (!bannerContext.mounted) return;
          showTopBanner(bannerContext,
              l10n.messagesConversationActionFailed(friendlyError(l10n, e)));
        },
      ),
    );
  }

  void _onMenu(String action) {
    switch (action) {
      case 'mute':
        _toggleMuted();
      case 'archive':
        _toggleArchived();
      case 'unread':
        _markUnread();
      case 'delete':
        _deleteConversation();
      case 'block':
        _toggleBlock();
    }
  }

  /// Re-read the newest page and merge it in by id. Skipped while the first
  /// load or another refresh is in flight, while the app is in the background
  /// and while another screen covers this one. A failed poll keeps what is
  /// on screen: the next tick is the retry, and a banner every ten seconds
  /// would be noise.
  ///
  /// A page that does not reach back to the newest message on screen means
  /// more than a page arrived since the last read. Merging it would leave the
  /// messages between the two out of the list for good, since "load earlier"
  /// pages back from the oldest message shown, so the page replaces the list
  /// instead and the older history is one "load earlier" away again.
  Future<void> _refresh() async {
    if (_loading || _refreshing || _loadError != null) return;
    if (!_appInForeground) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    _refreshing = true;
    final writesAtStart = _localWrites;
    try {
      final page = await widget.api.fetchDmThread(_target);
      if (!mounted || writesAtStart != _localWrites) return;
      setState(() {
        _refreshTick++;
        final fresh = page.messages;
        final gap = page.hasMore &&
            fresh.isNotEmpty &&
            _messages.isNotEmpty &&
            _compareOrder(fresh.first, _messages.last) > 0;
        if (!gap) {
          _messages = _merge(_messages, fresh);
          return;
        }
        _window++;
        _messages = _merge(fresh, [
          for (final m in _messages)
            if (_compareOrder(m, fresh.last) > 0) m,
        ]);
        _hasMore = true;
      });
      unawaited(_loadReactions());
      await _markReadIfUnread();
    } catch (e) {
      debugPrint('message thread poll failed: ${safeErrorLabel(e)}');
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _loadEarlier() async {
    if (_loadingEarlier || _messages.isEmpty) return;
    final window = _window;
    setState(() => _loadingEarlier = true);
    try {
      final page = await widget.api
          .fetchDmThread(_target, before: _messages.first);
      if (!mounted || window != _window) return;
      setState(() {
        _messages = _merge(_messages, page.messages);
        _hasMore = page.hasMore;
      });
      unawaited(_loadReactions());
    } catch (e) {
      debugPrint('message thread older page failed: ${safeErrorLabel(e)}');
      if (mounted) {
        showTopBanner(
          context,
          AppLocalizations.of(context).messagesLoadEarlierFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _loadingEarlier = false);
    }
  }

  static List<DirectMessageRow> _merge(
    List<DirectMessageRow> a,
    List<DirectMessageRow> b,
  ) {
    final byId = <String, DirectMessageRow>{
      for (final m in a) m.id: m,
      for (final m in b) m.id: m,
    };
    return byId.values.toList()..sort(_compareOrder);
  }

  /// The thread's `(created_at, id)` order, the one `fetchDmThread` pages on.
  static int _compareOrder(DirectMessageRow x, DirectMessageRow y) {
    final at = x.createdAt.compareTo(y.createdAt);
    return at != 0 ? at : x.id.compareTo(y.id);
  }

  /// Opening the conversation marks it read, as does a poll that brings in a
  /// new message from the partner. Only up to the newest unread message on
  /// screen: one that arrived after the read that drew the list stays unread
  /// until a poll shows it. An auxiliary effect: a failure leaves the
  /// conversation on screen and the next poll tries again.
  Future<void> _markReadIfUnread() async {
    final partnerId = widget.partnerId;
    if (partnerId == null) return;
    final through = dmMarkReadThrough(_messages, partnerId, _markedThroughId);
    if (through == null) return;
    try {
      await widget.api.markDmThreadRead(partnerId, through: through);
      if (!mounted) return;
      _markedThroughId = through.id;
    } catch (e) {
      debugPrint('message thread mark-read failed: ${safeErrorLabel(e)}');
    }
  }

  /// A photo is uploaded first and the message sent with its id; the photo
  /// stays beside the composer until the message is stored.
  Future<void> _send() async {
    final partnerId = widget.partnerId;
    final body = _composer.text.trim();
    final photo = _photoDraft;
    if (partnerId == null ||
        _blocked ||
        _sending ||
        _preparingPhoto ||
        (body.isEmpty && photo == null)) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final pending = _PendingMessage('pending-${_pendingSeq++}',
        body.isEmpty ? l10n.messagesPhotoPreview : body, DateTime.now());
    setState(() {
      _sending = true;
      _pending.add(pending);
    });
    _composer.clear();
    var uploaded = false;
    try {
      String? imageId;
      if (photo != null) {
        imageId = await widget.api.uploadDmImage(photo);
        uploaded = true;
      }
      final row = await widget.api.sendDm(partnerId, body, imageId: imageId);
      if (!mounted) return;
      _localWrites++;
      setState(() {
        _pending.remove(pending);
        _messages = _merge(_messages, [row]);
        if (identical(_photoDraft, photo)) _photoDraft = null;
      });
    } catch (e) {
      debugPrint('message send failed: ${safeErrorLabel(e)}');
      if (!mounted) return;
      setState(() => _pending.remove(pending));
      if (_composer.text.isEmpty) {
        _composer.value = TextEditingValue(
          text: body,
          selection: TextSelection.collapsed(offset: body.length),
        );
      }
      showTopBanner(
        context,
        photo != null
            ? dmPhotoSendErrorMessage(l10n, e, uploaded: uploaded)
            : dmSendErrorMessage(l10n, e),
        duration: kTopBannerMaxDuration,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _openProfile() {
    final partnerId = widget.partnerId;
    if (partnerId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileScreen(api: widget.api, userId: partnerId),
      ),
    );
  }

  /// The long-press options for one stored message: Edit (inside the window)
  /// and Unsend on your own, Report on the other person's. An unsent message
  /// has none.
  Future<void> _showOptions(DirectMessageRow m) async {
    final mine = m.senderId == widget.api.userId;
    final editable = canEditDm(m, widget.api.userId, DateTime.now());
    final canReact = _canReact(m);
    final action = await showMessageActionsSheet(
      context,
      mine: mine,
      editable: editable,
      canReact: canReact,
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'react':
        await _pickReaction(m);
      case 'unsend':
        await _unsend(m);
      case 'edit':
        await _edit(m);
      case 'report':
        await showReportSheet(
          context,
          api: widget.api,
          targetKind: 'direct_message',
          targetId: m.id,
        );
    }
  }

  /// The edit saves from inside its dialog, so a refused save is said there
  /// with the text still in the field rather than lost behind a banner.
  Future<void> _edit(DirectMessageRow m) async {
    final row = await showDialog<DirectMessageRow>(
      context: context,
      builder: (ctx) => DmEditMessageDialog(
        initial: m.body ?? '',
        save: (body) => widget.api.editDm(m.id, body),
      ),
    );
    if (row == null || !mounted) return;
    _localWrites++;
    setState(() => _messages = _merge(_messages, [row]));
  }

  /// Unsend cannot be undone — the server clears the text for both people —
  /// so it is confirmed rather than offered an undo (conventions.md
  /// § Destructive actions).
  Future<void> _unsend(DirectMessageRow m) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.messagesUnsendConfirmTitle),
            content: Text(l10n.messagesUnsendConfirmBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.commonCancel),
              ),
              TextButton(
                key: const ValueKey('message-unsend-confirm'),
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(
                    foregroundColor: AppSemanticColors.of(ctx).danger),
                child: Text(l10n.messagesUnsend),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    try {
      final row = await widget.api.unsendDm(m.id);
      if (!mounted) return;
      _localWrites++;
      setState(() => _messages = _merge(_messages, [row]));
    } catch (e) {
      debugPrint('message unsend failed: ${safeErrorLabel(e)}');
      if (mounted) showTopBanner(context, l10n.messagesUnsendFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final signedIn = widget.api.userId != null;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            IdentityAvatar(
              seed: widget.partnerId ?? widget.deletedPartnerKey!,
              name: _partnerName,
              imageUrl: widget.partnerAvatarUrl,
              size: 32,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.partnerId == null
                    ? l10n.messagesDeletedAccount
                    : _partnerName ?? l10n.profileRunnerFallback,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (signedIn && widget.partnerId != null)
            IconButton(
              tooltip: l10n.messagesViewProfile,
              icon: const Icon(Icons.person_outline),
              onPressed: _openProfile,
            ),
          if (signedIn &&
              !_deleted &&
              (widget.partnerId != null || _conversationId != null))
            PopupMenuButton<String>(
              key: const ValueKey('message-thread-more'),
              tooltip: l10n.commonMore,
              onSelected: _onMenu,
              itemBuilder: (context) => [
                if (_conversationId != null && widget.partnerId != null)
                  PopupMenuItem(
                    key: const ValueKey('message-thread-mute'),
                    value: 'mute',
                    enabled: !_conversationBusy,
                    child: ListTile(
                      leading: Icon(_muted
                          ? Icons.notifications_outlined
                          : Icons.notifications_off_outlined),
                      title: Text(
                          _muted ? l10n.messagesUnmute : l10n.messagesMute),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                if (_conversationId != null)
                  PopupMenuItem(
                    key: const ValueKey('message-thread-archive'),
                    value: 'archive',
                    enabled: !_conversationBusy,
                    child: ListTile(
                      leading: Icon(_archived
                          ? Icons.unarchive_outlined
                          : Icons.archive_outlined),
                      title: Text(_archived
                          ? l10n.messagesUnarchive
                          : l10n.messagesArchive),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                if (_conversationId != null)
                  PopupMenuItem(
                    key: const ValueKey('message-thread-mark-unread'),
                    value: 'unread',
                    enabled: !_conversationBusy,
                    child: ListTile(
                      leading: const Icon(Icons.mark_chat_unread_outlined),
                      title: Text(l10n.messagesMarkUnread),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                if (_conversationId != null && _messages.isNotEmpty)
                  PopupMenuItem(
                    key: const ValueKey('message-thread-delete'),
                    value: 'delete',
                    child: ListTile(
                      leading: const Icon(Icons.delete_outline),
                      title: Text(l10n.messagesDeleteConversation),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                if (widget.partnerId != null)
                  PopupMenuItem(
                    key: const ValueKey('message-thread-block'),
                    value: 'block',
                    enabled: !_blockBusy,
                    child: ListTile(
                      leading: Icon(
                        Icons.block,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: Text(
                        _blocked ? l10n.messagesUnblock : l10n.messagesBlock,
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: !signedIn
          ? SignInRequiredState(api: widget.api)
          : Column(
              children: [
                // A suggested change to a coach-assigned plan is a system
                // card above the conversation, merged in the UI only
                // (decisions § 2382): it is not a direct message.
                if (widget.partnerId != null && !_deleted)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                    ),
                    child: SingleChildScrollView(
                      child: PlanChangeRequestsSection(
                        api: widget.api,
                        partnerId: widget.partnerId,
                      ),
                    ),
                  ),
                Expanded(
                  child: _deleted
                      ? EmptyState(
                          key: const ValueKey('message-thread-deleted'),
                          icon: Icons.delete_outline,
                          title: l10n.messagesConversationDeleted,
                          body: widget.deletedPartnerKey != null
                              ? l10n.messagesConversationDeletedNoticeDeletedAccount
                              : l10n.messagesConversationDeletedNotice,
                        )
                      : _body(l10n),
                ),
                if (_loadError == null && !_loading && !_deleted)
                  widget.partnerId == null
                      ? _closedBar(l10n.messagesDeletedAccountClosed)
                      : _blocked
                          ? _closedBar(
                              l10n.messagesBlockedNotice(_displayName(l10n)),
                              action: TextButton(
                                key: const ValueKey('message-unblock'),
                                onPressed: _blockBusy ? null : _unblock,
                                child: Text(l10n.messagesUnblock),
                              ),
                            )
                          : _request
                              ? _requestBar(l10n)
                              : _composerBar(l10n),
              ],
            ),
    );
  }

  Widget _body(AppLocalizations l10n) {
    if (_loading) {
      return ListSkeleton(
        label: l10n.commonLoading,
        rows: 6,
        rowHeight: 52,
        hasLeading: false,
      );
    }
    if (_loadError != null) {
      return AppErrorState(message: l10n.messagesThreadLoadError, onRetry: _load);
    }
    if (_messages.isEmpty && _pending.isEmpty) {
      return EmptyState(
        icon: Icons.chat_bubble_outline,
        title: l10n.messagesThreadEmpty,
      );
    }
    final tag = localeToTag(Localizations.localeOf(context));
    final me = widget.api.userId;
    final seen = seenReceipt(_messages, me);
    // Reversed so the newest message sits at the bottom and the list opens
    // there, the way every conversation does.
    final items = <Widget>[
      for (final p in _pending.reversed)
        DmBubble(
          key: ValueKey(p.localId),
          mine: true,
          sending: true,
          body: p.body,
          time: formatTime(p.createdAt, tag),
          sendingLabel: l10n.messagesSending,
          onOpenLink: _openLink,
        ),
      for (final m in _messages.reversed)
        DmBubble(
          key: ValueKey(m.id),
          mine: m.senderId == me,
          unsentLabel:
              m.unsentAt != null || (m.body == null && m.imageId == null)
                  ? l10n.messagesUnsentPlaceholder
                  : null,
          onOpenLink: _openLink,
          body: m.body == null ||
                  _isCoachShare(m) ||
                  (hasDmRouteAttachment(m.routeId) &&
                      bodyRestatesAttachment(m.body!, m.routeId!))
              ? null
              : m.body,
          time: _stamp(m.createdAt, tag),
          seenLabel: seen?.id == m.id
              ? l10n.messagesSeenAt(_stamp(seen!.seenAt!, tag))
              : null,
          editedLabel: m.editedAt != null && m.unsentAt == null
              ? l10n.messagesEdited
              : null,
          aiAssisted: m.unsentAt == null &&
                  parseDmKind(m.kind) == 'ai_assisted'
              ? (label: l10n.coachAssistMarker, title: l10n.coachAssistMarkerTitle)
              : null,
          onLongPress: m.unsentAt == null ? () => _showOptions(m) : null,
          longPressHint: l10n.messagesOptionsHint,
          attachment: m.unsentAt == null && m.body != null && _isCoachShare(m)
              ? CoachShareCard(
                  api: widget.api,
                  body: m.body!,
                  mine: m.senderId == me,
                  coachMessageId: m.coachMessageId,
                  partnerName: _partnerName ?? l10n.profileRunnerFallback,
                  onOpenSource: widget.onOpenCoachSource,
                )
              : m.unsentAt == null && hasDmRouteAttachment(m.routeId)
              ? DmRouteAttachment(
                  api: widget.api,
                  routeId: m.routeId!,
                  refreshTick: _refreshTick,
                  onOpen: widget.onOpenRoute,
                )
              : m.unsentAt == null && m.imageId != null
              ? DmPhoto(
                  key: ValueKey('dm-photo-${m.imageId}'),
                  api: widget.api,
                  imageId: m.imageId!,
                  color: m.senderId == me
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSurface,
                )
              : null,
          footer: m.unsentAt == null
              ? DmReactionChips(
                  messageId: m.id,
                  rows: _reactions,
                  viewerId: me,
                  canReact: _canReact(m),
                  onSet: (r) => _react(m, r),
                )
              : null,
        ),
      if (_hasMore)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: TextButton(
              onPressed: _loadingEarlier ? null : _loadEarlier,
              child: Text(l10n.messagesLoadEarlier),
            ),
          ),
        ),
    ];
    return ListView(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: items,
    );
  }

  static String _stamp(DateTime at, String tag) {
    final local = at.toLocal();
    final now = DateTime.now();
    final today = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    return today ? formatTime(at, tag) : formatDateTime(at, tag);
  }

  /// Stands in for the composer when there is no one to reply to: the
  /// partner deleted their account, or the viewer has blocked them.
  Widget _closedBar(String message, {Widget? action}) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            if (action != null) ...[const SizedBox(width: 8), action],
          ],
        ),
      ),
    );
  }

  Widget _requestBar(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final canDecline = !_requestBusy && _requestThrough != null;
    return SafeArea(
      top: false,
      child: Container(
        key: const ValueKey('message-request-bar'),
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.messagesRequestNotice(_displayName(l10n)),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: const ValueKey('message-request-accept'),
                  onPressed: _requestBusy ? null : _acceptRequest,
                  child: Text(l10n.messagesRequestAccept),
                ),
                OutlinedButton(
                  key: const ValueKey('message-request-decline'),
                  onPressed: canDecline ? _confirmDecline : null,
                  child: Text(l10n.messagesRequestDecline),
                ),
                OutlinedButton(
                  key: const ValueKey('message-request-block'),
                  onPressed: canDecline ? _toggleBlock : null,
                  child: Text(l10n.messagesBlock),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _composerBar(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final photo = _photoDraft;
    final canSend = !_sending &&
        !_preparingPhoto &&
        (_composer.text.trim().isNotEmpty || photo != null);
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (photo != null) ...[
              Row(
                key: const ValueKey('dm-photo-draft'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: Image.memory(
                      photo,
                      height: 96,
                      fit: BoxFit.cover,
                      semanticLabel: l10n.messagesPhotoDraftAlt,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('dm-photo-remove'),
                    tooltip: l10n.messagesPhotoRemove,
                    icon: const Icon(Icons.close),
                    onPressed: _sending
                        ? null
                        : () => setState(() => _photoDraft = null),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            _composerRow(l10n, canSend),
          ],
        ),
      ),
    );
  }

  Widget _composerRow(AppLocalizations l10n, bool canSend) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_photosEnabled) ...[
            IconButton(
              key: const ValueKey('dm-attach-photo'),
              tooltip: l10n.messagesPhotoAttach,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              onPressed: _sending || _preparingPhoto ? null : _pickPhoto,
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: TextField(
              key: const ValueKey('message-composer'),
              controller: _composer,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: [
                LengthLimitingTextInputFormatter(kDirectMessageMaxLength),
              ],
              decoration: InputDecoration(
                hintText: l10n.messagesComposerHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            key: const ValueKey('message-send'),
            tooltip: l10n.messagesSend,
            icon: const Icon(Icons.send),
            onPressed: canSend ? _send : null,
          ),
        ],
      );
}

bool _isCoachShare(DirectMessageRow m) => parseDmKind(m.kind) == 'coach_share';

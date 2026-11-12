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
import '../coach_share.dart' show parseDmKind;
import '../dm_edit.dart';
import '../dm_image.dart';
import '../dm_image_encode.dart';
import '../dm_reactions.dart';
import '../dm_send_error.dart';
import '../group_errors.dart';
import '../group_messages.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../widgets/confirm_destructive.dart';
import '../widgets/dm_bubble.dart';
import '../widgets/dm_photo.dart';
import '../widgets/dm_reaction_chips.dart';
import '../widgets/error_state.dart';
import '../widgets/group_members_sheet.dart';
import '../widgets/report_sheet.dart';
import '../widgets/top_banner.dart';
import 'message_thread_screen.dart' show kMessageThreadPollInterval;

/// What a runner was typing into each group, per account, so leaving a
/// group and coming back keeps the draft and a draft never follows the
/// reader into another group's audience (web keeps them per group too).
final Map<String, String> _groupDrafts = {};

/// A group conversation (issue #1365 slice 3, group_messages.md § 3,
/// decisions § 2468). Mirrors web's `/messages/group/[id]`.
///
/// Everything this screen shows comes through the read rule
/// (private.can_read_message): an active member reads from the moment they
/// accepted, someone who left reads only their own messages, and the
/// viewer's own block leaves a placeholder where the blocked person's
/// message was. A group the viewer is not in, one that does not exist and
/// one they left without writing anything all read the same: not available.
///
/// It reuses the 1:1 thread's bubble, edit dialog, reactions, photos,
/// unsend and report, on the same 10 s poll (decisions § 2223). Leave cannot
/// be undone from the app, so it is confirmed.
class GroupThreadScreen extends StatefulWidget {
  const GroupThreadScreen({
    super.key,
    required this.api,
    required this.conversationId,
    this.title,
    this.initialMuted,
    this.initialLeft = false,
    this.pollInterval = kMessageThreadPollInterval,
    this.pickPhoto,
    this.openLink,
  });

  final ApiClient api;
  final String conversationId;

  /// The inbox row's title. Opened from elsewhere (a notification), the row
  /// is read once the thread loads.
  final String? title;
  final bool? initialMuted;

  /// The inbox row says the viewer left this group.
  final bool initialLeft;
  final Duration pollInterval;

  /// The bytes of a photo the runner picked, or null when they cancelled.
  /// Defaults to the gallery picker; tests inject it.
  final Future<Uint8List?> Function()? pickPhoto;

  /// Opens a link from a message. Defaults to the external browser.
  final Future<bool> Function(Uri uri)? openLink;

  @override
  State<GroupThreadScreen> createState() => _GroupThreadScreenState();
}

enum _Membership { unknown, active, outside }

class _GroupThreadScreenState extends State<GroupThreadScreen>
    with WidgetsBindingObserver {
  final _composer = TextEditingController();
  Timer? _poll;

  /// The server's `group_messages` flag; null until read and while a failed
  /// read leaves it unknown, which shows nothing of the group (fail-closed)
  /// and is read again on the next poll. Only a definite false is "not
  /// available".
  bool? _enabled;
  _Membership _membership = _Membership.unknown;
  List<GroupMember> _members = const [];
  bool _loading = true;
  Object? _loadError;
  List<DirectMessageRow> _messages = const [];
  List<GroupPlaceholder> _placeholders = const [];
  Map<String, ({String? name, String? avatarUrl})> _profiles = const {};
  List<DmReactionRow> _reactions = const [];
  bool _hasMore = false;
  bool _loadingEarlier = false;
  bool _refreshing = false;
  String? _markedThroughId;
  String? _title;
  bool _muted = false;
  bool _left = false;
  bool _busy = false;
  bool _sending = false;
  bool _photosEnabled = false;
  Uint8List? _photoDraft;
  bool _preparingPhoto = false;

  /// Bumped by a write newer than a poll's read (a send, an unsend, an
  /// edit), so a poll already in flight is dropped.
  int _localWrites = 0;
  int _reactionWrites = 0;
  int _reactionReadSeq = 0;

  String get _draftKey => '${widget.api.userId}|${widget.conversationId}';

  bool get _active => _membership == _Membership.active;

  bool get _notAvailable =>
      _enabled == false ||
      (_membership == _Membership.outside && !_left && _messages.isEmpty);

  @override
  void initState() {
    super.initState();
    _title = widget.title;
    _muted = widget.initialMuted ?? false;
    _left = widget.initialLeft;
    _composer.text = _groupDrafts[_draftKey] ?? '';
    _composer.addListener(_onComposerChanged);
    WidgetsBinding.instance.addObserver(this);
    if (widget.api.userId == null) return;
    _load();
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

  void _onComposerChanged() {
    final text = _composer.text;
    if (text.isEmpty) {
      _groupDrafts.remove(_draftKey);
    } else {
      _groupDrafts[_draftKey] = text;
    }
    setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final on = await widget.api.fetchGroupMessagesEnabled();
    if (!mounted) return;
    if (on != true) {
      setState(() {
        _enabled = on;
        _loading = false;
      });
      return;
    }
    _enabled = true;
    try {
      final results = await Future.wait([
        widget.api.fetchGroupThread(widget.conversationId),
        _loadMembers(),
      ]);
      if (!mounted) return;
      final page = results.first as DmThreadPage;
      _localWrites++;
      setState(() {
        _messages = _membership == _Membership.outside
            ? _ownOnly(page.messages)
            : page.messages;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (e) {
      debugPrint('group thread load failed: ${safeErrorLabel(e)}');
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
      return;
    }
    if (_title == null) unawaited(_loadRow());
    unawaited(_loadPhotosEnabled());
    _afterRead();
  }

  /// A thread opened from outside the inbox reads its row for the title, the
  /// mute and whether the viewer left. A failure keeps the fallback title.
  Future<void> _loadRow() async {
    try {
      final rows = await widget.api.fetchDmThreads();
      for (final t in rows) {
        if (t.isGroup && t.conversationId == widget.conversationId) {
          if (!mounted) return;
          setState(() {
            _title ??= t.title;
            _muted = t.muted;
            _left = t.membershipState == 'left';
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('group row read failed: ${safeErrorLabel(e)}');
    }
  }

  Future<void> _loadPhotosEnabled() async {
    final on = await widget.api.fetchDmImagesEnabled();
    if (mounted && on != _photosEnabled) setState(() => _photosEnabled = on);
  }

  List<DirectMessageRow> _ownOnly(List<DirectMessageRow> rows) {
    final me = widget.api.userId;
    return [
      for (final m in rows)
        if (m.senderId == me) m,
    ];
  }

  /// 'active' once group_members answers, 'outside' on its P0002: the viewer
  /// left, was removed, never belonged, or the group does not exist. D12:
  /// someone outside reads only their own messages, so what the screen still
  /// holds from before goes at once rather than waiting for a reload.
  Future<void> _loadMembers() async {
    try {
      final rows = await widget.api.fetchGroupMembers(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _members = rows;
        _membership = _Membership.active;
      });
    } on GroupActionRefused catch (e) {
      if (e.reason != GroupRefusal.notFound || !mounted) return;
      setState(() {
        _members = const [];
        _membership = _Membership.outside;
        _messages = _ownOnly(_messages);
        _placeholders = const [];
        _reactions = const [];
      });
    } catch (e) {
      debugPrint('group members read failed: ${safeErrorLabel(e)}');
    }
  }

  /// The auxiliary reads after any thread read. Each failure keeps what is
  /// shown; the next poll tries again.
  void _afterRead() {
    unawaited(_loadProfiles());
    unawaited(_loadPlaceholders());
    unawaited(_loadReactions());
    unawaited(_markRead());
  }

  Future<void> _loadProfiles() async {
    final known = {for (final m in _members) m.userId, ..._profiles.keys};
    final missing = {
      for (final m in _messages)
        if (!known.contains(m.senderId)) m.senderId,
    }.toList();
    if (missing.isEmpty) return;
    final found = await widget.api.fetchGroupProfiles(missing);
    if (!mounted || found.isEmpty) return;
    setState(() => _profiles = {..._profiles, ...found});
  }

  Future<void> _loadPlaceholders() async {
    if (!_active) {
      if (_placeholders.isNotEmpty) setState(() => _placeholders = const []);
      return;
    }
    try {
      final rows = await widget.api.fetchGroupBlockedPlaceholders(
          widget.conversationId, placeholdersSince(_messages, _hasMore));
      if (mounted && _active) setState(() => _placeholders = rows);
    } catch (e) {
      debugPrint('group placeholders read failed: ${safeErrorLabel(e)}');
    }
  }

  Future<void> _loadReactions() async {
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
      debugPrint('group reactions read failed: ${safeErrorLabel(e)}');
    }
  }

  /// Through the newest message on screen; nobody else learns of it (D6).
  Future<void> _markRead() async {
    if (!_active || _messages.isEmpty) return;
    final newest = _messages.last;
    if (newest.id == _markedThroughId) return;
    try {
      await widget.api.markGroupRead(widget.conversationId, newest.id);
      _markedThroughId = newest.id;
    } catch (e) {
      debugPrint('group mark-read failed: ${safeErrorLabel(e)}');
    }
  }

  /// Re-reads the newest page and the roster. Skipped in the background and
  /// under another screen; a failed poll keeps what is shown. A page that
  /// does not reach the newest message on screen replaces the list, as the
  /// 1:1 thread does, so no gap is left that "load earlier" cannot fill.
  Future<void> _refresh() async {
    if (_loading || _refreshing) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    if (_enabled == null) return _load();
    if (_loadError != null || _enabled != true) return;
    _refreshing = true;
    final writesAtStart = _localWrites;
    try {
      final results = await Future.wait([
        widget.api.fetchGroupThread(widget.conversationId),
        _loadMembers(),
      ]);
      final page = results.first as DmThreadPage;
      if (!mounted || writesAtStart != _localWrites) return;
      setState(() {
        final fresh = _membership == _Membership.outside
            ? _ownOnly(page.messages)
            : page.messages;
        final gap = page.hasMore &&
            fresh.isNotEmpty &&
            _messages.isNotEmpty &&
            _compareOrder(fresh.first, _messages.last) > 0;
        if (gap) {
          _messages = fresh;
          _hasMore = true;
        } else {
          _messages = _merge(
              _membership == _Membership.outside
                  ? _ownOnly(_messages)
                  : _messages,
              fresh);
        }
      });
      _afterRead();
    } catch (e) {
      debugPrint('group thread poll failed: ${safeErrorLabel(e)}');
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _loadEarlier() async {
    if (_loadingEarlier || _messages.isEmpty) return;
    setState(() => _loadingEarlier = true);
    try {
      final page = await widget.api
          .fetchGroupThread(widget.conversationId, before: _messages.first);
      if (!mounted) return;
      setState(() {
        _messages = _merge(_messages, page.messages);
        _hasMore = page.hasMore;
      });
      _afterRead();
    } catch (e) {
      debugPrint('group thread older page failed: ${safeErrorLabel(e)}');
      if (mounted) {
        showTopBanner(
            context, AppLocalizations.of(context).messagesLoadEarlierFailed);
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

  static int _compareOrder(DirectMessageRow x, DirectMessageRow y) {
    final at = x.createdAt.compareTo(y.createdAt);
    return at != 0 ? at : x.id.compareTo(y.id);
  }

  String _senderName(AppLocalizations l10n, String id) {
    for (final m in _members) {
      if (m.userId == id && m.name != null) return m.name!;
    }
    return _profiles[id]?.name ?? l10n.profileRunnerFallback;
  }

  String? _senderAvatar(String id) {
    for (final m in _members) {
      if (m.userId == id && m.avatarUrl != null) return m.avatarUrl;
    }
    return _profiles[id]?.avatarUrl;
  }

  /// The newest rename line names the title, so a rename shows here on the
  /// next read without another round trip. An unsent one names nothing.
  String _displayTitle(AppLocalizations l10n) {
    for (final m in _messages.reversed) {
      if (m.kind == 'group_renamed') {
        if (m.unsentAt == null && m.body != null) return m.body!;
        break;
      }
    }
    return _title ?? l10n.groupsGroupFallback;
  }

  int get _activeCount => _members.where((m) => !m.invited).length;

  bool _canReact(DirectMessageRow m) =>
      _active && m.unsentAt == null && widget.api.userId != null;

  Future<void> _react(DirectMessageRow m, String? next) async {
    final me = widget.api.userId;
    if (me == null || !_canReact(m)) return;
    final previous = myDmReaction(_reactions, m.id, me);
    _reactionWrites++;
    setState(() => _reactions = withMyDmReaction(_reactions, m.id, me, next));
    try {
      await widget.api.setDmReaction(m.id, next);
    } catch (e) {
      debugPrint('group reaction failed: ${safeErrorLabel(e)}');
      if (!mounted) return;
      _reactionWrites++;
      setState(() =>
          _reactions = withMyDmReaction(_reactions, m.id, me, previous));
      showTopBanner(
          context, dmReactionErrorMessage(AppLocalizations.of(context), e));
    }
  }

  Future<void> _openLink(String href) async {
    final l10n = AppLocalizations.of(context);
    var opened = false;
    try {
      final uri = Uri.parse(href);
      if (uri.scheme == 'http' || uri.scheme == 'https') {
        opened = await (widget.openLink ??
            (u) => launchUrl(u, mode: LaunchMode.externalApplication))(uri);
      }
    } catch (e) {
      debugPrint('group message link open failed: ${safeErrorLabel(e)}');
    }
    if (!opened && mounted) showTopBanner(context, l10n.messagesLinkOpenFailed);
  }

  static Future<Uint8List?> _pickFromGallery() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: kDmImageMaxEdge.toDouble(),
      maxHeight: kDmImageMaxEdge.toDouble(),
    );
    return file?.readAsBytes();
  }

  Future<void> _pickPhoto() async {
    if (_preparingPhoto || _sending) return;
    final l10n = AppLocalizations.of(context);
    Uint8List? raw;
    try {
      raw = await (widget.pickPhoto ?? _pickFromGallery)();
    } catch (e) {
      debugPrint('group photo pick failed: ${safeErrorLabel(e)}');
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
      if (mounted) setState(() => _photoDraft = jpeg);
    } catch (e) {
      debugPrint('group photo encode failed: $e');
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

  Future<void> _send() async {
    final body = _composer.text.trim();
    final photo = _photoDraft;
    if (!_active ||
        _sending ||
        _preparingPhoto ||
        (body.isEmpty && photo == null)) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    setState(() => _sending = true);
    var uploaded = false;
    try {
      String? imageId;
      if (photo != null) {
        imageId = await widget.api.uploadDmImage(photo);
        uploaded = true;
      }
      final row = await widget.api
          .sendGroupMessage(widget.conversationId, body, imageId: imageId);
      if (!mounted) return;
      _localWrites++;
      _composer.clear();
      setState(() {
        _messages = _merge(_messages, [row]);
        if (identical(_photoDraft, photo)) _photoDraft = null;
      });
    } catch (e) {
      debugPrint('group send failed: ${safeErrorLabel(e)}');
      if (!mounted) return;
      showTopBanner(
        context,
        groupSendErrorMessage(l10n, e,
            withPhoto: photo != null, uploaded: uploaded),
        duration: kTopBannerMaxDuration,
      );
      // A refusal is most often a removal the poll has not shown yet.
      unawaited(_loadMembers());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showOptions(DirectMessageRow m) async {
    final l10n = AppLocalizations.of(context);
    final mine = m.senderId == widget.api.userId;
    final editable =
        _active && canEditDm(m, widget.api.userId, DateTime.now());
    final canReact = _canReact(m);
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canReact)
              ListTile(
                key: const ValueKey('message-action-react'),
                leading: const Icon(Icons.add_reaction_outlined),
                title: Text(l10n.messagesReact),
                onTap: () => Navigator.pop(ctx, 'react'),
              ),
            if (editable)
              ListTile(
                key: const ValueKey('message-action-edit'),
                leading: const Icon(Icons.edit_outlined),
                title: Text(l10n.messagesEdit),
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
            if (mine)
              ListTile(
                key: const ValueKey('message-action-unsend'),
                leading: Icon(Icons.undo,
                    color: AppSemanticColors.of(ctx).danger),
                title: Text(l10n.messagesUnsend),
                onTap: () => Navigator.pop(ctx, 'unsend'),
              )
            else
              ListTile(
                key: const ValueKey('message-action-report'),
                leading: const Icon(Icons.flag_outlined),
                title: Text(l10n.messagesReport),
                onTap: () => Navigator.pop(ctx, 'report'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'react':
        final current = myDmReaction(_reactions, m.id, widget.api.userId);
        final picked = await showDmReactionPicker(context, current: current);
        if (picked == null || !mounted) return;
        await _react(m, picked == current ? null : picked);
      case 'edit':
        final row = await showDialog<DirectMessageRow>(
          context: context,
          builder: (_) => DmEditMessageDialog(
            initial: m.body ?? '',
            save: (body) => widget.api.editDm(m.id, body),
          ),
        );
        if (row == null || !mounted) return;
        _localWrites++;
        setState(() => _messages = _merge(_messages, [row]));
      case 'unsend':
        await _unsend(m);
      case 'report':
        await showReportSheet(
          context,
          api: widget.api,
          targetKind: 'direct_message',
          targetId: m.id,
        );
    }
  }

  /// Unsend cannot be undone, so it is confirmed. A leaver can still unsend
  /// their own messages (D11).
  Future<void> _unsend(DirectMessageRow m) async {
    final l10n = AppLocalizations.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.messagesUnsendConfirmTitle,
      body: l10n.messagesUnsendConfirmBody,
      confirmLabel: l10n.messagesUnsend,
    );
    if (!ok || !mounted) return;
    try {
      final row = await widget.api.unsendDm(m.id);
      if (!mounted) return;
      _localWrites++;
      setState(() => _messages = _merge(_messages, [row]));
    } catch (e) {
      debugPrint('group unsend failed: ${safeErrorLabel(e)}');
      if (mounted) showTopBanner(context, l10n.messagesUnsendFailed);
    }
  }

  Future<void> _toggleMuted() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final next = !_muted;
    setState(() => _busy = true);
    try {
      await widget.api
          .setDmConversationMuted(widget.conversationId, muted: next);
      if (!mounted) return;
      setState(() => _muted = next);
      if (next) showTopBanner(context, l10n.messagesMutedToast);
    } catch (e) {
      debugPrint('group mute failed: ${safeErrorLabel(e)}');
      if (mounted) {
        showTopBanner(context,
            l10n.messagesConversationActionFailed(friendlyError(l10n, e)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Leaving takes effect on the server at once and rejoining needs a new
  /// invitation, so it is confirmed rather than offered an undo.
  Future<void> _leave() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final title = _displayTitle(l10n);
    final ok = await confirmDestructive(
      context,
      title: l10n.groupsLeaveConfirmTitle(title),
      body: l10n.groupsLeaveConfirmMessage,
      confirmLabel: l10n.groupsLeave,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.leaveGroup(widget.conversationId);
      if (!mounted) return;
      final rootContext = Navigator.of(context, rootNavigator: true).context;
      Navigator.of(context).pop();
      if (rootContext.mounted) {
        showTopBanner(rootContext, l10n.groupsLeftToast(title));
      }
    } catch (e) {
      debugPrint('group leave failed: ${safeErrorLabel(e)}');
      if (!mounted) return;
      setState(() => _busy = false);
      showTopBanner(
        context,
        l10n.groupsActionFailed(
            groupErrorMessage(l10n, e, fallback: l10n.authErrorGeneric)),
      );
    }
  }

  Future<void> _openMembers() {
    final l10n = AppLocalizations.of(context);
    return showGroupMembersSheet(
      context,
      api: widget.api,
      conversationId: widget.conversationId,
      title: _displayTitle(l10n),
      members: _members,
      onChanged: () async {
        await _loadMembers();
        unawaited(_refresh());
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final signedIn = widget.api.userId != null;
    final title = _displayTitle(l10n);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _notAvailable
            ? null
            : Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Icon(Icons.group,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          key: const ValueKey('group-title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_active)
                          Text(
                            l10n.groupsMemberCount(_activeCount),
                            key: const ValueKey('group-member-count'),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
        actions: [
          if (_active) ...[
            IconButton(
              key: const ValueKey('group-mute-toggle'),
              tooltip: _muted ? l10n.messagesUnmute : l10n.messagesMute,
              isSelected: _muted,
              icon: const Icon(Icons.notifications_off_outlined),
              selectedIcon: const Icon(Icons.notifications_active_outlined),
              onPressed: _busy ? null : _toggleMuted,
            ),
            IconButton(
              key: const ValueKey('group-members-button'),
              tooltip: l10n.groupsMembersButton,
              icon: const Icon(Icons.group_outlined),
              onPressed: _openMembers,
            ),
            PopupMenuButton<String>(
              key: const ValueKey('group-menu'),
              onSelected: (v) {
                if (v == 'leave') _leave();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  key: const ValueKey('group-leave'),
                  value: 'leave',
                  enabled: !_busy,
                  child: Text(l10n.groupsLeave),
                ),
              ],
            ),
          ],
        ],
      ),
      body: !signedIn
          ? const SizedBox.shrink()
          : Column(
              children: [
                Expanded(child: _body(l10n)),
                if (!_notAvailable && !_loading && _loadError == null)
                  if (_membership == _Membership.outside)
                    _closedBar(l10n.groupsLeftNotice)
                  else if (_active)
                    _composerBar(l10n),
              ],
            ),
    );
  }

  Widget _closedBar(String message) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        key: const ValueKey('group-left-notice'),
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        padding: const EdgeInsets.all(12),
        child: Text(
          message,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _systemLine(String text, {Key? key}) {
    final theme = Theme.of(context);
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }

  Widget _body(AppLocalizations l10n) {
    if (_notAvailable) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.groupsNotAvailable,
            key: const ValueKey('group-unavailable'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_loading || _enabled == null) {
      return ListSkeleton(
        label: l10n.commonLoading,
        rows: 6,
        rowHeight: 52,
        hasLeading: false,
      );
    }
    if (_loadError != null) {
      return ErrorState(message: l10n.messagesThreadLoadError, onRetry: _load);
    }
    final tag = localeToTag(Localizations.localeOf(context));
    final me = widget.api.userId;
    final items = mergeGroupThread(_messages, _placeholders);
    final scheme = Theme.of(context).colorScheme;
    final children = <Widget>[
      for (final item in items.reversed)
        switch (item) {
          GroupBlockedItem(:final id) => _systemLine(
              l10n.groupsBlockedPlaceholder,
              key: ValueKey('group-blocked-$id'),
            ),
          GroupMessageItem(:final message) =>
            message.kind == 'group_renamed'
                ? _systemLine(
                    message.unsentAt != null || message.body == null
                        ? l10n.messagesUnsentPlaceholder
                        : message.senderId == me
                            ? l10n.groupsRenamedLineYou(message.body!)
                            : l10n.groupsRenamedLine(
                                _senderName(l10n, message.senderId),
                                message.body!),
                    key: ValueKey('group-renamed-${message.id}'),
                  )
                : _bubble(l10n, message, me, tag, scheme),
        },
      if (_messages.isEmpty && _placeholders.isEmpty)
        _systemLine(
          _active ? l10n.groupsEmptyThread : l10n.messagesThreadEmpty,
          key: const ValueKey('group-empty'),
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
        )
      else if (_active)
        _systemLine(
          l10n.groupsHistoryNote,
          key: const ValueKey('group-history-note'),
        ),
    ];
    return ListView(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: children,
    );
  }

  Widget _bubble(
    AppLocalizations l10n,
    DirectMessageRow m,
    String? me,
    String tag,
    ColorScheme scheme,
  ) {
    final mine = m.senderId == me;
    final live = m.unsentAt == null;
    return DmBubble(
      key: ValueKey(m.id),
      mine: mine,
      senderName: mine ? null : _senderName(l10n, m.senderId),
      avatar: mine
          ? null
          : IdentityAvatar(
              seed: m.senderId,
              name: _senderName(l10n, m.senderId),
              imageUrl: _senderAvatar(m.senderId),
              size: 28,
            ),
      unsentLabel: !live || (m.body == null && m.imageId == null)
          ? l10n.messagesUnsentPlaceholder
          : null,
      body: m.body,
      time: _stamp(m.createdAt, tag),
      editedLabel: m.editedAt != null && live ? l10n.messagesEdited : null,
      aiAssisted: live && parseDmKind(m.kind) == 'ai_assisted'
          ? (label: l10n.coachAssistMarker, title: l10n.coachAssistMarkerTitle)
          : null,
      onOpenLink: _openLink,
      onLongPress: live ? () => _showOptions(m) : null,
      longPressHint: l10n.messagesOptionsHint,
      attachment: live && m.imageId != null
          ? DmPhoto(
              key: ValueKey('dm-photo-${m.imageId}'),
              api: widget.api,
              imageId: m.imageId!,
              color: mine ? scheme.onPrimary : scheme.onSurface,
            )
          : null,
      footer: live
          ? DmReactionChips(
              messageId: m.id,
              rows: _reactions,
              viewerId: me,
              canReact: _canReact(m),
              onSet: (r) => _react(m, r),
            )
          : null,
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
            Row(
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
                  child: Semantics(
                    label: l10n.groupsComposerLabel(_displayTitle(l10n)),
                    child: TextField(
                      key: const ValueKey('message-composer'),
                      controller: _composer,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(
                            kDirectMessageMaxLength),
                      ],
                      decoration: InputDecoration(
                        hintText: l10n.messagesComposerHint,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
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
            ),
          ],
        ),
      ),
    );
  }
}

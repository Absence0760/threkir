import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show IdentityAvatar, ListSkeleton;
import '../auth_error.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../mentions.dart';
import '../run_reactions.dart';
import '../screens/profile_screen.dart';
import '../social_service.dart';
import '../widgets/report_sheet.dart';
import '../widgets/top_banner.dart';
import '../widgets/undo_bar.dart';
import '../undo_queue.dart';

/// Run-detail kudos pill + one-level comment thread + composer. Mirrors
/// the web `RunSocial.svelte` component.
class RunSocialSection extends StatefulWidget {
  final ApiClient api;
  final String runId;

  /// Owner gates the "delete any comment" affordance.
  final String? runOwnerId;

  const RunSocialSection({
    super.key,
    required this.api,
    required this.runId,
    this.runOwnerId,
  });

  @override
  State<RunSocialSection> createState() => _RunSocialSectionState();
}

class _RunSocialSectionState extends State<RunSocialSection> {
  bool _loading = true;
  bool _kudosBusy = false;
  bool _posting = false;

  EngagementSummary _eng = const EngagementSummary(
    kudosCount: 0,
    viewerHasKudos: false,
    commentCount: 0,
  );
  List<RunCommentWithAuthor> _comments = const [];

  // Cached viewer profile so optimistic comment append can render with
  // the right display name + avatar instead of a synthesized fallback.
  PublicProfile? _viewerProfile;

  String? _replyTo;

  List<ReactionTally> _reactions = reactionTallies(const []);
  String? _reactionBusy;
  Map<String, ({int count, bool viewerLiked})> _likes = const {};
  String? _likeBusy;
  Map<String, String> _mentionIds = const {};

  // The @mention picker serves one composer at a time.
  TextEditingController? _mentionCtrl;
  int _mentionStart = 0;
  int _mentionCaret = 0;
  List<PeopleSuggestion> _mentionPeople = const [];
  int _mentionSeq = 0;

  final _draftCtrl = TextEditingController();
  final _replyCtrl = TextEditingController();

  String? get _viewerId => widget.api.userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _draftCtrl.dispose();
    _replyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final viewerId = _viewerId;
      final results = await Future.wait<dynamic>([
        widget.api.fetchEngagementSummaries([widget.runId]),
        widget.api.fetchRunCommentsWithAuthors(widget.runId),
        viewerId == null
            ? Future.value(null)
            : widget.api.fetchProfileSummary(viewerId),
      ]);
      final engMap =
          results[0]
              as Map<
                String,
                ({int kudosCount, bool viewerHasKudos, int commentCount})
              >;
      final cs = results[1] as List<RunCommentWithAuthor>;
      final viewer = results[2] as ProfileSummary?;
      final entry = engMap[widget.runId];
      if (!mounted) return;
      setState(() {
        _eng = entry == null
            ? const EngagementSummary(
                kudosCount: 0,
                viewerHasKudos: false,
                commentCount: 0,
              )
            : EngagementSummary(
                kudosCount: entry.kudosCount,
                viewerHasKudos: entry.viewerHasKudos,
                commentCount: entry.commentCount,
              );
        _comments = cs;
        _viewerProfile = viewer;
        _loading = false;
      });
      await _loadExtras(cs);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // Reactions, comment likes and mention links are an L4 layer over kudos and
  // comments: each read fails on its own, is logged, and leaves its part
  // empty without touching the comments already on screen.
  Future<void> _loadExtras(List<RunCommentWithAuthor> cs) async {
    try {
      final rows = await widget.api.fetchRunReactionSummary(widget.runId);
      if (mounted) setState(() => _reactions = reactionTallies(rows));
    } catch (e) {
      debugPrint('run social reactions error: $e');
    }
    try {
      final likes = await widget.api.fetchRunCommentLikeSummary(widget.runId);
      if (mounted) setState(() => _likes = likes);
    } catch (e) {
      debugPrint('run social likes error: $e');
    }
    try {
      final ids = await widget.api.resolveMentionHandles([
        for (final c in cs) ...parseMentionHandles(c.comment.body),
      ]);
      if (mounted) setState(() => _mentionIds = ids);
    } catch (e) {
      debugPrint('run social mentions error: $e');
    }
  }

  String _reactionLabel(AppLocalizations l10n, String key) => switch (key) {
        'fire' => l10n.runSocialReactionFire,
        'strong' => l10n.runSocialReactionStrong,
        'trophy' => l10n.runSocialReactionTrophy,
        'thumbs_up' => l10n.runSocialReactionThumbsUp,
        _ => l10n.runSocialReactionWave,
      };

  Future<void> _toggleReaction(String key) async {
    if (_reactionBusy != null || _viewerId == null) return;
    if (widget.runOwnerId != null && widget.runOwnerId == _viewerId) return;
    final tally = _reactions.firstWhere((t) => t.key == key);
    final nowReacted = !tally.viewerReacted;
    setState(() => _reactionBusy = key);
    try {
      final changed = nowReacted
          ? await widget.api.addRunReaction(widget.runId, key)
          : await widget.api.removeRunReaction(widget.runId, key);
      if (!mounted) return;
      setState(
        () => _reactions = applyReactionToggle(_reactions, key, nowReacted, changed),
      );
    } catch (e) {
      debugPrint('run social reaction error: $e');
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      showTopBanner(context, l10n.runSocialReactionError(friendlyError(l10n, e)));
    } finally {
      if (mounted) setState(() => _reactionBusy = null);
    }
  }

  Future<void> _toggleLike(RunCommentRow c) async {
    if (_likeBusy != null || _viewerId == null || c.authorId == _viewerId) return;
    final before = _likes[c.id] ?? (count: 0, viewerLiked: false);
    final nowLiked = !before.viewerLiked;
    setState(() => _likeBusy = c.id);
    try {
      final changed = nowLiked
          ? await widget.api.likeRunComment(c.id)
          : await widget.api.unlikeRunComment(c.id);
      if (!mounted) return;
      final delta = changed ? (nowLiked ? 1 : -1) : 0;
      setState(() {
        _likes = {
          ..._likes,
          c.id: (count: (before.count + delta).clamp(0, 1 << 30), viewerLiked: nowLiked),
        };
      });
    } catch (e) {
      debugPrint('run social like error: $e');
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      showTopBanner(context, l10n.runSocialLikeError(friendlyError(l10n, e)));
    } finally {
      if (mounted) setState(() => _likeBusy = null);
    }
  }

  void _closeMentions() {
    if (_mentionCtrl == null && _mentionPeople.isEmpty) return;
    setState(() {
      _mentionCtrl = null;
      _mentionPeople = const [];
    });
  }

  Future<void> _onComposerChanged(TextEditingController ctrl) async {
    final caret = ctrl.selection.baseOffset < 0
        ? ctrl.text.length
        : ctrl.selection.baseOffset;
    final q = activeMentionQuery(ctrl.text, caret);
    if (q == null || q.query.isEmpty) {
      _closeMentions();
      return;
    }
    final seq = ++_mentionSeq;
    try {
      // decisions § 269's search: the opt-out, minor and block filters all
      // apply, so the picker never offers someone People search would not.
      final found = await widget.api.searchPeople('@${q.query}', limit: 8);
      if (!mounted || seq != _mentionSeq) return;
      setState(() {
        _mentionCtrl = ctrl;
        _mentionStart = q.start;
        _mentionCaret = caret;
        _mentionPeople = [for (final p in found) if (p.handle != null) p];
      });
    } catch (e) {
      debugPrint('run social mention search error: $e');
    }
  }

  void _pickMention(PeopleSuggestion person) {
    final ctrl = _mentionCtrl;
    final handle = person.handle;
    if (ctrl == null || handle == null) return;
    final next = insertMention(ctrl.text, _mentionStart, _mentionCaret, handle);
    ctrl.value = TextEditingValue(
      text: next.text,
      selection: TextSelection.collapsed(offset: next.caret),
    );
    _closeMentions();
  }

  Widget? _mentionPickerFor(TextEditingController ctrl) {
    if (_mentionCtrl != ctrl || _mentionPeople.isEmpty) return null;
    return _MentionPicker(people: _mentionPeople, onPick: _pickMention);
  }

  Future<void> _toggleKudos() async {
    if (_kudosBusy || _viewerId == null) return;
    // RLS would reject self-kudos anyway; skip the round-trip.
    if (widget.runOwnerId != null && widget.runOwnerId == _viewerId) return;
    final before = _eng;
    setState(() {
      _kudosBusy = true;
      _eng = EngagementSummary(
        kudosCount: before.viewerHasKudos
            ? (before.kudosCount - 1).clamp(0, 1 << 30)
            : before.kudosCount + 1,
        viewerHasKudos: !before.viewerHasKudos,
        commentCount: before.commentCount,
      );
    });
    try {
      final changed = before.viewerHasKudos
          ? await widget.api.rescindKudos(widget.runId)
          : await widget.api.giveKudos(widget.runId);
      // A no-op (the server already matched the new state from another
      // tab against a stale local flag) means the optimistic +/-1 drifted
      // the count. Undo the delta while keeping the corrected flag.
      if (!changed && mounted) {
        setState(
          () => _eng = EngagementSummary(
            kudosCount: before.kudosCount,
            viewerHasKudos: !before.viewerHasKudos,
            commentCount: before.commentCount,
          ),
        );
      }
    } catch (e) {
      debugPrint('run social kudos error: $e');
      if (!mounted) return;
      setState(() => _eng = before);
      showTopBanner(
        context,
        AppLocalizations.of(context).runSocialKudosError(
          friendlyError(AppLocalizations.of(context), e),
        ),
      );
    } finally {
      if (mounted) setState(() => _kudosBusy = false);
    }
  }

  Future<void> _postComment({String? parentId}) async {
    final ctrl = parentId == null ? _draftCtrl : _replyCtrl;
    final body = ctrl.text.trim();
    if (body.isEmpty || _viewerId == null) return;
    setState(() => _posting = true);
    try {
      final inserted = await widget.api.addRunComment(
        runId: widget.runId,
        body: body,
        parentCommentId: parentId,
      );
      ctrl.clear();
      _closeMentions();
      if (!mounted) return;
      // Optimistically append the new comment. Was: re-fetch the whole
      // engagement + comments list — a 200-comment thread paid for the
      // round-trip + the parent ListView rebuild on every reply.
      final author =
          _viewerProfile ??
          PublicProfile(id: _viewerId!, displayName: null, avatarUrl: null);
      setState(() {
        if (parentId != null) _replyTo = null;
        _comments = [
          ..._comments,
          RunCommentWithAuthor(comment: inserted, author: author),
        ];
        _eng = EngagementSummary(
          kudosCount: _eng.kudosCount,
          viewerHasKudos: _eng.viewerHasKudos,
          commentCount: _eng.commentCount + 1,
        );
      });
    } catch (e) {
      debugPrint('run social post error: $e');
      if (!mounted) return;
      showTopBanner(
        context,
        AppLocalizations.of(context).runSocialPostError(
          friendlyError(AppLocalizations.of(context), e),
        ),
      );
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  /// One behaviour for both the author's own delete and the run owner's
  /// MODERATION delete: with the mutation deferred the actor can put the
  /// comment back untouched, which is more than the old modal offered once
  /// dismissed, and a button that asks on some rows and not others reads as a
  /// bug (decisions § 514).
  ///
  /// The optimistic filter drops the replies with the parent, mirroring the
  /// `parent_comment_id ON DELETE CASCADE` the commit will trigger — and it is
  /// exactly why the mutation has to be DEFERRED rather than compensated: once
  /// the cascade has run, no re-insert could bring those replies back.
  void _deleteComment(String commentId) {
    final l10n = AppLocalizations.of(context);
    final api = widget.api;
    final snapshot = _comments;
    final eng = _eng;
    final dropped = {
      commentId,
      for (final c in _comments)
        if (c.comment.parentCommentId == commentId) c.comment.id,
    };
    setState(() {
      _comments = _comments
          .where((c) => !dropped.contains(c.comment.id))
          .toList(growable: false);
      _eng = EngagementSummary(
        kudosCount: _eng.kudosCount,
        viewerHasKudos: _eng.viewerHasKudos,
        commentCount: (_eng.commentCount - dropped.length)
            .clamp(0, _eng.commentCount),
      );
    });
    deferDestructive(
      context,
      DeferredDestruction(
        message: l10n.runSocialCommentRemoved,
        commit: () => api.deleteRunComment(commentId),
        restore: () {
          if (!mounted) return;
          setState(() {
            _comments = snapshot;
            _eng = eng;
          });
        },
        onCommitError: (e) {
          debugPrint('run social delete error: $e');
          if (!mounted) return;
          showTopBanner(
              context, l10n.runSocialDeleteError(friendlyError(l10n, e)));
        },
      ),
    );
  }

  bool _canDelete(RunCommentRow c) {
    if (_viewerId == null) return false;
    if (c.authorId == _viewerId) return true;
    if (widget.runOwnerId != null && widget.runOwnerId == _viewerId) {
      return true;
    }
    return false;
  }

  bool _canReport(RunCommentRow c) =>
      _viewerId != null && c.authorId != _viewerId;

  void _reportComment(String commentId) {
    showReportSheet(
      context,
      api: widget.api,
      targetKind: 'comment',
      targetId: commentId,
    );
  }

  // A harassing comment needs a one-tap path to the author's profile, where
  // the block / report affordance lives. Mirrors the feed's author-tap.
  void _openAuthor(String userId) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ProfileScreen(api: widget.api, userId: userId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    if (_loading) {
      return ListSkeleton.section(label: l10n.commonLoading, rows: 3);
    }

    final topLevel = <RunCommentWithAuthor>[];
    final repliesByParent = <String, List<RunCommentWithAuthor>>{};
    for (final c in _comments) {
      final parent = c.comment.parentCommentId;
      if (parent == null) {
        topLevel.add(c);
      } else {
        repliesByParent.putIfAbsent(parent, () => []).add(c);
      }
    }

    final isOwn = widget.runOwnerId != null && widget.runOwnerId == _viewerId;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section header + kudos pill
          Row(
            children: [
              Expanded(
                child: Text(l10n.runSocialActivity,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium),
              ),
              _KudosPill(
                count: _eng.kudosCount,
                viewerHas: _eng.viewerHasKudos,
                disabled: _kudosBusy || _viewerId == null || isOwn,
                onTap: _toggleKudos,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Semantics(
            container: true,
            label: l10n.runSocialReactionsLabel,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in _reactions)
                  _ReactionChip(
                    tally: r,
                    label: _reactionLabel(l10n, r.key),
                    disabled: _reactionBusy != null || _viewerId == null || isOwn,
                    onTap: () => _toggleReaction(r.key),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Comments list
          if (topLevel.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                l10n.runSocialNoComments,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final c in topLevel) ...[
              _CommentTile(
                entry: c,
                like: _likes[c.comment.id] ?? (count: 0, viewerLiked: false),
                canLike: _viewerId != null &&
                    c.comment.authorId != _viewerId &&
                    _likeBusy == null,
                onLike: () => _toggleLike(c.comment),
                mentionIds: _mentionIds,
                onMentionTap: _openAuthor,
                canDelete: _canDelete(c.comment),
                onAuthorTap: () => _openAuthor(c.author.id),
                onReply: _viewerId == null
                    ? null
                    : () => setState(() {
                        _replyTo = c.comment.id;
                        _replyCtrl.clear();
                      }),
                onDelete: () => _deleteComment(c.comment.id),
                onReport: _canReport(c.comment)
                    ? () => _reportComment(c.comment.id)
                    : null,
              ),
              for (final r in (repliesByParent[c.comment.id] ?? const []))
                Padding(
                  padding: const EdgeInsets.only(left: 36),
                  child: _CommentTile(
                    entry: r,
                    like: _likes[r.comment.id] ?? (count: 0, viewerLiked: false),
                    canLike: _viewerId != null &&
                        r.comment.authorId != _viewerId &&
                        _likeBusy == null,
                    onLike: () => _toggleLike(r.comment),
                    mentionIds: _mentionIds,
                    onMentionTap: _openAuthor,
                    canDelete: _canDelete(r.comment),
                    onAuthorTap: () => _openAuthor(r.author.id),
                    onReply: null,
                    onDelete: () => _deleteComment(r.comment.id),
                    onReport: _canReport(r.comment)
                        ? () => _reportComment(r.comment.id)
                        : null,
                    isReply: true,
                  ),
                ),
              if (_replyTo == c.comment.id)
                Padding(
                  padding: const EdgeInsets.fromLTRB(36, 4, 0, 8),
                  child: _Composer(
                    controller: _replyCtrl,
                    hint: l10n.runSocialReplyHint,
                    posting: _posting,
                    onPost: () => _postComment(parentId: c.comment.id),
                    onCancel: () => setState(() => _replyTo = null),
                    onChanged: () => _onComposerChanged(_replyCtrl),
                    picker: _mentionPickerFor(_replyCtrl),
                  ),
                ),
            ],

          if (_viewerId != null) ...[
            const SizedBox(height: 12),
            _Composer(
              controller: _draftCtrl,
              hint: l10n.runSocialCommentHint,
              posting: _posting,
              onPost: () => _postComment(),
              onChanged: () => _onComposerChanged(_draftCtrl),
              picker: _mentionPickerFor(_draftCtrl),
            ),
          ],
        ],
      ),
    );
  }
}

class _KudosPill extends StatelessWidget {
  final int count;
  final bool viewerHas;
  final bool disabled;
  final VoidCallback onTap;

  const _KudosPill({
    required this.count,
    required this.viewerHas,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = viewerHas
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      label: viewerHas
          ? AppLocalizations.of(context).kudosRemoveLabel
          : AppLocalizations.of(context).kudosGiveLabel,
      child: TextButton.icon(
        onPressed: disabled ? null : onTap,
        icon: Icon(
          viewerHas ? Icons.favorite : Icons.favorite_border,
          size: 18,
          color: accent,
        ),
        label: Text(
          '$count',
          style: theme.textTheme.bodyMedium?.copyWith(color: accent),
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final RunCommentWithAuthor entry;
  final ({int count, bool viewerLiked}) like;
  final bool canLike;
  final VoidCallback onLike;
  final Map<String, String> mentionIds;
  final void Function(String userId) onMentionTap;
  final bool canDelete;
  final VoidCallback onAuthorTap;
  final VoidCallback? onReply;
  final VoidCallback onDelete;
  final VoidCallback? onReport;
  final bool isReply;

  const _CommentTile({
    required this.entry,
    required this.like,
    required this.canLike,
    required this.onLike,
    required this.mentionIds,
    required this.onMentionTap,
    required this.canDelete,
    required this.onAuthorTap,
    required this.onReply,
    required this.onDelete,
    this.onReport,
    this.isReply = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: isReply ? 6 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onAuthorTap,
            child: IdentityAvatar(
              seed: entry.author.id,
              name: entry.author.displayName,
              size: 32,
              imageUrl: entry.author.avatarUrl,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: onAuthorTap,
                        child: Semantics(
                          button: true,
                          child: Text(
                            entry.author.displayName ??
                                l10n.runSocialRunnerFallback,
                            style: theme.textTheme.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    Text(
                      fmtRelative(
                        entry.comment.createdAt,
                        localeToTag(Localizations.localeOf(context)),
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                _MentionText(
                  body: entry.comment.body,
                  mentionIds: mentionIds,
                  onTap: onMentionTap,
                ),
                OverflowBar(
                  children: [
                    Semantics(
                      button: true,
                      toggled: like.viewerLiked,
                      label: like.viewerLiked
                          ? l10n.runSocialUnlikeComment
                          : l10n.runSocialLikeComment,
                      child: TextButton.icon(
                        key: ValueKey('comment-like-${entry.comment.id}'),
                        onPressed: canLike ? onLike : null,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(48, 48),
                        ),
                        icon: Icon(
                          like.viewerLiked ? Icons.favorite : Icons.favorite_border,
                          size: 18,
                          color: like.viewerLiked
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        label: Text(like.count > 0 ? '${like.count}' : ''),
                      ),
                    ),
                    if (onReply != null)
                      TextButton(
                        onPressed: onReply,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(48, 48),
                        ),
                        child: Text(l10n.runSocialReply),
                      ),
                    if (onReport != null)
                      IconButton(
                        onPressed: onReport,
                        icon: const Icon(Icons.flag_outlined, size: 18),
                        tooltip: isReply
                            ? l10n.runSocialReportReply
                            : l10n.runSocialReportComment,
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    if (canDelete)
                      TextButton(
                        onPressed: onDelete,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(48, 48),
                          foregroundColor: theme.colorScheme.error,
                        ),
                        child: Text(l10n.runSocialDelete),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool posting;
  final VoidCallback onPost;
  final VoidCallback? onCancel;
  final VoidCallback? onChanged;
  final Widget? picker;

  const _Composer({
    required this.controller,
    required this.hint,
    required this.posting,
    required this.onPost,
    this.onCancel,
    this.onChanged,
    this.picker,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller,
                maxLines: null,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                onChanged: onChanged == null ? null : (_) => onChanged!(),
                decoration: InputDecoration(
                  hintText: hint,
                  isDense: true,
                ),
              ),
              ?picker,
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          children: [
            FilledButton(
              onPressed: posting ? null : onPost,
              child: posting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.runSocialPost),
            ),
            if (onCancel != null)
              TextButton(
                onPressed: onCancel,
                child: Text(l10n.runSocialCancel),
              ),
          ],
        ),
      ],
    );
  }
}


class _ReactionChip extends StatelessWidget {
  final ReactionTally tally;
  final String label;
  final bool disabled;
  final VoidCallback onTap;

  const _ReactionChip({
    required this.tally,
    required this.label,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final on = tally.viewerReacted;
    final accent = on ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      toggled: on,
      label: on ? l10n.runSocialRemoveReaction(label) : l10n.runSocialReactWith(label),
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: OutlinedButton(
          key: ValueKey('reaction-${tally.key}'),
          onPressed: disabled ? null : onTap,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            shape: const StadiumBorder(),
            backgroundColor: on ? theme.colorScheme.primary.withValues(alpha: 0.12) : null,
            side: BorderSide(color: on ? theme.colorScheme.primary : theme.colorScheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(reactionIcons[tally.key], size: 18, color: accent),
              if (tally.count > 0) ...[
                const SizedBox(width: 4),
                Text(
                  '${tally.count}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: on ? FontWeight.w700 : null,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A comment body with every mention of a real runner drawn as a tappable
/// link to their profile; an unknown handle stays plain text.
class _MentionText extends StatelessWidget {
  final String body;
  final Map<String, String> mentionIds;
  final void Function(String userId) onTap;

  const _MentionText({
    required this.body,
    required this.mentionIds,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyMedium;
    final segments = splitMentions(body);
    if (!segments.any((s) => s.isMention && mentionIds.containsKey(s.handle))) {
      return Text(body, style: base);
    }
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          for (final seg in segments)
            if (seg.isMention && mentionIds.containsKey(seg.handle))
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: Semantics(
                  link: true,
                  child: GestureDetector(
                    key: ValueKey('mention-${seg.handle}'),
                    onTap: () => onTap(mentionIds[seg.handle]!),
                    child: Text(
                      seg.text,
                      style: base?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              )
            else
              TextSpan(text: seg.text),
        ],
      ),
    );
  }
}

class _MentionPicker extends StatelessWidget {
  final List<PeopleSuggestion> people;
  final void Function(PeopleSuggestion) onPick;

  const _MentionPicker({required this.people, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: AppLocalizations.of(context).runSocialMentionSuggestions,
      child: Card(
        margin: const EdgeInsets.only(top: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in people)
              ListTile(
                key: ValueKey('mention-pick-${p.handle}'),
                dense: true,
                minTileHeight: 48,
                leading: IdentityAvatar(
                  seed: p.id,
                  name: p.displayName,
                  size: 28,
                  imageUrl: p.avatarUrl,
                ),
                title: Text(
                  p.displayName ?? AppLocalizations.of(context).runSocialRunnerFallback,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '@${p.handle}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () => onPick(p),
              ),
          ],
        ),
      ),
    );
  }
}

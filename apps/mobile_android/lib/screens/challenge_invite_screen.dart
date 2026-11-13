import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../auth_error.dart';
import '../l10n/gen/app_localizations.dart';
import '../rate_limit_message.dart';
import '../runner_handle.dart';
import '../social_service.dart';
import '../widgets/challenge_progress_bar.dart' show challengeValueLabel;
import '../widgets/error_state.dart';
import '../widgets/sign_in_required_state.dart';
import 'challenge_detail_screen.dart';

/// A challenge invite link opened in the app (decisions § 2261). Mirrors the
/// web `/challenges/join/[token]` page: the challenge the link names, and one
/// tap to join. Signed out, the tap goes through sign-in or sign-up and then
/// joins, so the link survives creating an account.
class ChallengeInviteScreen extends StatefulWidget {
  final SocialService social;
  final String token;

  const ChallengeInviteScreen({
    super.key,
    required this.social,
    required this.token,
  });

  @override
  State<ChallengeInviteScreen> createState() => _ChallengeInviteScreenState();
}

class _ChallengeInviteScreenState extends State<ChallengeInviteScreen> {
  ChallengeInvitePreview? _preview;
  bool _loaded = false;
  bool _loadFailed = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loaded = false;
      _loadFailed = false;
    });
    try {
      final p = await widget.social.previewChallengeInvite(widget.token);
      if (!mounted) return;
      setState(() {
        _preview = p;
        _loaded = true;
      });
    } catch (e) {
      debugPrint('ChallengeInviteScreen._load failed: $e');
      if (!mounted) return;
      setState(() {
        _loadFailed = true;
        _loaded = true;
      });
    }
  }

  void _openChallenge(String id) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) =>
            ChallengeDetailScreen(social: widget.social, challengeId: id),
      ),
    );
  }

  Future<void> _join() async {
    if (_busy) return;
    if (!await ensureSignedIn(
      context,
      viewerId: widget.social.currentUserId,
      onSignedIn: _join,
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final l10n = AppLocalizations.of(context);
    try {
      final id = await widget.social.joinChallengeByToken(widget.token);
      if (!mounted) return;
      if (id == null) {
        setState(() => _preview = null);
        return;
      }
      _openChallenge(id);
    } catch (e) {
      debugPrint('ChallengeInviteScreen._join failed: $e');
      if (!mounted) return;
      final limited = e is PostgrestException
          ? rateLimitErrorMessage(l10n, code: e.code, message: e.message)
          : null;
      setState(() => _error = limited ?? friendlyError(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _windowLabel(AppLocalizations l10n, ChallengeInvitePreview p) {
    final now = DateTime.now();
    if (now.isBefore(p.startsAt)) {
      return l10n.challengeInviteStartsIn(p.startsAt.difference(now).inDays + 1);
    }
    if (now.isAfter(p.endsAt)) return l10n.challengesEnded;
    final days = p.endsAt.difference(now).inDays;
    return days <= 1 ? l10n.challengesEndsToday : l10n.challengesEndsIn(days);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = _preview;
    final Widget body;
    if (!_loaded) {
      body = Center(
        child: Semantics(
          excludeSemantics: true,
          label: l10n.commonLoading,
          child: const CircularProgressIndicator(),
        ),
      );
    } else if (_loadFailed) {
      body = AppErrorState(message: l10n.challengeInviteLoadFailed, onRetry: _load);
    } else if (p == null) {
      body = Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.challengeInviteMissingTitle,
                textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(l10n.challengeInviteMissingBody, textAlign: TextAlign.center),
          ],
        ),
      );
    } else {
      final creator = p.creatorName ??
          runnerHandle(
            p.creatorId,
            handle: (slug) => l10n.liveRunnerHandle(slug),
            anonymous: l10n.liveRunnerAnonymous,
          );
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.challengeInviteFrom(creator),
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(p.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text(_windowLabel(l10n, p))),
              if (p.goalValue != null)
                Chip(label: Text(challengeValueLabel(l10n, p.metric, p.goalValue!))),
              Chip(label: Text(l10n.challengeInviteParticipants(p.participantCount))),
            ],
          ),
          if ((p.description ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(p.description!),
          ],
          const SizedBox(height: 24),
          if (p.joined) ...[
            Text(l10n.challengeInviteAlreadyIn),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _openChallenge(p.id),
              child: Text(l10n.challengeInviteOpen),
            ),
          ] else ...[
            if (widget.social.currentUserId == null) ...[
              Text(l10n.challengeInviteSignInBody),
              const SizedBox(height: 12),
            ],
            FilledButton(
              key: const ValueKey('challenge-invite-join'),
              onPressed: _busy ? null : _join,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.challengeInviteJoin),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.challengeInviteTitle)),
      body: body,
    );
  }
}

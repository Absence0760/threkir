import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../l10n/gen/app_localizations.dart';
import '../widgets/error_state.dart';
import '../widgets/top_banner.dart';

/// Pending requests to follow the signed-in user's private profile, with
/// approve and decline (decisions § 1967). Mirrors web `/follow-requests`.
/// A decline is not confirmed: the requester can ask again, and nothing they
/// could see is taken away.
class FollowRequestsScreen extends StatefulWidget {
  final ApiClient api;

  const FollowRequestsScreen({super.key, required this.api});

  @override
  State<FollowRequestsScreen> createState() => _FollowRequestsScreenState();
}

class _FollowRequestsScreenState extends State<FollowRequestsScreen> {
  List<IncomingFollowRequest> _requests = const [];
  bool _loading = true;
  Object? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.api.fetchIncomingFollowRequests();
      if (!mounted) return;
      setState(() => _requests = rows);
    } catch (e) {
      debugPrint('follow requests load failed: $e');
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _act(IncomingFollowRequest r, {required bool approve}) async {
    final id = r.requester.id;
    if (_busy.contains(id)) return;
    final l10n = AppLocalizations.of(context);
    final name = r.requester.displayName ?? l10n.profileNotifSomeone;
    setState(() => _busy.add(id));
    try {
      if (approve) {
        await widget.api.approveFollowRequest(id);
      } else {
        await widget.api.declineFollowRequest(id);
      }
      if (!mounted) return;
      setState(() => _requests =
          _requests.where((x) => x.requester.id != id).toList());
      showTopBanner(
        context,
        approve
            ? l10n.followRequestsApproved(name)
            : l10n.followRequestsDeclinedBanner,
      );
    } catch (e) {
      debugPrint('follow request action failed: $e');
      if (!mounted) return;
      showTopBanner(context, l10n.followRequestsActionFailed);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.followRequestsTitle)),
      body: _body(l10n),
    );
  }

  Widget _body(AppLocalizations l10n) {
    if (_loading) return ListSkeleton(label: l10n.commonLoading);
    if (_error != null) {
      return ErrorState(message: l10n.followRequestsLoadError, onRetry: _load);
    }
    if (_requests.isEmpty) {
      return EmptyState(
        key: const ValueKey('follow-requests-empty'),
        icon: Icons.person_add_alt_1_outlined,
        title: l10n.followRequestsEmptyTitle,
        body: l10n.followRequestsEmptyBody,
      );
    }
    return ListView.separated(
      key: const ValueKey('follow-requests-list'),
      itemCount: _requests.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = _requests[i];
        final p = r.requester;
        final busy = _busy.contains(p.id);
        return ListTile(
          leading: IdentityAvatar(
            seed: p.id,
            name: p.displayName,
            imageUrl: p.avatarUrl,
          ),
          title: Text(
            p.displayName ?? l10n.profileNotifSomeone,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Wrap(
            spacing: 8,
            children: [
              FilledButton(
                key: ValueKey('follow-request-approve-${p.id}'),
                onPressed: busy ? null : () => _act(r, approve: true),
                child: Text(l10n.followRequestsApprove),
              ),
              OutlinedButton(
                key: ValueKey('follow-request-decline-${p.id}'),
                onPressed: busy ? null : () => _act(r, approve: false),
                child: Text(l10n.followRequestsDecline),
              ),
            ],
          ),
        );
      },
    );
  }
}

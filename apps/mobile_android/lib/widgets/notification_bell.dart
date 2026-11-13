import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../screens/profile_screen.dart';

/// Notification bell icon for the dashboard action toolbar. Mirrors
/// `apps/web/src/lib/components/NotificationBell.svelte`. Tapping
/// navigates to the user's own ProfileScreen with the Notifications
/// tab pre-selected. Unread notifications show as a Material `Badge`
/// carrying the count (9+ past nine, as web's badge does), and the
/// tooltip, which is also the button's accessible name, says how many:
/// a colour-only dot told neither a screen reader nor a colour-blind
/// reader anything (#1374 A11Y-5).
///
/// The unread count is fetched on mount via
/// `ApiClient.fetchUnreadNotificationCount`. Failures are swallowed
/// (L4 — auxiliary effect, must not break the dashboard render
/// per docs/architecture/conventions.md). When [api] has no signed-in user, the
/// bell renders empty — the dashboard's `if (api != null)` gate is
/// the canonical signed-in check, but the widget is defensive.
class NotificationBell extends StatefulWidget {
  final ApiClient api;

  const NotificationBell({super.key, required this.api});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final count = await widget.api.fetchUnreadNotificationCount();
      if (!mounted) return;
      setState(() => _unread = count);
    } catch (_) {
      // L4 — auxiliary effect. A failed unread fetch must not break
      // the dashboard. Leave the badge dark.
    }
  }

  void _open() {
    final uid = widget.api.userId;
    if (uid == null) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => ProfileScreen(
              api: widget.api,
              userId: uid,
              initialTab: ProfileTab.notifications,
            ),
          ),
        )
        .then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final unread = _unread > 0;
    return IconButton(
      tooltip: unread
          ? l10n.notificationBellUnread(_unread)
          : l10n.notificationBellTooltip,
      icon: Badge.count(
        count: _unread,
        maxCount: 9,
        isLabelVisible: unread,
        child: Icon(
          unread ? Icons.notifications_active : Icons.notifications_outlined,
        ),
      ),
      onPressed: _open,
    );
  }
}

import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../backend_timeout.dart';
import '../screens/event_detail_screen.dart';
import '../social_service.dart';

/// How far ahead Home's Today block looks for the runner's next club event
/// (decisions § 2285). The Run tab keeps `fetchNextRsvpedEvent`'s own 48 h
/// default, where the card stands in for the last run just before the event.
const kHomeEventWindow = Duration(days: 7);

/// Opens [event]'s detail screen. An event row carries its club's id, not the
/// slug the detail route needs, so the slug comes from the runner's clubs; a
/// club that cannot be resolved (the read failed, or the runner left it)
/// leaves the tap doing nothing rather than opening a broken screen.
Future<void> openUpcomingEvent(
    BuildContext context, SocialService social, EventView event) async {
  List<ClubView> clubs = const [];
  try {
    clubs = await social.fetchMyClubs().timeout(kBackendLoadTimeout);
  } catch (e) {
    debugPrint('fetchMyClubs failed: $e');
  }
  final match = clubs.where((c) => c.row.id == event.row.clubId).toList();
  if (!context.mounted) return;
  final slug = match.isEmpty ? null : match.first.row.slug;
  if (slug == null) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => EventDetailScreen(
        social: social,
        clubSlug: slug,
        eventId: event.row.id,
      ),
    ),
  );
}

/// Small tappable card for the runner's next `going` club event: on the Run
/// tab's idle state within 48 hours, where it replaces the last-run card so
/// the imminent commitment gets priority, and in Home's Today block within
/// [kHomeEventWindow].
class UpcomingEventCard extends StatelessWidget {
  final EventView event;
  final VoidCallback? onTap;
  const UpcomingEventCard({super.key, required this.event, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final when = event.nextInstanceStart;
    final relative = _relativeFromNow(l10n, when);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primaryContainer,
              theme.colorScheme.surfaceContainerHighest,
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary,
              ),
              child: Icon(Icons.event,
                  color: theme.colorScheme.onPrimary, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.upcomingEventBadge(relative),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      letterSpacing: 0.7,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    event.row.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 14,
                          color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          fmtEventDate(when, localeToTag(Localizations.localeOf(context))),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      if (event.row.meetLabel != null) ...[
                        const SizedBox(width: 10),
                        Icon(Icons.place, size: 14,
                            color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            event.row.meetLabel!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _relativeFromNow(AppLocalizations l10n, DateTime when) {
    final diff = when.difference(DateTime.now());
    if (diff.inMinutes < 60) {
      return diff.inMinutes <= 1
          ? l10n.upcomingEventStartingNow
          : l10n.upcomingEventInMinutes(diff.inMinutes);
    }
    if (diff.inHours < 24) {
      return diff.inHours == 1
          ? l10n.upcomingEventInOneHour
          : l10n.upcomingEventInHours(diff.inHours);
    }
    if (diff.inHours < 48) return l10n.upcomingEventTomorrow;
    return l10n.upcomingEventInDays(diff.inDays);
  }
}

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../badges.dart';
import '../preferences.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';

/// Tier ring colours, matching the web `BadgeGrid.svelte` `.tier-*` palette.
Color badgeTierColor(String tier) {
  switch (tier) {
    case 'bronze':
      return const Color(0xFFB08D57);
    case 'silver':
      return const Color(0xFF9AA3AD);
    case 'gold':
      return const Color(0xFFD4AF37);
    case 'platinum':
      return const Color(0xFF7FD3E0);
    default:
      return const Color(0xFF9AA3AD);
  }
}

String badgeTierLabel(AppLocalizations l10n, String tier) {
  switch (tier) {
    case 'bronze':
      return l10n.badgesTierBronze;
    case 'silver':
      return l10n.badgesTierSilver;
    case 'gold':
      return l10n.badgesTierGold;
    case 'platinum':
      return l10n.badgesTierPlatinum;
    default:
      return tier;
  }
}

/// Map a catalogue Material-Symbols ligature name to a Flutter [IconData].
IconData badgeIconData(String name) {
  switch (name) {
    case 'directions_run':
      return Icons.directions_run;
    case 'military_tech':
      return Icons.military_tech;
    case 'workspace_premium':
      return Icons.workspace_premium_outlined;
    case 'route':
      return Icons.route;
    case 'public':
      return Icons.public;
    case 'local_fire_department':
      return Icons.local_fire_department;
    case 'whatshot':
      return Icons.whatshot;
    case 'timer':
      return Icons.timer;
    case 'trophy':
    case 'emoji_events':
      return Icons.emoji_events;
    case 'flag':
      return Icons.flag_outlined;
    case 'park':
      return Icons.park_outlined;
    case 'hiking':
      return Icons.hiking;
    case 'forest':
      return Icons.forest;
    case 'explore':
      return Icons.explore;
    case 'flag_circle':
      return Icons.flag_circle;
    case 'map':
      return Icons.map_outlined;
    default:
      return Icons.military_tech;
  }
}

/// Resolve a catalogue label/desc ARB key to its localized string. The keys
/// are the camelCase ids carried by [BadgeTier.labelKey] / [BadgeTier.descKey]
/// — gen-l10n exposes getters, not a map, so the resolution is a switch. A
/// distance family's words take [distance], its threshold already in the
/// reader's unit; the other keys ignore it. Callers go through [badgeWords].
String badgeText(AppLocalizations l10n, String key, String distance) {
  switch (key) {
    case 'badgesDistanceSingle5kLabel':
      return l10n.badgesDistanceSingle5kLabel;
    case 'badgesDistanceSingle5kDesc':
      return l10n.badgesDistanceSingle5kDesc(distance);
    case 'badgesDistanceSingleHalfLabel':
      return l10n.badgesDistanceSingleHalfLabel;
    case 'badgesDistanceSingleHalfDesc':
      return l10n.badgesDistanceSingleHalfDesc(distance);
    case 'badgesDistanceSingleMarathonLabel':
      return l10n.badgesDistanceSingleMarathonLabel;
    case 'badgesDistanceSingleMarathonDesc':
      return l10n.badgesDistanceSingleMarathonDesc(distance);
    case 'badgesDistanceSingleUltraLabel':
      return l10n.badgesDistanceSingleUltraLabel;
    case 'badgesDistanceSingleUltraDesc':
      return l10n.badgesDistanceSingleUltraDesc(distance);
    case 'badgesDistanceLifetime100Label':
      return l10n.badgesDistanceLifetime100Label(distance);
    case 'badgesDistanceLifetime100Desc':
      return l10n.badgesDistanceLifetime100Desc(distance);
    case 'badgesDistanceLifetime500Label':
      return l10n.badgesDistanceLifetime500Label(distance);
    case 'badgesDistanceLifetime500Desc':
      return l10n.badgesDistanceLifetime500Desc(distance);
    case 'badgesDistanceLifetime1000Label':
      return l10n.badgesDistanceLifetime1000Label(distance);
    case 'badgesDistanceLifetime1000Desc':
      return l10n.badgesDistanceLifetime1000Desc(distance);
    case 'badgesDistanceLifetime5000Label':
      return l10n.badgesDistanceLifetime5000Label(distance);
    case 'badgesDistanceLifetime5000Desc':
      return l10n.badgesDistanceLifetime5000Desc(distance);
    case 'badgesStreak7Label':
      return l10n.badgesStreak7Label;
    case 'badgesStreak7Desc':
      return l10n.badgesStreak7Desc;
    case 'badgesStreak30Label':
      return l10n.badgesStreak30Label;
    case 'badgesStreak30Desc':
      return l10n.badgesStreak30Desc;
    case 'badgesStreak100Label':
      return l10n.badgesStreak100Label;
    case 'badgesStreak100Desc':
      return l10n.badgesStreak100Desc;
    case 'badgesStreak365Label':
      return l10n.badgesStreak365Label;
    case 'badgesStreak365Desc':
      return l10n.badgesStreak365Desc;
    case 'badgesPr1Label':
      return l10n.badgesPr1Label;
    case 'badgesPr1Desc':
      return l10n.badgesPr1Desc;
    case 'badgesPr3Label':
      return l10n.badgesPr3Label;
    case 'badgesPr3Desc':
      return l10n.badgesPr3Desc;
    case 'badgesPr5Label':
      return l10n.badgesPr5Label;
    case 'badgesPr5Desc':
      return l10n.badgesPr5Desc;
    case 'badgesPlan1Label':
      return l10n.badgesPlan1Label;
    case 'badgesPlan1Desc':
      return l10n.badgesPlan1Desc;
    case 'badgesPlan3Label':
      return l10n.badgesPlan3Label;
    case 'badgesPlan3Desc':
      return l10n.badgesPlan3Desc;
    case 'badgesPlan10Label':
      return l10n.badgesPlan10Label;
    case 'badgesPlan10Desc':
      return l10n.badgesPlan10Desc;
    case 'badgesParkCourses1Label':
      return l10n.badgesParkCourses1Label;
    case 'badgesParkCourses1Desc':
      return l10n.badgesParkCourses1Desc;
    case 'badgesParkCourses5Label':
      return l10n.badgesParkCourses5Label;
    case 'badgesParkCourses5Desc':
      return l10n.badgesParkCourses5Desc;
    case 'badgesParkCourses10Label':
      return l10n.badgesParkCourses10Label;
    case 'badgesParkCourses10Desc':
      return l10n.badgesParkCourses10Desc;
    case 'badgesParkCourses25Label':
      return l10n.badgesParkCourses25Label;
    case 'badgesParkCourses25Desc':
      return l10n.badgesParkCourses25Desc;
    case 'badgesParkComplete1Label':
      return l10n.badgesParkComplete1Label;
    case 'badgesParkComplete1Desc':
      return l10n.badgesParkComplete1Desc;
    case 'badgesParkComplete3Label':
      return l10n.badgesParkComplete3Label;
    case 'badgesParkComplete3Desc':
      return l10n.badgesParkComplete3Desc;
    case 'badgesParkComplete10Label':
      return l10n.badgesParkComplete10Label;
    case 'badgesParkComplete10Desc':
      return l10n.badgesParkComplete10Desc;
    case 'badgesParkPassport1Label':
      return l10n.badgesParkPassport1Label;
    case 'badgesParkPassport1Desc':
      return l10n.badgesParkPassport1Desc;
    case 'badgesParkPassport3Label':
      return l10n.badgesParkPassport3Label;
    case 'badgesParkPassport3Desc':
      return l10n.badgesParkPassport3Desc;
    case 'badgesParkPassport10Label':
      return l10n.badgesParkPassport10Label;
    case 'badgesParkPassport10Desc':
      return l10n.badgesParkPassport10Desc;
    default:
      return key;
  }
}

/// An award's label and description in the reader's words and unit, or null
/// for a badge or tier this build does not know. A distance family's words
/// name its threshold, so a miles reader reads "Ran 26.2 mi in a single run".
/// [unit] and [localeTag] default to the active preference and locale. Twin
/// of web's `badgeWords` in apps/web/src/lib/social/badges.ts.
({String label, String desc, String icon})? badgeWords(
  AppLocalizations l10n,
  String badgeKey,
  String tier, {
  DistanceUnit? unit,
  String? localeTag,
}) {
  for (final b in kBadgeCatalogue) {
    if (b.id != badgeKey) continue;
    for (final t in b.tiers) {
      if (t.tier != tier) continue;
      final digits = b.distanceDigits;
      final distance = digits == null
          ? ''
          : UnitFormat.thresholdDistance(
              t.threshold, unit ?? activeDistanceUnit, digits, localeTag);
      return (
        label: badgeText(l10n, t.labelKey, distance),
        desc: badgeText(l10n, t.descKey, distance),
        icon: t.icon,
      );
    }
    return null;
  }
  return null;
}

/// Localized label for a stored award (its catalogue label, else the raw
/// badge_key). Shared by the feed badge strip and the run share card.
String badgeLabelFor(AppLocalizations l10n, String badgeKey, String tier,
        {DistanceUnit? unit}) =>
    badgeWords(l10n, badgeKey, tier, unit: unit)?.label ?? badgeKey;

/// A tier-coloured grid of earned badges. Mirrors the web `BadgeGrid.svelte`:
/// the owner sees their private badges flagged, and tapping one of their own
/// opens [onOpen] (the badge share sheet, with the visibility toggle).
class BadgeGrid extends StatelessWidget {
  final List<AchievementRow> badges;
  final bool isOwner;
  final ValueChanged<AchievementRow>? onOpen;

  const BadgeGrid({
    super.key,
    required this.badges,
    this.isOwner = false,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (badges.isEmpty) {
      return EmptyState(
        icon: Icons.emoji_events,
        title: isOwner ? l10n.badgesEmpty : l10n.badgesEmptyOther,
      );
    }
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisExtent: 210,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: badges.length,
      itemBuilder: (context, i) => _BadgeTile(
        badge: badges[i],
        showPrivate: isOwner,
        onTap: isOwner && onOpen != null ? () => onOpen!(badges[i]) : null,
      ),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  final AchievementRow badge;
  final bool showPrivate;
  final VoidCallback? onTap;

  const _BadgeTile({required this.badge, this.showPrivate = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tierColor = badgeTierColor(badge.tier);
    final words = badgeWords(l10n, badge.badgeKey, badge.tier);
    final label = words?.label ?? badge.badgeKey;
    final desc = words?.desc;
    final icon = badgeIconData(words?.icon ?? 'military_tech');
    final earned = formatDateMed(badge.earnedAt, activeLocaleTag);
    return Opacity(
      opacity: badge.isPublic ? 1 : 0.72,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          // Ink, not a Container, so the tap's splash draws over the ground.
          child: Ink(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Stack(
              children: [
                Column(
                  children: [
                    Container(height: 3, color: tierColor),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(icon, size: 40, color: tierColor),
                            const SizedBox(height: 6),
                            Text(
                              label,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (desc != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                desc,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              badgeTierLabel(l10n, badge.tier).toUpperCase(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: tierColor,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              l10n.badgesEarnedOn(earned),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (showPrivate && !badge.isPublic)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Tooltip(
                      message: l10n.badgesPrivate,
                      child: Icon(
                        Icons.lock_outline,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                        semanticLabel: l10n.badgesPrivate,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

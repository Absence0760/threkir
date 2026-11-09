/// What leads Home, and which trend groups the runner has hidden from it
/// (#1187). Parity pair with `apps/web/src/lib/training/dashboard_layout.ts`;
/// the rules are the pair's point, the rendering is each platform's own.
library;

/// The state the adaptive Today hero renders. A plan outranks everything,
/// because a plan written for today is the most specific thing Home knows; a
/// brand-new account without a plan gets the first-run block; otherwise a run
/// logged today leads, and failing that readiness plus a prompt to start.
enum TodayHeroState { raceDay, planToday, restDay, newAccount, ranToday, noPlan }

TodayHeroState todayHeroState({
  required bool hasPlan,
  required bool raceToday,
  required String? todayWorkoutKind,
  required bool isNewAccount,
  required bool ranToday,
}) {
  if (hasPlan) {
    if (raceToday) return TodayHeroState.raceDay;
    if (todayWorkoutKind != null && todayWorkoutKind != 'rest') {
      return TodayHeroState.planToday;
    }
    return TodayHeroState.restDay;
  }
  if (isNewAccount) return TodayHeroState.newAccount;
  if (ranToday) return TodayHeroState.ranToday;
  return TodayHeroState.noPlan;
}

/// Universal settings key holding the trend groups hidden from Home.
const kDashboardHiddenCardsKey = 'dashboard_hidden_cards';

/// The trend groups a runner can hide, in Home's order. The ids are the
/// `dashboard_trends` disclosure keys, so one group has one name everywhere.
const hideableDashboardCards = <String>[
  'volume',
  'fitness',
  'performance',
  'effort',
  'recent',
];

bool isHideableDashboardCard(Object? v) =>
    v is String && hideableDashboardCards.contains(v);

/// The stored list as Home reads it: known ids only, each once, in Home's
/// order. Anything else (a non-list, an id a newer client wrote, a number) is
/// dropped rather than thrown on, so a bad bag never takes a card away that
/// the runner did not hide.
List<String> parseHiddenCards(Object? raw) {
  if (raw is! List) return const [];
  final present = raw.where(isHideableDashboardCard).toSet();
  return [
    for (final id in hideableDashboardCards)
      if (present.contains(id)) id,
  ];
}

/// [list] with [id] hidden or shown, normalised the way [parseHiddenCards]
/// reads it.
List<String> withCardHidden(List<String> list, String id, bool hidden) {
  final next = parseHiddenCards(list).toSet();
  if (hidden && isHideableDashboardCard(id)) {
    next.add(id);
  } else {
    next.remove(id);
  }
  return [
    for (final c in hideableDashboardCards)
      if (next.contains(c)) c,
  ];
}

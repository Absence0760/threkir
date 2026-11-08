import 'package:flutter_test/flutter_test.dart';
import '../lib/dashboard_layout.dart';

// Dart twin of apps/web/src/lib/training/dashboard_layout.test.ts — one case
// per web case, same inputs, same expectations.

TodayHeroState _state({
  bool hasPlan = false,
  bool raceToday = false,
  String? todayWorkoutKind,
  bool isNewAccount = false,
  bool ranToday = false,
}) =>
    todayHeroState(
      hasPlan: hasPlan,
      raceToday: raceToday,
      todayWorkoutKind: todayWorkoutKind,
      isNewAccount: isNewAccount,
      ranToday: ranToday,
    );

void main() {
  test('a plan workout today leads', () {
    expect(_state(hasPlan: true, todayWorkoutKind: 'easy'),
        TodayHeroState.planToday);
  });

  test("race day outranks the day's workout", () {
    expect(_state(hasPlan: true, raceToday: true, todayWorkoutKind: 'race'),
        TodayHeroState.raceDay);
  });

  test('a plan with nothing or a rest workout today is a rest day', () {
    expect(_state(hasPlan: true), TodayHeroState.restDay);
    expect(_state(hasPlan: true, todayWorkoutKind: 'rest'),
        TodayHeroState.restDay);
  });

  test('a plan rest day stays a rest day even after a run', () {
    expect(_state(hasPlan: true, ranToday: true), TodayHeroState.restDay);
  });

  test('a new account without a plan gets the first-run state', () {
    expect(_state(isNewAccount: true), TodayHeroState.newAccount);
  });

  test('a new account with a plan is led by the plan', () {
    expect(
        _state(isNewAccount: true, hasPlan: true, todayWorkoutKind: 'easy'),
        TodayHeroState.planToday);
  });

  test('without a plan, a run today leads', () {
    expect(_state(ranToday: true), TodayHeroState.ranToday);
  });

  test('without a plan or a run today, readiness and a start prompt lead', () {
    expect(_state(), TodayHeroState.noPlan);
  });

  test('the settings key and the hideable ids', () {
    expect(kDashboardHiddenCardsKey, 'dashboard_hidden_cards');
    expect(hideableDashboardCards,
        ['volume', 'fitness', 'performance', 'effort', 'recent']);
  });

  test('parse keeps known ids once, in Home order', () {
    expect(parseHiddenCards(['recent', 'volume', 'recent']),
        ['volume', 'recent']);
  });

  test('parse drops unknown ids and non-strings', () {
    expect(parseHiddenCards(['streak', 3, null, 'effort']), ['effort']);
  });

  test('parse reads anything that is not a list as nothing hidden', () {
    expect(parseHiddenCards(null), isEmpty);
    expect(parseHiddenCards('volume'), isEmpty);
    expect(parseHiddenCards({'volume': true}), isEmpty);
  });

  test('hiding adds an id in Home order and is idempotent', () {
    expect(withCardHidden(['recent'], 'volume', true), ['volume', 'recent']);
    expect(withCardHidden(['volume'], 'volume', true), ['volume']);
  });

  test('showing removes an id and tolerates one that was not hidden', () {
    expect(withCardHidden(['volume', 'recent'], 'volume', false), ['recent']);
    expect(withCardHidden(['recent'], 'effort', false), ['recent']);
  });

  test('a toggle drops ids the parse would drop', () {
    expect(withCardHidden(['streak', 'fitness'], 'effort', true),
        ['fitness', 'effort']);
  });
}

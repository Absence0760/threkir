import 'package:flutter_test/flutter_test.dart';

import '../lib/fuel_plan.dart';

// start -> aid (1h, refill) -> cutoff (0.5h, no services) -> finish (0.5h).
List<FuelLegInput> legs() => const [
      FuelLegInput(projectedElapsedS: 0, legDistM: 0, services: []),
      FuelLegInput(projectedElapsedS: 3600, legDistM: 8000, services: ['water', 'food']),
      FuelLegInput(projectedElapsedS: 5400, legDistM: 4000, services: []),
      FuelLegInput(projectedElapsedS: 7200, legDistM: 4000, services: []),
    ];

FuelPlan plan({double carbs = 60, double fluid = 500, double? heat, double? weightKg}) =>
    buildFuelPlan(legs(),
        carbsPerHourG: carbs, fluidPerHourMl: fluid, heatFactor: heat, weightKg: weightKg);

void main() {
  test('carbs + fluid scale with each leg duration', () {
    final p = plan();
    expect(p.legs[1].carbsG, 60);
    expect(p.legs[1].fluidMl, 500);
    expect(p.legs[2].carbsG, 30);
    expect(p.legs[2].fluidMl, 250);
    expect(p.legs[3].carbsG, 30);
  });

  test('zero-duration leg (start) gets zero carbs + fluid', () {
    final p = plan();
    expect(p.legs[0].carbsG, 0);
    expect(p.legs[0].fluidMl, 0);
  });

  test('heat factor bumps fluid but not carbs', () {
    final base = plan();
    final hot = plan(heat: heatFluidFactor);
    expect(hot.legs[1].carbsG, base.legs[1].carbsG);
    expect(hot.legs[1].fluidMl, base.legs[1].fluidMl * heatFluidFactor);
  });

  test('carryToNextAid sums legs up to and including the next refill', () {
    final p = plan();
    expect(p.legs[0].carryToNextAid!.carbsG, 60);
    expect(p.legs[0].carryToNextAid!.fluidMl, 500);
    expect(p.legs[0].carryToNextAid!.gels, 3);
    expect(p.legs[1].carryToNextAid!.carbsG, 60);
    expect(p.legs[1].carryToNextAid!.fluidMl, 500);
    expect(p.legs[1].carryToNextAid!.gels, 3);
  });

  test('carry is present only on the start + refill checkpoints', () {
    final p = plan();
    expect(p.legs[0].carryToNextAid, isNotNull);
    expect(p.legs[1].carryToNextAid, isNotNull);
    expect(p.legs[2].carryToNextAid, isNull);
    expect(p.legs[3].carryToNextAid, isNull);
  });

  test('gel count is ceil(carbs / gelCarbsG)', () {
    final p = plan(carbs: 70);
    expect(p.legs[0].carryToNextAid!.carbsG, 70);
    expect(p.legs[0].carryToNextAid!.gels, (70 / gelCarbsG).ceil());
  });

  test('totals equal the sum of the legs', () {
    final p = plan();
    final sumCarbs = p.legs.fold<double>(0, (a, l) => a + l.carbsG);
    final sumFluid = p.legs.fold<double>(0, (a, l) => a + l.fluidMl);
    expect(p.totalCarbsG, sumCarbs);
    expect(p.totalFluidMl, sumFluid);
    expect(p.totalCarbsG, 120);
    expect(p.totalFluidMl, 1000);
  });

  test('kcal is estimated only when a bodyweight is supplied', () {
    expect(plan().legs[1].kcal, 0);
    final withWeight = plan(weightKg: 70);
    expect((withWeight.legs[1].kcal - 580.16).abs() < 0.01, isTrue);
  });

  test('non-positive intake rates clamp to zero', () {
    final p = plan(carbs: -10, fluid: -5);
    expect(p.totalCarbsG, 0);
    expect(p.totalFluidMl, 0);
  });

  test('weight-based fluid is the default rate at the reference weight and scales with mass', () {
    expect(weightFluidPerHourMl(weightFluidReferenceKg), defaultFluidPerHourMl);
    // 500 × 90 / 70 = 642.9 → nearest 25 ml.
    expect(weightFluidPerHourMl(90), 650);
    // 500 × 63 / 70 = 450.
    expect(weightFluidPerHourMl(63), 450);
  });

  test('weight-based fluid is held to the 400-800 ml/h band', () {
    expect(weightFluidPerHourMl(50), weightFluidMinMl);
    expect(weightFluidPerHourMl(130), weightFluidMaxMl);
    expect(weightFluidPerHourMl(20), weightFluidMinMl);
    expect(weightFluidPerHourMl(250), weightFluidMaxMl);
  });

  test('no usable weight gives no weight-based rate, so the flat rate stands', () {
    for (final w in <double?>[null, 0, -70, 19.9, 250.1, double.nan, double.infinity]) {
      expect(weightFluidPerHourMl(w), isNull, reason: '$w');
    }
  });
}

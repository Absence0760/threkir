import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { maxSpeedMpsForActivity } from './strava.ts';

// fixtures/activity_speed_caps.json is ActivityType.maxSpeedMps
// (packages/core_models), the table every port's tests read.

const FIXTURE = JSON.parse(
  await Deno.readTextFile(
    new URL('../../../../../fixtures/activity_speed_caps.json', import.meta.url),
  ),
) as { unknownActivityCap: string; capsMps: Record<string, number> };

Deno.test('every activity speed cap matches fixtures/activity_speed_caps.json', () => {
  const entries = Object.entries(FIXTURE.capsMps);
  assert(entries.length > 0);
  for (const [type, cap] of entries) {
    assertEquals(maxSpeedMpsForActivity(type), cap, type);
  }
});

Deno.test('an unknown or missing activity takes the fixture fallback cap', () => {
  const fallback = FIXTURE.capsMps[FIXTURE.unknownActivityCap];
  assert(fallback !== undefined);
  for (const type of [null, undefined, '', 'skateboard']) {
    assertEquals(maxSpeedMpsForActivity(type), fallback, String(type));
  }
});

/// The alert → course matching of the park closures sweep, against a
/// recorded NPS Data API answer (fixtures/nps_alerts_2026-11-10.json: the
/// alerts endpoint for shen, blri, prwi and grfa on 2026-11-10, unedited) and
/// a few written alerts for the cases that answer lacks. No network.
///
/// Run with `cd apps/backend && deno test --allow-read
/// supabase/functions/park-closures-sweep/lib.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  alertsUrl,
  chunk,
  courseNames,
  flagsForPark,
  matchAlert,
  type NpsAlert,
  parseAlertsPage,
  PARKS_PER_REQUEST,
  type SweepCourse,
} from './lib.ts';

const RECORDED = JSON.parse(
  Deno.readTextFileSync(new URL('./fixtures/nps_alerts_2026-11-10.json', import.meta.url)),
);

function recorded(): NpsAlert[] {
  const page = parseAlertsPage(RECORDED);
  assert(page !== null);
  return page.alerts;
}

const alert = (over: Partial<NpsAlert>): NpsAlert => ({
  id: 'A-1',
  parkCode: 'shen',
  title: 'Notice',
  description: '',
  category: 'Caution',
  url: null,
  ...over,
});

const SHEN: SweepCourse[] = [
  { id: 'big-meadows', name: 'Big Meadows Loop' },
  { id: 'old-rag', name: 'Old Rag Loop' },
  { id: 'dark-hollow', name: 'Dark Hollow Falls Trail' },
];
const PRWI: SweepCourse[] = [
  { id: 'mary-byrd', name: 'Mary Byrd Branch Trail' },
  { id: 'scenic', name: 'Scenic Drive Loop' },
];
const GRFA: SweepCourse[] = [{ id: 'river', name: 'River Trail' }];

Deno.test('the recorded answer reads as one page of eleven alerts, numbers as strings and all', () => {
  const page = parseAlertsPage(RECORDED)!;
  assertEquals([page.total, page.start, page.count, page.alerts.length], [11, 0, 11, 11]);
  assertEquals([...new Set(page.alerts.map((a) => a.parkCode))].sort(), ['grfa', 'prwi', 'shen']);
  const fire = page.alerts.find((a) => a.title === 'Prescribed Fire in Big Meadows')!;
  assertEquals(fire.category, 'Caution');
  assertEquals(fire.url, null, 'an empty url is no url');
  const closure = page.alerts.find((a) => a.title === 'Active Closure')!;
  assertEquals(closure.url, 'https://www.nps.gov/shen/planyourvisit/naked-creek-backcountry-zone-closure.htm');
});

Deno.test('anything but the alerts envelope is refused, and a malformed alert is dropped', () => {
  assertEquals(parseAlertsPage(null), null);
  assertEquals(parseAlertsPage({ error: { code: 'API_KEY_INVALID', message: 'An invalid api_key was supplied.' } }), null);
  assertEquals(parseAlertsPage({ total: 'many', data: [] }), null);
  const page = parseAlertsPage({
    total: '3',
    start: '0',
    data: [{ id: 'X', parkCode: 'SHEN', title: ' Closed ', url: 'http://insecure' }, { parkCode: 'shen', title: 'no id' }, 7],
  })!;
  assertEquals(page.count, 3, 'paging counts every entry the page held');
  assertEquals(page.alerts, [{ id: 'X', parkCode: 'shen', title: 'Closed', description: '', category: '', url: null }]);
  assertEquals(
    parseAlertsPage({ total: '2', data: [{ id: 'NO-TITLE', parkCode: 'shen', title: ' ' }, { id: 'NO-PARK', title: 'T' }] })!.seen,
    [{ id: 'NO-TITLE', parkCode: 'shen' }, { id: 'NO-PARK', parkCode: null }],
    'an entry this side cannot use is still listed by NPS, so it is still seen',
  );
});

Deno.test('the recorded Shenandoah alerts flag each course a closure names, by its short name', () => {
  const shen = recorded().filter((a) => a.parkCode === 'shen');
  const flags = flagsForPark(shen, SHEN);
  assertEquals(
    flags.map((f) => [f.course_id, f.match, f.title]),
    [
      ['big-meadows', 'named', 'Prescribed Fire in Big Meadows'],
      // "A camping closure remains in effect ... from Lewis Mountain to Big Meadows".
      ['big-meadows', 'named', 'Active Closure'],
      ['old-rag', 'named', 'Infrastructure Improvements to Old Rag Trailhead'],
    ],
  );
  assert(flags.every((f) => f.course_id !== 'dark-hollow'), 'a course no alert names is left alone');
});

Deno.test('an Information alert with no closure in it flags nothing, even naming the course', () => {
  const ticket = recorded().find((a) => a.title === 'Ticket Required to Hike Old Rag')!;
  assertEquals(ticket.category, 'Information');
  assertEquals(matchAlert(ticket, SHEN), []);
});

Deno.test('a partial closure filed as Park Closure flags only the course it names', () => {
  const prwi = recorded().filter((a) => a.parkCode === 'prwi');
  assertEquals(flagsForPark(prwi, PRWI).map((f) => [f.course_id, f.match, f.category]), [
    ['mary-byrd', 'named', 'Park Closure'],
  ]);
  const grfa = recorded().filter((a) => a.parkCode === 'grfa');
  assertEquals(flagsForPark(grfa, GRFA), [], 'a closed climbing area is not a closed park');
});

Deno.test('a whole-park closure flags every course, the named ones as named', () => {
  const shutdown = alert({
    category: 'Park Closure',
    title: 'Park Closed',
    description: 'Due to a lapse in appropriations the park is closed. The Dark Hollow Falls Trail is also closed.',
  });
  assertEquals(matchAlert(shutdown, SHEN), [
    { courseId: 'big-meadows', match: 'park_wide' },
    { courseId: 'old-rag', match: 'park_wide' },
    { courseId: 'dark-hollow', match: 'named' },
  ]);
  const trails = alert({ category: 'Danger', title: 'Flooding', description: 'All trails are closed until further notice.' });
  assertEquals(matchAlert(trails, PRWI).map((m) => m.match), ['park_wide', 'park_wide']);
  const entrance = alert({
    category: 'Information',
    title: 'Temporary Closures of Park Entrance',
    description: 'There will be a temporary closure of the park entrance.',
  });
  assertEquals(matchAlert(entrance, PRWI), [], 'a closed entrance is not a closed park');
});

Deno.test('a course name is matched on word boundaries, accents and case aside', () => {
  assertEquals(courseNames('Big Meadows Loop'), ['big meadows loop', 'big meadows']);
  assertEquals(courseNames('Loop'), ['loop'], 'a bare generic word is never shortened to nothing');
  assertEquals(courseNames('Elk Trail'), ['elk trail'], 'a short leftover is too vague to stand alone');
  assertEquals(courseNames("Cañon Rim Route"), ['canon rim route', 'canon rim']);
  const near = alert({ title: 'Big Meadowsweet Lane closed' });
  assertEquals(matchAlert(near, SHEN), [], 'a longer word is not the name');
  const accented = alert({ title: 'CAÑON RIM CLOSED' });
  assertEquals(matchAlert(accented, [{ id: 'c', name: 'Canon Rim Route' }]), [{ courseId: 'c', match: 'named' }]);
});

Deno.test('a flag is clipped to the columns it lands in', () => {
  const long = alert({ title: 'T'.repeat(400), description: 'Big Meadows closed. ' + 'x'.repeat(3000), category: 'C'.repeat(80) });
  const [flag] = flagsForPark([long], SHEN);
  assertEquals([flag.title.length, flag.description.length, flag.category.length], [300, 2000, 60]);
});

Deno.test('requests carry the park codes and page, never the key', () => {
  const url = new URL(alertsUrl(['shen', 'blri'], 500));
  assertEquals(url.origin + url.pathname, 'https://developer.nps.gov/api/v1/alerts');
  assertEquals(url.searchParams.get('parkCode'), 'shen,blri');
  assertEquals(url.searchParams.get('start'), '500');
  assert(!url.search.includes('api_key'));
  assertEquals(chunk(Array.from({ length: 23 }, (_, i) => i), PARKS_PER_REQUEST).map((c) => c.length), [10, 10, 3]);
});

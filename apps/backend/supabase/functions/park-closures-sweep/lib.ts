/// The pure half of the park closures sweep (issue #1313 Phase 6): reading an
/// NPS Data API alerts page, and deciding which park courses an alert may
/// affect. Nothing here closes a course. An NPS alert is free text written for
/// visitors, so a match only puts the course in front of an operator, who
/// closes it from /admin/reports if the alert really shuts the trail.
///
/// The rule is deliberately narrow, because every flag costs a person a read:
///
///   * `named`: the alert's title or description names the course, by its
///     full name or by its name without a trailing "Trail" / "Loop" / "Course"
///     / "Path" / "Route" (an alert says "Big Meadows", the course is "Big
///     Meadows Loop"). An `Information` alert must also say something is
///     closed, rerouted or hazardous, so "Ticket Required to Hike Old Rag"
///     flags nothing.
///   * `park_wide`: the alert says the whole park, or every trail, is closed
///     ("The park is closed", "all trails are closed"); every course it does
///     not name. NPS files partial closures (a parking lot, a climbing area)
///     under the `Park Closure` category too, so the category alone is not
///     enough.

export const NPS_ALERTS_URL = 'https://developer.nps.gov/api/v1/alerts';

/// NPS documents a cap on `limit`; a park rarely has more than a dozen alerts,
/// so one page of this size holds every park in a chunk on any normal day.
export const NPS_PAGE_LIMIT = 500;

/// Park codes per request. The API takes a comma-separated list, so ten parks
/// cost one request against the key's hourly budget rather than ten.
export const PARKS_PER_REQUEST = 10;

/// The most pages one chunk may take before the sweep gives up on it.
export const MAX_PAGES = 5;

/// The pause between two requests, so a run never bursts the key's budget
/// (NPS allows 1,000 requests an hour per key).
export const REQUEST_GAP_MS = 1_000;

export const TITLE_MAX = 300;
export const DESCRIPTION_MAX = 2000;
export const URL_MAX = 500;

export type AlertMatch = 'named' | 'park_wide';

export interface NpsAlert {
  id: string;
  parkCode: string;
  title: string;
  description: string;
  category: string;
  url: string | null;
}

export interface SweepCourse {
  id: string;
  name: string;
}

/// A type alias, not an interface, so it is assignable to the `Json` the
/// record RPC's `p_flags` takes.
export type CourseFlag = {
  course_id: string;
  alert_id: string;
  category: string;
  title: string;
  description: string;
  url: string | null;
  match: AlertMatch;
};

export interface AlertsPage {
  alerts: NpsAlert[];
  /// How many entries the page held, malformed ones included, for paging.
  count: number;
  total: number;
  start: number;
}

/// The NPS envelope `{ total, limit, start, data: [...] }`, whose numbers come
/// back as strings. Null for anything else, including the api.data.gov error
/// body (`{ error: { code } }`) a bad or rate-limited key gets. An alert
/// missing its id, park code or title is dropped, not guessed at.
export function parseAlertsPage(payload: unknown): AlertsPage | null {
  if (!payload || typeof payload !== 'object') return null;
  const p = payload as Record<string, unknown>;
  if (!Array.isArray(p.data)) return null;
  const total = Number(p.total);
  const start = Number(p.start ?? 0);
  if (!Number.isFinite(total) || !Number.isFinite(start)) return null;
  const alerts: NpsAlert[] = [];
  for (const raw of p.data) {
    if (!raw || typeof raw !== 'object') continue;
    const a = raw as Record<string, unknown>;
    if (typeof a.id !== 'string' || a.id.length === 0 || a.id.length > 64) continue;
    if (typeof a.parkCode !== 'string' || a.parkCode.length === 0) continue;
    if (typeof a.title !== 'string' || a.title.trim().length === 0) continue;
    const url = typeof a.url === 'string' && /^https:\/\/\S+$/.test(a.url) && a.url.length <= URL_MAX ? a.url : null;
    alerts.push({
      id: a.id,
      parkCode: a.parkCode.toLowerCase(),
      title: a.title.trim(),
      description: typeof a.description === 'string' ? a.description.trim() : '',
      category: typeof a.category === 'string' ? a.category.trim() : '',
      url,
    });
  }
  return { alerts, count: p.data.length, total, start };
}

/// The request for one chunk of park codes, one page of it. The key travels in
/// the `X-Api-Key` header, never in the URL, so it stays out of every log line
/// that prints a URL.
export function alertsUrl(parkCodes: readonly string[], start = 0): string {
  const u = new URL(NPS_ALERTS_URL);
  u.searchParams.set('parkCode', parkCodes.join(','));
  u.searchParams.set('limit', String(NPS_PAGE_LIMIT));
  if (start > 0) u.searchParams.set('start', String(start));
  return u.toString();
}

export function chunk<T>(items: readonly T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

/// Lower case, accents dropped, every run of non-letters and non-digits one
/// space, padded so a phrase test is a word-boundary test.
export function normalise(text: string): string {
  return ` ${
    text
      .normalize('NFKD')
      .replace(/[̀-ͯ]/g, '')
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, ' ')
      .trim()
  } `;
}

const GENERIC_SUFFIX = / (trail|loop|course|path|route)$/;

/// The phrases that name a course: its whole name, and its name without a
/// trailing generic word when what is left is still a real name (four letters
/// or more), so "Loop" alone never names anything.
export function courseNames(name: string): string[] {
  const full = normalise(name).trim();
  if (full.length === 0) return [];
  const out = [full];
  const short = full.replace(GENERIC_SUFFIX, '');
  if (short !== full && short.replace(/ /g, '').length >= 4) out.push(short);
  return out;
}

const CLOSURE_WORDS = / (closed|closure|closures|closing|reroute|rerouted|detour|washout|washed out|flood|flooding|flooded|hazard|hazardous|unsafe|impassable) /;

const PARK_WIDE = [
  / park (is|are|will be|remains|remain|has been) (temporarily )?closed /,
  / park closed /,
  / entire park /,
  / all (park )?trails (are|will be|remain|remains|have been) (temporarily )?closed /,
  / all trails closed /,
];

/// The courses one alert may affect, each with how it matched. A park-wide
/// alert flags every course, the ones it also names as `named`: "the park is
/// closed except the Beaver Lake Trail" is one the operator has to read.
export function matchAlert(alert: NpsAlert, courses: readonly SweepCourse[]): Array<{ courseId: string; match: AlertMatch }> {
  const text = normalise(`${alert.title} ${alert.description}`);
  const information = alert.category.toLowerCase() === 'information';
  if (information && !CLOSURE_WORDS.test(text)) return [];
  const names = (c: SweepCourse) => courseNames(c.name).some((n) => text.includes(` ${n} `));
  const parkWide = PARK_WIDE.some((re) => re.test(text));
  const out: Array<{ courseId: string; match: AlertMatch }> = [];
  for (const c of courses) {
    if (names(c)) out.push({ courseId: c.id, match: 'named' });
    else if (parkWide) out.push({ courseId: c.id, match: 'park_wide' });
  }
  return out;
}

/// Every flag for one park: its alerts against its courses, clipped to the
/// column limits.
export function flagsForPark(alerts: readonly NpsAlert[], courses: readonly SweepCourse[]): CourseFlag[] {
  const out: CourseFlag[] = [];
  for (const alert of alerts) {
    for (const { courseId, match } of matchAlert(alert, courses)) {
      out.push({
        course_id: courseId,
        alert_id: alert.id,
        category: alert.category.slice(0, 60),
        title: alert.title.slice(0, TITLE_MAX),
        description: alert.description.slice(0, DESCRIPTION_MAX),
        url: alert.url,
        match,
      });
    }
  }
  return out;
}

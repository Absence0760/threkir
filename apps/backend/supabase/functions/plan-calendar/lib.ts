/// Pure halves of the plan-calendar feed: reading the token out of the URL,
/// the constant-time secret check, and the VCALENDAR body. No I/O, so every
/// branch is driven by `lib.test.ts` without a stack.
///
/// The body is decided by what `plan_calendar_feed_events` projects (the
/// active plan's non-rest workouts: id, date, kind, prescribed target) and by
/// what this file chooses to write from it: a localized kind label, the
/// target in the owner's unit, and nothing else. No location, no notes, no
/// plan or race name, no link.

import { escapeText, joinIcsLines, toIcsDate, toIcsUtc } from '../_shared/ics_text.ts';
import { normalizeEmailLocale } from '../auth-email/lib.ts';
import { timingSafeEqual } from '../_shared/webhook_security.ts';
import { isValidUuid } from '../_shared/input_validation.ts';

// ─────────────────── token ───────────────────

/// The token `rotate_plan_calendar_feed` mints: the feed row's id as 32 hex
/// characters, then 64 hex characters of secret.
const TOKEN = /^([0-9a-f]{32})([0-9a-f]{64})$/;

export interface FeedToken {
  feedId: string;
  secret: string;
}

/// The token in `/plan-calendar/<token>.ics` (the `.ics` suffix optional,
/// because some clients strip it and Outlook wants it). Null for anything
/// else, including a path with more segments after the token.
export function parseFeedToken(url: string): FeedToken | null {
  let path: string;
  try {
    path = new URL(url).pathname;
  } catch {
    return null;
  }
  const segments = path.split('/').filter((s) => s.length > 0);
  const i = segments.lastIndexOf('plan-calendar');
  if (i < 0 || i !== segments.length - 2) return null;
  const raw = segments[i + 1].replace(/\.ics$/i, '').toLowerCase();
  const m = TOKEN.exec(raw);
  if (!m) return null;
  const h = m[1];
  const feedId = `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
  if (!isValidUuid(feedId)) return null;
  return { feedId, secret: m[2] };
}

export async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

/// PostgREST serialises a bytea as `\x<hex>`.
export function byteaHex(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const hex = value.startsWith('\\x') ? value.slice(2) : value;
  return /^[0-9a-f]{64}$/i.test(hex) ? hex.toLowerCase() : null;
}

/// A hash that matches no secret, compared against when the feed row does not
/// exist so an unknown id costs the same digest + compare as a wrong secret.
const NO_FEED_HASH = '0'.repeat(64);

/// Whether `secret` hashes to the stored value, compared in constant time.
/// `storedHashHex` null (no such feed) still runs the full comparison.
export async function secretMatches(secret: string, storedHashHex: string | null): Promise<boolean> {
  const supplied = await sha256Hex(secret);
  const ok = timingSafeEqual(supplied, storedHashHex ?? NO_FEED_HASH);
  return ok && storedHashHex !== null;
}

/// A rate-limit key for one feed, in the synthetic UUIDv8 shape
/// `ipBucketKey` uses, so it can never collide with a real auth.users id.
export async function feedBucketKey(feedId: string): Promise<string> {
  const hex = await sha256Hex(`plan-calendar-feed-v1:${feedId}`);
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-8${hex.slice(13, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
}

/// The coarse per-address ceiling. Calendar providers poll from shared
/// pools, so one address can carry thousands of subscribers' feeds; this
/// bucket only stops one address grinding the secret read at network rate.
/// The per-feed bucket (30 an hour, after the secret check) is the tight one.
export const PLAN_CALENDAR_IP_PER_HOUR = 3600;

/// The per-address limiter, applied only to a caller the trusted header
/// names. A request it does not name is left to the per-feed bucket rather
/// than put in one bucket shared by every such caller, where one client
/// could lock every feed out.
export function planCalendarIpLimiter(
  ipOf: (req: Request) => string | null,
  check: (req: Request) => Promise<Response | null>,
): (req: Request) => Promise<Response | null> {
  return (req) => (ipOf(req) === null ? Promise.resolve(null) : check(req));
}

// ─────────────────── feed document ───────────────────

export const WORKOUT_KINDS = [
  'easy',
  'long',
  'recovery',
  'tempo',
  'interval',
  'marathon_pace',
  'race',
  'walk_run',
] as const;
export type FeedWorkoutKind = (typeof WORKOUT_KINDS)[number];

export interface FeedWorkout {
  id: string;
  date: string;
  kind: FeedWorkoutKind;
  targetDistanceM: number | null;
  targetDurationS: number | null;
  targetPaceSecPerKm: number | null;
  targetPaceEndSecPerKm: number | null;
  targetPaceToleranceSec: number | null;
}

export interface FeedDocument {
  unit: 'km' | 'mi';
  locale: string;
  workouts: FeedWorkout[];
}

function positiveOrNull(v: unknown): number | null {
  return typeof v === 'number' && Number.isFinite(v) && v > 0 ? v : null;
}

/// Narrow what `plan_calendar_feed_events` returned. A workout row that does
/// not parse is dropped rather than failing the whole feed: one bad row should
/// cost one calendar entry, not every entry.
export function parseFeedDocument(raw: unknown): FeedDocument | null {
  if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const r = raw as Record<string, unknown>;
  const list = Array.isArray(r.workouts) ? r.workouts : [];
  const workouts: FeedWorkout[] = [];
  for (const item of list) {
    if (item === null || typeof item !== 'object') continue;
    const w = item as Record<string, unknown>;
    if (typeof w.id !== 'string' || !isValidUuid(w.id)) continue;
    if (typeof w.date !== 'string' || toIcsDate(w.date) === null) continue;
    if (typeof w.kind !== 'string' || !(WORKOUT_KINDS as readonly string[]).includes(w.kind)) continue;
    workouts.push({
      id: w.id,
      date: w.date,
      kind: w.kind as FeedWorkoutKind,
      targetDistanceM: positiveOrNull(w.target_distance_m),
      targetDurationS: positiveOrNull(w.target_duration_seconds),
      targetPaceSecPerKm: positiveOrNull(w.target_pace_sec_per_km),
      targetPaceEndSecPerKm: positiveOrNull(w.target_pace_end_sec_per_km),
      targetPaceToleranceSec: positiveOrNull(w.target_pace_tolerance_sec),
    });
  }
  return {
    unit: r.unit === 'mi' ? 'mi' : 'km',
    locale: normalizeEmailLocale(typeof r.locale === 'string' ? r.locale : null),
    workouts,
  };
}

// ─────────────────── labels ───────────────────

/// The `workoutKind.*` strings of the web catalogue
/// (apps/web/src/lib/i18n/locales/*.ts), copied verbatim so a workout reads
/// the same in the calendar as on the plan page. `lib.test.ts` reads every
/// web locale and fails when a value here stops matching.
export const KIND_LABELS: Record<string, Record<FeedWorkoutKind, string>> = {
  en: {
    easy: 'Easy',
    long: 'Long run',
    recovery: 'Recovery',
    tempo: 'Tempo',
    interval: 'Intervals',
    marathon_pace: 'Marathon pace',
    race: 'Race',
    walk_run: 'Walk-run',
  },
  de: {
    easy: 'Locker',
    long: 'Langer Lauf',
    recovery: 'Erholung',
    tempo: 'Tempo',
    interval: 'Intervalle',
    marathon_pace: 'Marathontempo',
    race: 'Wettkampf',
    walk_run: 'Geh-Lauf',
  },
  fr: {
    easy: 'Facile',
    long: 'Sortie longue',
    recovery: 'Récupération',
    tempo: 'Tempo',
    interval: 'Fractionné',
    marathon_pace: 'Allure marathon',
    race: 'Course',
    walk_run: 'Marche-course',
  },
  es: {
    easy: 'Suave',
    long: 'Tirada larga',
    recovery: 'Recuperación',
    tempo: 'Tempo',
    interval: 'Series',
    marathon_pace: 'Ritmo de maratón',
    race: 'Carrera',
    walk_run: 'Caminar-correr',
  },
  ja: {
    easy: 'イージー',
    long: 'ロング走',
    recovery: 'リカバリー',
    tempo: 'テンポ',
    interval: 'インターバル',
    marathon_pace: 'マラソンペース',
    race: 'レース',
    walk_run: 'ウォークラン',
  },
  'pt-BR': {
    easy: 'Leve',
    long: 'Longão',
    recovery: 'Recuperação',
    tempo: 'Tempo',
    interval: 'Intervalado',
    marathon_pace: 'Ritmo de maratona',
    race: 'Prova',
    walk_run: 'Caminhada-corrida',
  },
  'pt-PT': {
    easy: 'Leve',
    long: 'Longão',
    recovery: 'Recuperação',
    tempo: 'Tempo',
    interval: 'Intervalado',
    marathon_pace: 'Ritmo de maratona',
    race: 'Prova',
    walk_run: 'Caminhada-corrida',
  },
};

const METRES_PER_MILE = 1609.344;

function paceText(secPerKm: number, unit: 'km' | 'mi'): string {
  const perUnit = Math.round(unit === 'mi' ? secPerKm * (METRES_PER_MILE / 1000) : secPerKm);
  return `${Math.floor(perUnit / 60)}:${String(perUnit % 60).padStart(2, '0')}`;
}

function distanceText(metres: number, unit: 'km' | 'mi', locale: string): string {
  const value = unit === 'mi' ? metres / METRES_PER_MILE : metres / 1000;
  return new Intl.NumberFormat(locale, {
    style: 'unit',
    unit: unit === 'mi' ? 'mile' : 'kilometer',
    unitDisplay: 'short',
    maximumFractionDigits: 1,
  }).format(value);
}

function durationText(seconds: number, locale: string): string {
  return new Intl.NumberFormat(locale, {
    style: 'unit',
    unit: 'minute',
    unitDisplay: 'short',
    maximumFractionDigits: 0,
  }).format(Math.round(seconds / 60));
}

/// The prescribed pace, in the owner's unit: a single pace, a band around it
/// (`target_pace_tolerance_sec` is stored per km, so it is converted too), or
/// a progression from the start pace to the end pace.
export function targetPaceText(w: FeedWorkout, unit: 'km' | 'mi'): string | null {
  if (w.targetPaceSecPerKm === null) return null;
  const start = paceText(w.targetPaceSecPerKm, unit);
  if (w.targetPaceEndSecPerKm !== null && Math.round(w.targetPaceEndSecPerKm) !== Math.round(w.targetPaceSecPerKm)) {
    return `${start}–${paceText(w.targetPaceEndSecPerKm, unit)}/${unit}`;
  }
  if (w.targetPaceToleranceSec !== null) {
    const tol = Math.round(unit === 'mi' ? w.targetPaceToleranceSec * (METRES_PER_MILE / 1000) : w.targetPaceToleranceSec);
    return `${start}/${unit} ±${tol}s`;
  }
  return `${start}/${unit}`;
}

/// `SUMMARY` and `DESCRIPTION` for one workout. The summary is the kind and
/// the headline target (distance, else duration); the description is every
/// prescribed figure, so the pace is there when the calendar entry is opened.
export function workoutText(w: FeedWorkout, doc: Pick<FeedDocument, 'unit' | 'locale'>): {
  summary: string;
  description: string | null;
} {
  const labels = KIND_LABELS[doc.locale] ?? KIND_LABELS.en;
  const kind = labels[w.kind];
  const distance = w.targetDistanceM !== null ? distanceText(w.targetDistanceM, doc.unit, doc.locale) : null;
  const duration = w.targetDurationS !== null ? durationText(w.targetDurationS, doc.locale) : null;
  const pace = targetPaceText(w, doc.unit);
  const headline = distance ?? duration;
  const parts = [distance, duration, pace].filter((p): p is string => p !== null);
  return {
    summary: headline ? `${kind} · ${headline}` : kind,
    description: parts.length ? parts.join(' · ') : null,
  };
}

/// How often a subscribed calendar is asked to re-read the feed. Google and
/// Outlook set their own schedule whatever this says; Apple Calendar honours it.
export const REFRESH_INTERVAL = 'PT6H';

/// The whole VCALENDAR. Every workout is an all-day entry (VALUE=DATE, DTEND
/// the following day, as RFC 5545 §3.6.1 reads an exclusive end), marked
/// TRANSPARENT so a training day never shows the runner as busy. The UID is
/// the workout's id, so a moved or edited workout updates its entry instead
/// of duplicating it, and one that is deleted drops out on the next read.
export function buildPlanFeedIcs(doc: FeedDocument, nowMs: number): string {
  const dtStamp = toIcsUtc(new Date(nowMs).toISOString())!;
  const lines: string[] = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Threkir//Run App//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'X-WR-CALNAME:Threkir',
    `REFRESH-INTERVAL;VALUE=DURATION:${REFRESH_INTERVAL}`,
    `X-PUBLISHED-TTL:${REFRESH_INTERVAL}`,
  ];
  for (const w of doc.workouts) {
    const start = toIcsDate(w.date);
    const end = toIcsDate(w.date, 1);
    if (!start || !end) continue;
    const { summary, description } = workoutText(w, doc);
    lines.push(
      'BEGIN:VEVENT',
      `UID:plan-workout-${w.id}@threkir.com`,
      `DTSTAMP:${dtStamp}`,
      `DTSTART;VALUE=DATE:${start}`,
      `DTEND;VALUE=DATE:${end}`,
      `SUMMARY:${escapeText(summary)}`,
    );
    if (description) lines.push(`DESCRIPTION:${escapeText(description)}`);
    lines.push('TRANSP:TRANSPARENT', 'END:VEVENT');
  }
  lines.push('END:VCALENDAR');
  return joinIcsLines(lines);
}

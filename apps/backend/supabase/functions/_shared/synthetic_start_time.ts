/// Synthetic UTC start time for date-only imported results.
///
/// The race-results importer ingests a result that carries a calendar
/// date but no time-of-day or timezone: the RunSignUp and ChronoTrack
/// feeds and a pasted result carry a race date with no start clock.
/// `runs.started_at` is a `timestamptz`, so we synthesise one by
/// appending this suffix to the ISO (YYYY-MM-DD) date. The choice of
/// hour determines which timezones get the right LOCAL calendar date
/// when their dashboard / heatmap reads the run back.
///
/// Persona-hunt finding Pro #5: T08:00:00Z was a UK-centric default.
/// At UTC-10 (Hawaii) and UTC-11 (American Samoa), 08:00 UTC wraps
/// backward to the PREVIOUS local calendar day. A Saturday result
/// would land on Friday in the runner's heatmap.
///
/// T10:00:00Z covers UTC-10 (Hawaii) through UTC+13 (New Zealand
/// NZDT) — the realistic worldwide audience. The remaining edge case
/// is Samoa (UTC+14 during DST), which crosses the dateline to land
/// one calendar day forward. That's a known acceptable trade — no
/// single UTC hour can satisfy every offset in the 26-hour worldwide
/// range simultaneously. Pinned by race-results-import's lib.test.ts.
export const SYNTHETIC_START_TIME_UTC = 'T10:00:00Z';

// Race start modes (#1306, decisions § 2400-§ 2401), spec `race_start_modes v1`.
//
// The pure half of the three modes, shared with mobile `race_start_modes.dart`
// through `fixtures/race_start_modes_cases.json`:
//
//   * effectiveRaceStatus mirrors `private.race_session_effective_status`: a
//     session is judged on the server clock, because the per-minute job moves
//     the stored status up to a minute late.
//   * raceCountdownS / voiceCountdownCue time the scheduled-GO countdown on
//     the server clock (device clock + a sampled offset).
//   * startOffsetFromLocal / localFromStartOffset turn an offset from the
//     occurrence into a day-and-wall-time pair the editor shows, and back.
//   * selfTimedAttemptState decides what a runner's Self-timed banner offers.
//   * validateStartSettings mirrors the events CHECKs, so the editor refuses
//     what the database would.
//
// selfTimedBoard is web-only (the spectator page has no mobile twin).

import type { SessionStartMode } from './course_gates';

export type RaceStatus = 'armed' | 'running' | 'finished' | 'cancelled';

export interface StartModeSession {
	status: RaceStatus;
	startMode: SessionStartMode;
	scheduledStartAt: string | null;
	windowOpensAt: string | null;
	windowClosesAt: string | null;
}

/** The longest a self-timed window (or a scheduled race's auto-end) lasts. */
export const RACE_WINDOW_MAX_S = 7 * 24 * 3600;
/** The shortest window the database accepts. */
export const RACE_WINDOW_MIN_S = 60;
/** A scheduled GO sits within a day either side of the occurrence's start. */
export const RACE_SCHEDULED_OFFSET_MAX_S = 24 * 3600;
/** A window opens up to a day before the occurrence and up to a week after. */
export const RACE_WINDOW_OPEN_OFFSET_MIN_S = -24 * 3600;
export const RACE_WINDOW_OPEN_OFFSET_MAX_S = 7 * 24 * 3600;
/** The seconds-left marks the run screen speaks during a scheduled countdown. */
export const VOICE_COUNTDOWN_MARKS_S = [10, 5, 3, 2, 1] as const;

const ms = (iso: string | null): number | null => {
	if (iso == null) return null;
	const t = Date.parse(iso);
	return Number.isFinite(t) ? t : null;
};

/** The status a session is in on the server clock. */
export function effectiveRaceStatus(session: StartModeSession, serverNowMs: number): RaceStatus {
	const { status, startMode } = session;
	if (status === 'finished' || status === 'cancelled') return status;
	if (startMode === 'host_go') return status;
	const start = ms(session.scheduledStartAt) ?? ms(session.windowOpensAt);
	const close = ms(session.windowClosesAt);
	if (close != null && close <= serverNowMs && (status === 'running' || (start != null && start <= serverNowMs))) {
		return 'finished';
	}
	if (status === 'armed' && start != null && start <= serverNowMs) return 'running';
	return status;
}

/** The instant a session's clock starts: the scheduled GO or the window's opening. */
export function raceStartInstant(session: StartModeSession): string | null {
	return session.startMode === 'scheduled'
		? session.scheduledStartAt
		: session.startMode === 'self_timed'
			? session.windowOpensAt
			: null;
}

/** Whole seconds until `targetIso` on the server clock, never negative; null without a target. */
export function raceCountdownS(targetIso: string | null, deviceNowMs: number, serverOffsetMs: number): number | null {
	const target = ms(targetIso);
	if (target == null) return null;
	return Math.max(0, Math.ceil((target - (deviceNowMs + serverOffsetMs)) / 1000));
}

/**
 * The mark to speak when a countdown moves from `previousS` to `currentS`
 * seconds left, or null. A tick that skips a mark (the app was paused) speaks
 * nothing rather than a late number.
 */
export function voiceCountdownCue(previousS: number | null, currentS: number | null): number | null {
	if (previousS == null || currentS == null || currentS >= previousS) return null;
	for (const mark of VOICE_COUNTDOWN_MARKS_S) {
		if (currentS === mark && previousS === mark + 1) return mark;
	}
	return null;
}

export interface LocalStartOffset {
	/** Whole days after the occurrence's start date (negative: before). */
	dayOffset: number;
	/** Minutes after midnight on that day, 0-1439. */
	minuteOfDay: number;
}

/**
 * The offset (seconds) from an occurrence starting at `startMinuteOfDay` to a
 * wall time `dayOffset` days later at `minuteOfDay`. Wall-clock arithmetic on
 * the event's own clock; a DST change inside the offset moves the instant by
 * the change, which the editor's preview shows.
 */
export function startOffsetFromLocal(startMinuteOfDay: number, local: LocalStartOffset): number {
	return (local.dayOffset * 1440 + local.minuteOfDay - startMinuteOfDay) * 60;
}

/** The inverse of startOffsetFromLocal, whole minutes. */
export function localFromStartOffset(startMinuteOfDay: number, offsetS: number): LocalStartOffset {
	const total = startMinuteOfDay + Math.round(offsetS / 60);
	const dayOffset = Math.floor(total / 1440);
	return { dayOffset, minuteOfDay: total - dayOffset * 1440 };
}

export type SelfTimedAttemptState = 'not_open' | 'join' | 'choose_course' | 'attempt' | 'closed';

/**
 * What a Self-timed banner offers a runner: join (RSVP) first when not going,
 * then a course when the race has several and none is chosen, then the
 * attempt. Outside the window, not_open or closed.
 */
export function selfTimedAttemptState(input: {
	effectiveStatus: RaceStatus;
	going: boolean;
	courseCount: number;
	courseChosen: boolean;
}): SelfTimedAttemptState {
	if (input.effectiveStatus === 'armed') return 'not_open';
	if (input.effectiveStatus !== 'running') return 'closed';
	if (!input.going) return 'join';
	if (input.courseCount > 1 && !input.courseChosen) return 'choose_course';
	return 'attempt';
}

export interface StartSettings {
	mode: SessionStartMode;
	scheduledOffsetS: number | null;
	windowOpenOffsetS: number | null;
	windowLengthS: number | null;
}

export type StartSettingsError =
	| 'scheduled_offset_required'
	| 'scheduled_offset_range'
	| 'window_open_required'
	| 'window_open_range'
	| 'window_length_required'
	| 'window_length_range';

/** The events CHECKs, in the order the editor reports them. Empty when valid. */
export function validateStartSettings(s: StartSettings): StartSettingsError[] {
	const out: StartSettingsError[] = [];
	if (s.mode === 'host_go') return out;
	if (s.mode === 'scheduled') {
		if (s.scheduledOffsetS == null) out.push('scheduled_offset_required');
		else if (Math.abs(s.scheduledOffsetS) > RACE_SCHEDULED_OFFSET_MAX_S) out.push('scheduled_offset_range');
	} else {
		if (s.windowOpenOffsetS == null) out.push('window_open_required');
		else if (s.windowOpenOffsetS < RACE_WINDOW_OPEN_OFFSET_MIN_S || s.windowOpenOffsetS > RACE_WINDOW_OPEN_OFFSET_MAX_S)
			out.push('window_open_range');
	}
	if (s.windowLengthS == null) out.push('window_length_required');
	else if (s.windowLengthS < RACE_WINDOW_MIN_S || s.windowLengthS > RACE_WINDOW_MAX_S) out.push('window_length_range');
	return out;
}

export interface BoardPing {
	userId: string;
	sinceStartLineS: number | null;
}

/**
 * The Self-timed on-course board (M13): runners with a start-line time,
 * longest on course first, then those without one (an Apple Watch relay, an
 * older app) in a separate block, each block keeping its input order on ties.
 */
export function selfTimedBoard<T extends BoardPing>(pings: readonly T[]): { timed: T[]; untimed: T[] } {
	const timed = pings
		.map((p, i) => ({ p, i }))
		.filter(({ p }) => p.sinceStartLineS != null)
		.sort((a, b) => b.p.sinceStartLineS! - a.p.sinceStartLineS! || a.i - b.i)
		.map(({ p }) => p);
	return { timed, untimed: pings.filter((p) => p.sinceStartLineS == null) };
}

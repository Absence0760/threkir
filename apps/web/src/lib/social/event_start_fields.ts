// The event editor's date + time inputs, read and written on the clock the
// event lives on. A series is wall-clock in its stored zone, so an organiser
// editing from another zone must see — and save — that zone's reading, or a
// re-save quietly moves every occurrence by the offset between the two.
// A legacy row with no stored zone keeps the editor's own clock, which is the
// clock it was created on.

import { instantForWallClock, isKnownTimeZone, wallClockIn } from './zoned_time';

export interface StartFields {
	/** `YYYY-MM-DD`, as an `<input type="date">` binds it. */
	date: string;
	/** `HH:MM`, as an `<input type="time">` binds it. */
	time: string;
}

/** The zone the editor reads and writes the start in: the event's own when it
 * has a usable one, otherwise null (the editor's local clock). */
export function editorZone(timezone: string | null | undefined): string | null {
	return isKnownTimeZone(timezone) ? timezone : null;
}

const p2 = (n: number) => String(n).padStart(2, '0');

export function startFieldsFor(iso: string, zone: string | null): StartFields {
	if (zone) {
		const w = wallClockIn(new Date(iso), zone);
		return { date: `${w.year}-${p2(w.month)}-${p2(w.day)}`, time: `${p2(w.hour)}:${p2(w.minute)}` };
	}
	const d = new Date(iso);
	return {
		date: `${d.getFullYear()}-${p2(d.getMonth() + 1)}-${p2(d.getDate())}`,
		time: `${p2(d.getHours())}:${p2(d.getMinutes())}`
	};
}

/** The instant the inputs name. In a zone, a reading a DST gap skips moves
 * forward and a repeated one takes the earlier instant — the rule the series
 * expands by. */
export function startIsoFor(fields: StartFields, zone: string | null): string {
	if (!zone) return new Date(`${fields.date}T${fields.time}`).toISOString();
	const [year, month, day] = fields.date.split('-').map(Number);
	const [hour, minute] = fields.time.split(':').map(Number);
	return instantForWallClock({ year, month, day, hour, minute, second: 0 }, zone).toISOString();
}

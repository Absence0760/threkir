// The `time_zone` universal pref (docs/backend/settings.md): the runner's IANA
// zone, read server-side by coach_roster_summary so a coach's roster picks the
// athlete's current plan by the athlete's local date (issue #1182). Written
// from the browser's zone on sign-in, and only when it differs from what is
// stored, so a runner who never moves writes it once. The write itself is in
// the root layout's settings hydrate. The server refuses a name Postgres does
// not know (22023), and settings_write.ts never queues a rejection for replay.
// Dart twin `apps/mobile_android/lib/time_zone_pref.dart`.

/// The browser's IANA zone, or null when the runtime cannot say.
export function browserTimeZone(): string | null {
	try {
		const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
		return typeof tz === 'string' && tz.trim() !== '' ? tz : null;
	} catch {
		return null;
	}
}

/// The zone to write, or null when nothing needs writing: the device zone is
/// unknown or blank, or the bag already holds it.
export function timeZoneToWrite(stored: unknown, device: string | null): string | null {
	const tz = device?.trim();
	if (!tz) return null;
	return stored === tz ? null : tz;
}

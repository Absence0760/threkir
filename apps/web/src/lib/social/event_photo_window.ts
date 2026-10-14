/// Which of a runner's runs may join an occurrence's photo gallery.
///
/// The database refuses an attendee photo whose run did not START inside
/// [occurrence − 2 h, occurrence + 24 h) (`run_photos_event_integrity`,
/// migration 20270807000001, decisions § 1905), so the run picker offers only
/// the runs that will be accepted rather than letting the upload fail. The two
/// bounds are named once in SQL (`private.event_photo_window_before/after`) and
/// mirrored here and in apps/mobile_android/lib/event_photo_window.dart.

export const EVENT_PHOTO_WINDOW_BEFORE_MS = 2 * 3600 * 1000;
export const EVENT_PHOTO_WINDOW_AFTER_MS = 24 * 3600 * 1000;

/// True when a run that started at `runStartedAt` may be attached to the
/// occurrence at `instanceStart`. Unparseable input is outside the window.
export function isRunInEventPhotoWindow(
	runStartedAt: string | null | undefined,
	instanceStart: string | null | undefined,
): boolean {
	if (runStartedAt == null || instanceStart == null) return false;
	const run = Date.parse(runStartedAt);
	const occ = Date.parse(instanceStart);
	if (!Number.isFinite(run) || !Number.isFinite(occ)) return false;
	return run >= occ - EVENT_PHOTO_WINDOW_BEFORE_MS && run < occ + EVENT_PHOTO_WINDOW_AFTER_MS;
}

/// True when a steward may already post run-less photos for the occurrence:
/// from two hours before it starts (set-up shots) onwards.
export function hasEventPhotoWindowOpened(
	instanceStart: string | null | undefined,
	nowMs: number,
): boolean {
	if (instanceStart == null) return false;
	const occ = Date.parse(instanceStart);
	if (!Number.isFinite(occ)) return false;
	return nowMs >= occ - EVENT_PHOTO_WINDOW_BEFORE_MS;
}

/**
 * Fail-closed gate on Drive this course (docs/features/course_drive.md,
 * decisions § 2380): the route and race pages' Maps hand-off and notes list.
 * The safety notice drivers see needs counsel review before it reaches them
 * (§ 150), so unset, empty or anything but 1 / true / yes / on hides every
 * entry point. Local dev + e2e turn it on in `.env.development`. The phone
 * reads the same flag as `COURSE_DRIVE_ENABLED`.
 */
import { PUBLIC_COURSE_DRIVE_ENABLED } from '$app/env/public';
import { isTruthyFlagValue } from '../core/env_flag';

export function courseDriveEnabled(): boolean {
	return isTruthyFlagValue(PUBLIC_COURSE_DRIVE_ENABLED);
}

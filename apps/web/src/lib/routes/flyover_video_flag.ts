/// Fail-closed gate on MapTiler in the flyover video export (decisions
/// § 2259). Unset, empty or anything but 1 / true / yes / on keeps MapTiler
/// out of the export; the operator sets it once MapTiler's plan terms are
/// confirmed to allow its terrain and imagery in a published video (§ 2251).
/// With the gate shut and no local tile-style override the export is not
/// offered at all (`videoBasemapPermitted`, called where the dev-only
/// `PUBLIC_TILE_STYLE_URL` is read, so this module names only the release
/// flag). The on-screen preview is unaffected either way.
import { PUBLIC_FLYOVER_VIDEO_MAPTILER_ENABLED } from '$app/env/public';
import { videoMaptilerKey } from './flyover_video_source';

export function flyoverVideoMaptilerKey(maptilerKey: string): string {
	return videoMaptilerKey(maptilerKey, PUBLIC_FLYOVER_VIDEO_MAPTILER_ENABLED);
}

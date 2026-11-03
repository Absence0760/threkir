/// Fail-closed gate on MapTiler in the flyover video export (decisions
/// § 2259). Unset, empty or anything but 1 / true / yes / on keeps MapTiler
/// out of the export; the operator sets it once MapTiler's plan terms are
/// confirmed to allow its terrain and imagery in a published video (§ 2251).
/// With the gate shut and no local tile-style override the export is not
/// offered at all (`videoBasemapPermitted`). The on-screen preview is
/// unaffected either way.
import { PUBLIC_FLYOVER_VIDEO_MAPTILER_ENABLED, PUBLIC_TILE_STYLE_URL } from '$app/env/public';
import { videoBasemapPermitted, videoMaptilerKey } from './flyover_video_source';

export function flyoverVideoMaptilerKey(maptilerKey: string): string {
	return videoMaptilerKey(maptilerKey, PUBLIC_FLYOVER_VIDEO_MAPTILER_ENABLED);
}

export function flyoverVideoBasemapPermitted(videoKey: string): boolean {
	return videoBasemapPermitted(videoKey, PUBLIC_TILE_STYLE_URL);
}

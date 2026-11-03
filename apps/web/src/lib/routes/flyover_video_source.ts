/// The MapTiler key the flyover VIDEO export may use, which is not the key the
/// on-screen preview uses (decisions § 2259). A video is a recording of the
/// map that gets published, and whether MapTiler's plan allows its terrain and
/// imagery in a published video is an operator check that has not been made
/// (§ 2251's pre-marketing item). Until `PUBLIC_FLYOVER_VIDEO_MAPTILER_ENABLED`
/// (read by `flyover_video_flag.ts`) is explicitly truthy the export gets no
/// key at all. The local `PUBLIC_TILE_STYLE_URL` / `PUBLIC_TERRAIN_URL`
/// overrides still win, as they do everywhere, because they name the
/// developer's own tileserver.
import { isTruthyFlagValue } from '../core/env_flag';

export function videoMaptilerKey(maptilerKey: string, allowFlag: string | null | undefined): string {
	return isTruthyFlagValue(allowFlag) ? maptilerKey.trim() : '';
}

/// Whether the export has a basemap it may record (decisions § 2259
/// amendment). Without a video key or a style override, `styleUrlForSlug`
/// falls to the OSM raster style, and rendering a video pulls thousands of
/// tiles from tile.openstreetmap.org — bulk use OSM's tile policy forbids, from
/// hosts the CSP does not allow. So the export is not offered at all rather
/// than rendered on that rung; the on-screen preview keeps its fallback.
export function videoBasemapPermitted(videoKey: string, tileStyleOverride: string | null | undefined): boolean {
	return videoKey.trim() !== '' || (tileStyleOverride?.trim() ?? '') !== '';
}

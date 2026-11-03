/// The MapTiler key the flyover VIDEO export may use, which is not the key the
/// on-screen preview uses (decisions § 2259). A video is a recording of the
/// map that gets published, and whether MapTiler's plan allows its terrain and
/// imagery in a published video is an operator check that has not been made
/// (§ 2251's pre-marketing item). Until `PUBLIC_FLYOVER_VIDEO_MAPTILER_ENABLED`
/// (read by `flyover_video_flag.ts`) is explicitly truthy the export renders
/// with no key at all, which the existing
/// resolvers already turn into the keyless rungs: the OSM raster style
/// (`styleUrlForSlug`) and the AWS Terrain Tiles (`resolveTerrainSource`).
/// The local `PUBLIC_TILE_STYLE_URL` / `PUBLIC_TERRAIN_URL` overrides still win
/// over both, as they do everywhere, because they name the developer's own
/// tileserver.
import { isTruthyFlagValue } from '../core/env_flag';

export function videoMaptilerKey(maptilerKey: string, allowFlag: string | null | undefined): string {
	return isTruthyFlagValue(allowFlag) ? maptilerKey.trim() : '';
}

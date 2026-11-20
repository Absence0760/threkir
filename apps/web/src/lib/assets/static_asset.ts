// The way app code names a file that has to stay at a fixed public path under
// apps/web/static/ (the favicon, the PWA icons, the default OG image): with a
// `?v=` of the file's own content hash, so a changed file reaches a browser or
// crawler that cached the old one. Anything only the app itself loads is not
// here: it lives beside this file and is imported through Vite, which hashes
// its name (decisions § 2600, conventions § Web static assets).

import { STATIC_ASSET_VERSIONS } from './static_asset_versions.ts';

export type StaticAssetPath = keyof typeof STATIC_ASSET_VERSIONS;

export function staticAsset(path: StaticAssetPath): string {
	return `${path}?v=${STATIC_ASSET_VERSIONS[path]}`;
}

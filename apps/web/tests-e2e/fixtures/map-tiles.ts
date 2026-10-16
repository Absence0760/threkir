import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

/**
 * Origins of the raster tiles in `static/osm-fallback-style.json`, the style
 * every map falls back to without a MapTiler key — which is CI. Read from the
 * style itself so a host it gains is stubbed too.
 */
export const FALLBACK_TILE_ORIGINS: ReadonlySet<string> = new Set(
	Object.values(
		(
			JSON.parse(
				readFileSync(resolve(import.meta.dirname, '..', '..', 'static', 'osm-fallback-style.json'), 'utf-8')
			) as { sources: Record<string, { tiles?: string[] }> }
		).sources
	).flatMap((source) => (source.tiles ?? []).map((url) => new URL(url.replace(/[{}]/g, '')).origin))
);

/** A 1×1 transparent PNG. */
export const BLANK_TILE = Buffer.from(
	'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
	'base64'
);

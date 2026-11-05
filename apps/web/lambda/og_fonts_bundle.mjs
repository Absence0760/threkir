// Copies the share cards' bundled face into a share Lambda's dist directory.
//
// `src/lib/share/og_png_render.ts` resolves its TTFs as `og-fonts/<file>`
// beside `import.meta.url`, which inside a Lambda is the bundled `index.mjs`
// at the zip root. The Lambda runtime has no system fonts, so a zip without
// this directory renders every card with no text (issue #1287); the build
// fails here instead. Each share Lambda's build.mjs calls this and zips
// `og-fonts` (guarded by src/lib/share/og_font_packaging.test.ts).

import { cpSync, existsSync, readdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const OG_FONT_DIR_NAME = 'og-fonts';

const source = resolve(dirname(fileURLToPath(import.meta.url)), '..', 'src', 'lib', 'share', OG_FONT_DIR_NAME);

/** @param {string} distDir */
export function copyOgFonts(distDir) {
	const faces = existsSync(source) ? readdirSync(source).filter((f) => f.endsWith('.ttf')) : [];
	if (faces.length === 0) {
		console.error(`[og-fonts] no .ttf faces in ${source}; the share cards would render without text`);
		process.exit(1);
	}
	cpSync(source, resolve(distDir, OG_FONT_DIR_NAME), { recursive: true });
}

/// The one face every rasterised share card is set in, and the files it ships
/// as. Pure strings so the card builders can import the family without pulling
/// a filesystem path into anything that might reach the browser.
///
/// The cards are rasterised by resvg in the share Lambdas, whose runtime has no
/// system fonts: a card that names a face the process cannot load has every
/// `<text>` dropped without an error, which is how the route, run, badge and
/// recap unfurls went out with no words on them (issue #1287). So the face is
/// bundled, resvg is told to load nothing else, and `og_png_render.ts` is the
/// only place that hands it to the rasteriser.

export const OG_FONT_FAMILY = 'Manrope';

/// What the card SVGs put in `font-family`. resvg only ever sees Manrope (the
/// generic `sans-serif` is mapped to it too); the tail is for a browser that
/// opens the SVG directly.
export const OG_FONT_STACK = `${OG_FONT_FAMILY},system-ui,-apple-system,Segoe UI,Roboto,sans-serif`;

/// Directory, relative to the rasterising module, the TTFs sit in. In the
/// source tree that is `src/lib/share/og-fonts/`; each share Lambda's build
/// copies the same directory beside its bundled `index.mjs`, which is where the
/// bundle's `import.meta.url` resolves it.
export const OG_FONT_DIR = 'og-fonts/';

/// Static instances of Google Fonts' variable master, the same bytes as
/// `packages/ui_kit/fonts/` (`assets/fonts/gen-manrope.py` writes both). Static
/// because resvg 2.x cannot drive a variable font's weight axis. The cards use
/// 500-900; 900 resolves to ExtraBold.
export const OG_FONT_FILES = [
	'Manrope-Regular.ttf',
	'Manrope-Medium.ttf',
	'Manrope-SemiBold.ttf',
	'Manrope-Bold.ttf',
	'Manrope-ExtraBold.ttf',
] as const;

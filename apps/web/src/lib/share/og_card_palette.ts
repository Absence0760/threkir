/// The two palettes every rasterised share card paints with.
///
/// These are `fixed-canvas` colours in the § 526 register's sense: each card is
/// concatenated into an SVG string and rendered to a PNG that leaves the site,
/// so no device theme reaches it and a CSS custom property would be a value the
/// rasteriser cannot resolve. A fixed canvas is exempt from THEMING, never from
/// contrast (§ 511) — so every ink below carries its measured ratio and the
/// ground it was measured against, computed rather than remembered (§ 534).
///
/// They live here because five card builders had spelled them independently:
/// the light palette four values deep in `og_run_image` / `og_route_image` /
/// `og_badge_image`, and the dark one five values deep in `og_recap_image` /
/// `recap_share_image` — 22 literals expressing 9 values, and the two recap
/// cards byte-identical. Two cards of the same product drifting apart is
/// invisible until someone puts the unfurl and the shared PNG side by side.
///
/// Each card keeps its own geometry, its own type scale and any hue that is
/// genuinely its own (the route card's start/finish caps), because those are
/// not shared and pretending otherwise would be the abstraction this project
/// warns about. Only the palette is common.

/// White-paper card: the run, route and badge unfurls, in the "Dusk, refined"
/// palette (decisions § 1772).
///
/// Measured against `bg` (#FFFFFF):
///   brand  4.763:1 — the "Threkir" wordmark, the light theme's coral accent.
///   ink   17.653:1 — the hero numeral.
///   muted  6.643:1 — the sub-line and source label.
export const OG_CARD_LIGHT = {
	bg: '#FFFFFF',
	brand: '#C24E24',
	ink: '#1A1722',
	muted: '#5F5A6B',
} as const;

/// Dark card: the recap unfurl (1200x630) and the in-app recap share PNG
/// (1080 square). Same palette, different geometry.
///
/// Measured against `bg` (#121117):
///   brand  7.600:1
///   hero  18.779:1 — the distance numeral.
///   label  7.755:1 — the letter-spaced kicker and stat labels.
///   stat  14.538:1 — the stat values and subhead.
export const OG_CARD_DARK = {
	bg: '#121117',
	brand: '#F08A5D',
	hero: '#FFFFFF',
	label: '#A9A4B6',
	stat: '#E4E1EA',
} as const;

/// The three inks the photo and sticker share images are drawn in, twin of
/// `RunShareInkSpec` in apps/mobile_android/lib/widgets/run_share_overlays.dart.
/// Labels take `muted`, numbers and the route take `text`; `shadow` sits under
/// both and `halo` is the soft casing under the route line. `accent` marks the
/// one figure an occasion sticker singles out, such as the fastest split: the
/// coral on the white and black inks, white on the coral one.
///
/// These grounds are not ours: the image lands on the runner's own photo, or on
/// whatever story the sticker is dropped onto, so no single ratio can be
/// measured. The shadow is what carries legibility, and the runner picks the
/// ink the photo needs — `light` for a dark photo, `dark` for a bright one. The
/// photo style adds its own scrim under the type (white under `dark`, black
/// otherwise) for the same reason.
export const SHARE_STICKER_INKS = {
	light: {
		text: '#FFFFFF',
		muted: 'rgba(255, 255, 255, 0.85)',
		accent: OG_CARD_DARK.brand,
		shadow: 'rgba(0, 0, 0, 0.55)',
		halo: 'rgba(0, 0, 0, 0.35)',
		scrim: '0, 0, 0',
	},
	dark: {
		text: OG_CARD_LIGHT.ink,
		muted: 'rgba(26, 23, 34, 0.8)',
		accent: OG_CARD_LIGHT.brand,
		shadow: 'rgba(255, 255, 255, 0.6)',
		halo: 'rgba(255, 255, 255, 0.5)',
		scrim: '255, 255, 255',
	},
	brand: {
		text: OG_CARD_DARK.brand,
		muted: 'rgba(255, 255, 255, 0.9)',
		accent: OG_CARD_DARK.hero,
		shadow: 'rgba(0, 0, 0, 0.6)',
		halo: 'rgba(0, 0, 0, 0.4)',
		scrim: '0, 0, 0',
	},
} as const;

/// The Threkir mark's tile gradient, the stops of apps/web/static/logo-mark.svg,
/// painted from its geometry so a capture never waits on an image decode.
export const THREKIR_MARK_GRADIENT = [OG_CARD_LIGHT.brand, '#A8426A', '#5B4B8A'] as const;

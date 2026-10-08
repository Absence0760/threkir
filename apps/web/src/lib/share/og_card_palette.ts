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

/// Grisnir's toon palette, per part, in the order the GLB's COLOR_0 blue
/// channel indexes them (`PARTS` in `scripts/brand/export_grisnir_gltf.py`).
/// A toon part is a shadow, base and highlight tone; a flat part draws its
/// base everywhere. The hexes are the model's own, so the 3D marker matches
/// the stills and the social videos.

export interface MascotPart {
	name: string;
	shadow: string;
	base: string;
	high: string;
}

export const MASCOT_PARTS: readonly MascotPart[] = [
	{ name: 'coat', shadow: '#C9BDD2', base: '#F4EEE6', high: '#FFFFFF' },
	{ name: 'hoof', shadow: '#221B29', base: '#3A3142', high: '#5A4E63' },
	// The horn's colours come from its gradient; this row is unused.
	{ name: 'horn', shadow: '#A8426A', base: '#C2477E', high: '#5B4B8A' },
	{ name: 'tag', shadow: '#A8426A', base: '#C2477E', high: '#E07AA4' },
	{ name: 'ear_inner', shadow: '#8E6C86', base: '#B08AA6', high: '#C4A3BA' },
	{ name: 'tag_glyph', shadow: '#F4EEE6', base: '#F4EEE6', high: '#F4EEE6' },
	{ name: 'eye', shadow: '#EE7440', base: '#EE7440', high: '#EE7440' },
	{ name: 'pupil', shadow: '#14101A', base: '#14101A', high: '#14101A' },
];

export const HORN_PART = 2;

/// The brand gradient along the horn, base (0) to tip (1), and the light ring
/// bands on its lower part.
export const HORN_RAMP: readonly [number, string][] = [
	[0, '#C2477E'],
	[0.3, '#A8426A'],
	[1, '#5B4B8A'],
];
export const HORN_BAND = '#D9739E';
export const INK = '#14101A';

/// The shading value is the larger of the normal's dot with a headlight from
/// the upper left of the view and its world-up component: below `SHADOW_BELOW`
/// a part takes its shadow tone, from `HIGH_FROM` its highlight.
export const SHADOW_BELOW = 0.7;
export const HIGH_FROM = 0.95;
/// View space, x right, y up, z toward the viewer.
export const LIGHT_VIEW: readonly [number, number, number] = [-0.25, 0.35, 0.9];

/// sRGB hex to linear floats, for the shader's uniforms.
export function linearRgb(hex: string): [number, number, number] {
	const h = hex.replace('#', '');
	const out: number[] = [];
	for (let i = 0; i < 3; i++) {
		const c = parseInt(h.slice(i * 2, i * 2 + 2), 16) / 255;
		out.push(c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
	}
	return [out[0], out[1], out[2]];
}

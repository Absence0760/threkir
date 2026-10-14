// The help-guide illustrations (docs/features/help.md § Illustrations): text-free
// SVG diagrams at `illustrations/<id>.svg`, one file serving every locale and
// both themes. A file may paint with only `currentColor` (the ink) and the
// placeholder colours below, one per theme token; each renderer swaps a
// placeholder for its own theme's colour — web for a CSS variable
// (`themeIllustration`), mobile for a ColorScheme colour (flutter_svg's
// ColorMapper, `help_illustration.dart`). flutter_svg reads no CSS variables,
// which is why the file holds a placeholder rather than a `var(...)`.
//
// Nothing here imports at run time, so scripts/check_help_illustrations.mjs
// loads it under plain Node, and the Dart test reads the palette out of this
// file's source.

/** token → the placeholder colour a file paints it with */
export const ILLUSTRATION_PALETTE = {
	accent: '#ff00a1',
	'accent-soft': '#ff00a2',
	muted: '#ff00a3',
	surface: '#ff00a4',
	tint: '#ff00a5',
	positive: '#ff00a6',
	caution: '#ff00a7',
} as const;

export type IllustrationToken = keyof typeof ILLUSTRATION_PALETTE;

export const ILLUSTRATION_ID = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
export const ILLUSTRATION_MAX_BYTES = 4096;

const ELEMENTS = new Set(['svg', 'g', 'path', 'circle', 'ellipse', 'rect', 'line', 'polyline', 'polygon']);
const ATTRIBUTES = new Set([
	'xmlns',
	'viewBox',
	'fill',
	'fill-opacity',
	'fill-rule',
	'stroke',
	'stroke-width',
	'stroke-linecap',
	'stroke-linejoin',
	'stroke-dasharray',
	'stroke-opacity',
	'opacity',
	'transform',
	'd',
	'cx',
	'cy',
	'r',
	'rx',
	'ry',
	'x',
	'y',
	'width',
	'height',
	'x1',
	'y1',
	'x2',
	'y2',
	'points',
]);
const COLOUR_ATTRIBUTES = new Set(['fill', 'stroke']);
const COLOURS = new Set<string>(['none', 'currentColor', ...Object.values(ILLUSTRATION_PALETTE)]);

const COMMENT = /<!--[\s\S]*?-->/g;
const TAG = /<(\/?)([A-Za-z][\w:-]*)((?:\s+[^\s="'<>/]+="[^"<>]*")*)\s*(\/?)>/g;
const ATTRIBUTE = /([^\s="'<>/]+)="([^"<>]*)"/g;

/// What is wrong with one illustration file, one message per problem; empty
/// when it is a clean, text-free, theme-painted diagram. An allow-list, not a
/// deny-list: only the shape elements and painting attributes above pass, so
/// `<text>`, `<script>`, `<foreignObject>`, `<image>`, `<style>`, an `href`, an
/// event handler or a `url(...)` all fail without being named one by one.
export function illustrationProblems(source: string): string[] {
	const problems: string[] = [];
	const bytes = new TextEncoder().encode(source).length;
	if (bytes > ILLUSTRATION_MAX_BYTES) problems.push(`${bytes} bytes, over the ${ILLUSTRATION_MAX_BYTES}-byte budget`);
	if (source.includes('<!') && source.replace(COMMENT, '').includes('<!')) problems.push('a DOCTYPE, CDATA or other <! declaration');
	if (source.includes('<?')) problems.push('an XML declaration or processing instruction (start with <svg)');
	const body = source.replace(COMMENT, '');
	const rest = body.replace(TAG, '').trim();
	if (rest !== '') problems.push(`text or a malformed tag outside the elements: "${rest.slice(0, 40)}"`);
	let depth = 0;
	let roots = 0;
	for (const match of body.matchAll(TAG)) {
		const [, closing, name = '', attributes = '', selfClosing] = match;
		if (!ELEMENTS.has(name)) problems.push(`<${name}> is not an allowed element (${[...ELEMENTS].join(', ')})`);
		if (closing) {
			depth--;
			continue;
		}
		if (depth === 0) {
			roots++;
			if (name !== 'svg') problems.push(`the root element is <${name}>, not <svg>`);
		}
		const seen = new Map<string, string>();
		for (const [, attr = '', value = ''] of attributes.matchAll(ATTRIBUTE)) seen.set(attr, value);
		for (const [attr, value] of seen) {
			if (!ATTRIBUTES.has(attr)) problems.push(`<${name} ${attr}> is not an allowed attribute`);
			if (COLOUR_ATTRIBUTES.has(attr) && !COLOURS.has(value)) {
				problems.push(`<${name} ${attr}="${value}"> paints a colour outside the token set (currentColor, none, ${Object.values(ILLUSTRATION_PALETTE).join(', ')})`);
			}
			if (/url\s*\(/i.test(value)) problems.push(`<${name} ${attr}> references url(...)`);
		}
		if (name === 'svg' && depth === 0) {
			if (seen.get('xmlns') !== 'http://www.w3.org/2000/svg') problems.push('the <svg> root needs xmlns="http://www.w3.org/2000/svg"');
			if (!/^0 0 \d+ \d+$/.test(seen.get('viewBox') ?? '')) problems.push('the <svg> root needs a viewBox="0 0 <w> <h>"');
			if (seen.has('width') || seen.has('height')) problems.push('the <svg> root takes no width or height, so it scales to its container');
		}
		if (!selfClosing) depth++;
	}
	if (roots !== 1) problems.push(`${roots} root elements, not one <svg>`);
	if (depth !== 0) problems.push('unbalanced tags');
	return problems;
}

/// The file as web paints it inline: each placeholder becomes its token's CSS
/// variable (`--illus-<token>`, set by HelpIllustration.svelte from the app
/// theme), comments go, and the drawing is hidden from assistive technology —
/// the figure around it carries the guide's alt text.
export function themeIllustration(source: string): string {
	let out = source.replace(COMMENT, '').trim();
	for (const [token, placeholder] of Object.entries(ILLUSTRATION_PALETTE)) {
		out = out.replaceAll(`"${placeholder}"`, `"var(--illus-${token})"`);
	}
	return out.replace(/^<svg\b/, '<svg aria-hidden="true" focusable="false"');
}

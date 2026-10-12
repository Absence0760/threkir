/**
 * Canonical HTML/XML escaping for strings interpolated into raw-HTML or
 * raw-SVG sinks — MapLibre `Popup.setHTML`, hand-built SVG (finisher
 * certificate, recap image), and the share-run Lambda `<head>` injection.
 *
 * Encodes the five characters that change parse context in HTML text, HTML
 * attribute, and XML/SVG contexts. Uses the numeric `&#39;` (not `&apos;`)
 * for the apostrophe so the output is valid in HTML4/5 and XML/SVG alike.
 *
 * This ESCAPES (the value survives as inert text). It is NOT a sanitiser —
 * for untrusted *markup* that must keep some tags, use the DOMPurify path in
 * `coach/markdown.ts` instead.
 */
export function escapeHtml(s: string): string {
	return s
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;')
		.replace(/'/g, '&#39;');
}

/// Code points outside XML 1.0's `Char` production — C0 controls other than
/// tab / LF / CR, lone surrogates, U+FFFE / U+FFFF. No entity can carry them,
/// so one in a single name made every XML reader (a GPX importer, resvg, a
/// browser loading an SVG) refuse the whole document. Same set and U+FFFD
/// replacement as the Art 20 exporter (export-data/render.ts).
const XML_FORBIDDEN_CHARS = /[^\t\n\r\u0020-\uD7FF\uE000-\uFFFD\u{10000}-\u{10FFFF}]/gu;

/**
 * `escapeHtml` for an XML document (GPX, KML, SVG, sitemap): also replaces
 * the code points XML cannot carry at all with U+FFFD, so one stray control
 * character in user text degrades to a replacement glyph instead of making
 * the file unreadable.
 */
export function escapeXml(s: string): string {
	return escapeHtml(s.replace(XML_FORBIDDEN_CHARS, '\uFFFD'));
}

/**
 * A value as an XML number, or null when it is not a finite number. Stored
 * coordinates and elevations reach the XML writers from JSON with no schema
 * in between and land inside quoted attributes, so anything else is dropped
 * rather than written as `NaN` or as markup.
 */
export function xmlNumber(v: unknown): string | null {
	return typeof v === 'number' && Number.isFinite(v) ? String(v) : null;
}

/**
 * Scheme guard for an `href` interpolated into a raw-HTML sink. `escapeHtml`
 * alone does NOT neutralise a `javascript:` / `data:` URI — none of those
 * strings contain the five escaped characters, so they survive attribute
 * escaping intact and execute on click. Any href that isn't built from a
 * fixed root-relative or http(s) template must pass through here first.
 *
 * Returns the URL when it is root-relative (`/…`, but not protocol-relative
 * `//host` or `/\host`, which the browser resolves to an external origin) or
 * http(s); otherwise `#`. Pair with `escapeHtml` for the attribute-context encoding:
 * `href="${escapeHtml(safeHref(url))}"`.
 */
export function safeHref(url: string): string {
	// The URL parser drops ASCII tab / LF / CR wherever they appear, so check
	// the string the browser will actually follow: `/\t/evil.com` is `//evil.com`.
	const u = url.trim().replace(/[\t\n\r]/g, '');
	if (/^https?:\/\//i.test(u)) return u;
	// `\` reads as `/` in an http(s) URL, so `/\host` is protocol-relative too.
	if (u[0] === '/' && u[1] !== '/' && u[1] !== '\\') return u;
	return '#';
}

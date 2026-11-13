/// Landing on a settings row from a search result (issue #1374, the web twin
/// of mobile's `SettingsAnchor`). A result links to `/settings/<page>#<id>`
/// (`settingRowId`, settings_search.ts); opening the page alone left the row
/// below the fold with nothing to say where it was, so the result seemed to do
/// nothing. This waits for the row (a page renders its rows once its settings
/// have loaded), scrolls it to the middle of the viewport, moves keyboard and
/// screen-reader focus to it, and highlights it briefly.

/// The class the row carries while it is highlighted. Styled in the settings
/// layout, with a static variant under `prefers-reduced-motion`.
export const SETTING_FLASH_CLASS = 'setting-flash';

/// How long the highlight stays on.
export const SETTING_FLASH_MS = 2000;

/// How long to wait for the row to render before giving up quietly: a gated
/// row the page does not show (a feature switched off) never appears.
export const SETTING_WAIT_MS = 5000;

const PREFIX = 'setting-';

/// The row id a URL fragment names, or null when it names none. Accepts the
/// fragment with or without its leading `#`, and decodes it.
export function settingIdFromHash(hash: string): string | null {
	let raw = hash.startsWith('#') ? hash.slice(1) : hash;
	try {
		raw = decodeURIComponent(raw);
	} catch {
		return null;
	}
	return raw.startsWith(PREFIX) && raw.length > PREFIX.length ? raw : null;
}

/// Whether [el] takes focus without a tabindex of its own.
export function isNativelyFocusable(el: Pick<Element, 'tagName'> & { hasAttribute(name: string): boolean }): boolean {
	const tag = el.tagName.toLowerCase();
	if (el.hasAttribute('tabindex')) return true;
	if (tag === 'a') return el.hasAttribute('href');
	// A regex, not a list of quoted tag names: one of them is an icon-font
	// ligature, and every quoted ligature under src/ joins the icon subset
	// (scripts/gen_web_icon_font.mjs).
	return /^(?:button|input|select|textarea)$/.test(tag);
}

/// Scroll [el] to the middle of the viewport, focus it and highlight it.
/// [reducedMotion] jumps instead of scrolling smoothly; the highlight's own
/// animation is turned off in CSS.
export function revealSettingRow(el: HTMLElement, reducedMotion: boolean): void {
	if (!isNativelyFocusable(el)) el.setAttribute('tabindex', '-1');
	el.scrollIntoView({ block: 'center', behavior: reducedMotion ? 'auto' : 'smooth' });
	el.focus({ preventScroll: true });
	el.classList.remove(SETTING_FLASH_CLASS);
	// Re-adding the class restarts the animation when the same result is
	// picked twice in a row.
	void el.offsetWidth;
	el.classList.add(SETTING_FLASH_CLASS);
	setTimeout(() => el.classList.remove(SETTING_FLASH_CLASS), SETTING_FLASH_MS);
}

/// Land on the row [hash] names in [doc], waiting up to [SETTING_WAIT_MS]
/// for it to render. Returns a function that stops waiting (call it when the
/// page navigates away first). Does nothing for a fragment that names no row.
export function focusSettingFromHash(hash: string, doc: Document = document): () => void {
	const id = settingIdFromHash(hash);
	if (id == null) return () => {};
	const reduced = doc.defaultView?.matchMedia?.('(prefers-reduced-motion: reduce)').matches ?? false;
	const now = doc.getElementById(id);
	if (now) {
		revealSettingRow(now, reduced);
		return () => {};
	}
	let done = false;
	const stop = () => {
		if (done) return;
		done = true;
		observer.disconnect();
		clearTimeout(timer);
	};
	const observer = new MutationObserver(() => {
		const el = doc.getElementById(id);
		if (!el) return;
		stop();
		revealSettingRow(el, reduced);
	});
	observer.observe(doc.body, { childList: true, subtree: true });
	const timer = setTimeout(stop, SETTING_WAIT_MS);
	return stop;
}

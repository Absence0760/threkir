/// The browser's Web Storage, reached in one place that cannot throw.
///
/// Firefox and Safari throw `SecurityError: The operation is insecure.` from
/// the `localStorage` / `sessionStorage` getter itself when the visitor has
/// blocked site data or the page is in a sandboxed frame. `typeof
/// localStorage` reads through the same getter, so the `typeof … ===
/// 'undefined'` idiom that guards SSR throws there too, and an unguarded one
/// in the root layout's mount took the page down for that visitor (Sentry
/// THREKIR-CLIENT-9). Reach storage through these; `browser_storage.test.ts`
/// fails on a bare `typeof localStorage` anywhere else.
///
/// A null return means "no storage here" (SSR, or blocked): the caller keeps
/// its in-memory default. `getItem` / `setItem` on a returned store can still
/// throw (quota, Safari private mode), so a write keeps its own try.

export function localStore(): Storage | null {
	try {
		return typeof localStorage === 'undefined' ? null : localStorage;
	} catch {
		return null;
	}
}

export function sessionStore(): Storage | null {
	try {
		return typeof sessionStorage === 'undefined' ? null : sessionStorage;
	} catch {
		return null;
	}
}

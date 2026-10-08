// The rune-free half of the i18n runtime: which catalogue parts are loaded,
// for which locale, and what dict `m()` should read. `store.svelte.ts` wraps
// it in `$state`; everything here is plain TS so it unit-tests under tsx
// (`catalogue_set.test.ts`) with fake loaders.
//
// A locale is a CORE catalogue plus one catalogue per AREA (`areas.ts`,
// decisions § 1802). The contract that makes the split safe is that the dict
// handed to `onChange` always holds core AND every area a route has asked for,
// in ONE locale — never a German core over an English area, never an area
// that a route needs and has not got. `m()` is synchronous, so a key that is
// not in the dict when a component renders is a key name on screen.

export type Catalogue = Readonly<Record<string, string>>;

/// Whether SvelteKit is about to HYDRATE server-rendered markup rather than
/// render into the SPA shell. `root` is app.html's single `display: contents`
/// div around `%sveltekit.body%`: in the shell (`200.html`, which every
/// production route but `/` and `/learn` boots from) it holds only the
/// bootstrap <script>; a prerendered page, and every page under the dev
/// server, has the rendered markup in it too.
///
/// It no longer decides which catalogues load: the reader's locale is applied
/// before the first render either way, and Svelte rewrites any text the
/// server wrote in English as it hydrates (decisions § 1812). What hydration
/// cannot rewrite is STRUCTURE, so the store uses this to tell a component
/// that picks a different subtree per locale (`structureLocale()`) to keep the
/// server's choice until the app has mounted.
export function holdsServerMarkup(
	root: { readonly children: ArrayLike<{ readonly tagName: string }> } | null | undefined,
): boolean {
	if (!root) return false;
	return Array.from(root.children).some((el) => el.tagName !== 'SCRIPT');
}

export type CatalogueSources<L extends string, A extends string> = {
	core: (locale: L) => Promise<Catalogue>;
	area: (locale: L, area: A) => Promise<Catalogue>;
};

export type CatalogueSetOptions<L extends string, A extends string> = {
	sources: CatalogueSources<L, A>;
	/// The locale whose core is bundled synchronously. Its areas are the
	/// stand-in when a translated area fails to load.
	fallbackLocale: L;
	fallbackCore: Catalogue;
	onChange: (locale: L, dict: Catalogue) => void;
	onError?: (what: string, error: unknown) => void;
};

export class CatalogueSet<L extends string, A extends string> {
	private readonly opts: CatalogueSetOptions<L, A>;
	private readonly cache = new Map<string, Promise<Catalogue>>();
	private readonly wanted = new Set<A>();
	private current: L;
	private target: L;
	private issued = 0;
	private applied = 0;

	constructor(opts: CatalogueSetOptions<L, A>) {
		this.opts = opts;
		this.current = opts.fallbackLocale;
		this.target = opts.fallbackLocale;
	}

	/// The locale of the dict last handed to `onChange`.
	get locale(): L {
		return this.current;
	}

	/// The areas any route has asked for so far. They stay loaded: a locale
	/// switch reloads all of them, so going back to an area never re-fetches.
	get areas(): ReadonlySet<A> {
		return this.wanted;
	}

	/// Load `areas` for the locale being shown (or being switched to) and
	/// resolve once the dict holds them. Never rejects: a failed fetch leaves
	/// the dict as it was, which is the layered-resilience floor — a route
	/// whose area did not arrive still renders, it does not blank.
	async ensureAreas(areas: readonly A[]): Promise<void> {
		const fresh = areas.filter((a) => !this.wanted.has(a));
		// Nothing new: either it is already in the dict, or a locale switch in
		// flight is fetching it with everything else.
		if (fresh.length === 0) return;
		for (const a of fresh) this.wanted.add(a);
		await this.compose(this.target);
	}

	/// Switch to `next`: core and every wanted area are fetched first and
	/// swapped in together. Resolves `false` (and keeps the current locale)
	/// when the core cannot be fetched.
	async setLocale(next: L): Promise<boolean> {
		if (next === this.current && next === this.target) return true;
		const previous = this.target;
		this.target = next;
		const ok = await this.compose(next);
		if (!ok && this.target === next) this.target = previous;
		return ok;
	}

	/// The first load of a page: apply `locale` with `areas` already in the
	/// dict, so the first render (or hydration) reads them in the reader's own
	/// language and nothing is fetched in any other. When `locale`'s core
	/// cannot be fetched the areas are composed in the locale still shown, so
	/// the route renders in that language rather than as key names. Resolves
	/// whether `locale` was applied.
	async open(locale: L, areas: readonly A[]): Promise<boolean> {
		for (const a of areas) this.wanted.add(a);
		const previous = this.target;
		this.target = locale;
		if (await this.compose(locale)) return true;
		if (this.target === locale) this.target = previous;
		await this.compose(this.target);
		return false;
	}

	private load(key: string, fetch: () => Promise<Catalogue>): Promise<Catalogue> {
		let hit = this.cache.get(key);
		if (!hit) {
			hit = fetch();
			this.cache.set(key, hit);
			// A rejected fetch is not cached, or one dropped request would pin
			// the area to "never loads" for the rest of the session.
			hit.catch(() => this.cache.delete(key));
		}
		return hit;
	}

	private async area(locale: L, area: A): Promise<Catalogue> {
		const { sources, fallbackLocale, onError } = this.opts;
		try {
			return await this.load(`${locale}:${area}`, () => sources.area(locale, area));
		} catch (e) {
			onError?.(`${locale}/${area}`, e);
			if (locale === fallbackLocale) return {};
			// The English area is the stand-in for a translated one that did not
			// arrive: a sentence in English beats a key name.
			try {
				return await this.load(`${fallbackLocale}:${area}`, () =>
					sources.area(fallbackLocale, area),
				);
			} catch (e2) {
				onError?.(`${fallbackLocale}/${area}`, e2);
				return {};
			}
		}
	}

	private async compose(locale: L): Promise<boolean> {
		const seq = ++this.issued;
		const { sources, fallbackLocale, fallbackCore, onError, onChange } = this.opts;
		// Core and areas are fetched in parallel: one round trip, not two.
		const areaParts = Promise.all([...this.wanted].map((a) => this.area(locale, a)));
		let core: Catalogue;
		try {
			core =
				locale === fallbackLocale
					? fallbackCore
					: await this.load(`${locale}:core`, () => sources.core(locale));
		} catch (e) {
			onError?.(`${locale}/core`, e);
			return false;
		}
		const parts = await areaParts;
		// Only the newest request may write. An older compose resolving late
		// holds fewer areas (or another locale) and would undo a newer one.
		if (seq < this.applied || locale !== this.target) return true;
		this.applied = seq;
		this.current = locale;
		onChange(locale, Object.assign({}, core, ...parts));
		return true;
	}
}

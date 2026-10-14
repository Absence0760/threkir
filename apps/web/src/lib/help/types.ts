// The shapes of an in-app help guide (docs/features/help.md). Type-only, so a
// guide file (`./guides/<id>.ts`) or a translation
// (`./translations/<locale>/<id>.ts`), each importing nothing but these types,
// loads under plain Node: scripts/gen_help_guides.mjs reads every one that way
// to write the per-locale JSON the phone apps and the web load, and the mobile
// renderer parses the same fields. Change a shape here and the Flutter reader
// has to change with it.

export type GuideKind = 'start' | 'how-to' | 'explainer';
export type Audience = 'everyone' | 'runner' | 'organiser' | 'participant' | 'spectator' | 'instructor' | 'club-admin';
export type Requirement = 'pro' | 'club-admin' | 'race-director' | 'stripe-connected' | 'paid-rail-live';
export type Platform = 'web' | 'android' | 'ios' | 'wear' | 'apple-watch';
export type Block =
	| { type: 'p'; text: string }
	| { type: 'steps'; items: string[] }
	| { type: 'list'; items: string[] }
	| { type: 'note'; tone: 'tip' | 'caution'; text: string };
export interface GuideSection {
	heading: string;
	blocks: Block[];
}
export interface Guide {
	/** kebab-case, equals the file name */
	id: string;
	/** <= 70 chars */
	title: string;
	/** <= 160 chars, one sentence */
	summary: string;
	kind: GuideKind;
	category: 'races' | 'paid-classes' | 'instructors' | 'clubs' | 'running' | 'account';
	audience: Audience[];
	requires?: Requirement[];
	/** where the described flow exists TODAY */
	platforms: Platform[];
	/** real SvelteKit route ids the guide describes, e.g. '/clubs/[slug]/events/[id]' */
	routes?: string[];
	sections: GuideSection[];
	/** other guide ids */
	related?: string[];
}

export type GuideCategory = Guide['category'];

/// One guide's text in another locale. Everything else (kind, audience,
/// routes, related …) is the English guide's; the sections mirror its
/// sections block for block, so a translation can only change words.
export interface GuideTranslation {
	/** the English guide's id, equal to the file name */
	id: string;
	title: string;
	summary: string;
	sections: GuideSection[];
	/** per translated string, keyed by its `translatableStrings` path: the hash of the English it was translated from (`node scripts/check_help_translations.mjs --hash <id>`) */
	sources: Record<string, string>;
}

/// A guide as a reader sees it: the English guide with a translation's words
/// in place, and `lang` saying which language they are in.
export type LocalizedGuide = Guide & { lang: string };

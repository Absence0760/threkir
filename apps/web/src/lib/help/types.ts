// The shapes of an in-app help guide (docs/features/help.md). Type-only, so a
// guide file (`./guides/<id>.ts`, which imports nothing but these types) loads
// under plain Node: scripts/gen_help_guides.mjs reads every guide that way to
// write the mobile apps' JSON copy, and the mobile renderer parses the same
// fields. Change a shape here and the Flutter reader has to change with it.

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

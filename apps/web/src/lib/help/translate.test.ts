// Unit tests for laying a translation over its help guide, and for reading
// the generated per-locale JSON back.
//   npx tsx --test src/lib/help/translate.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { describePath, localizeGuide, mergeFetchedGuides, structureProblems, translatableStrings } from './translate';
import type { Guide, GuideTranslation } from './types';

const guide: Guide = {
	id: 'g',
	title: 'Title',
	summary: 'Summary.',
	kind: 'how-to',
	category: 'clubs',
	audience: ['runner'],
	platforms: ['web', 'android'],
	routes: ['/clubs'],
	sections: [
		{
			heading: 'One',
			blocks: [
				{ type: 'p', text: 'Press **Save**.' },
				{ type: 'steps', items: ['a', 'b'] },
				{ type: 'note', tone: 'caution', text: 'n' },
			],
		},
	],
	related: ['other'],
};

const translation: GuideTranslation = {
	id: 'g',
	title: 'Titel',
	summary: 'Zusammenfassung.',
	sections: [
		{
			heading: 'Eins',
			blocks: [
				{ type: 'p', text: 'Tippe auf **Speichern**.' },
				{ type: 'steps', items: ['A', 'B'] },
				{ type: 'note', tone: 'caution', text: 'N' },
			],
		},
	],
	sources: {},
};

const clone = <T>(v: T): T => JSON.parse(JSON.stringify(v)) as T;

test('localizeGuide takes the words from the translation and everything else from the guide', () => {
	const out = localizeGuide(guide, translation, 'de');
	assert.equal(out.lang, 'de');
	assert.equal(out.title, 'Titel');
	assert.equal(out.summary, 'Zusammenfassung.');
	assert.deepEqual(out.sections, translation.sections);
	assert.deepEqual(
		[out.kind, out.category, out.audience, out.platforms, out.routes, out.related],
		[guide.kind, guide.category, guide.audience, guide.platforms, guide.routes, guide.related],
	);
});

test('localizeGuide falls back to the English guide, marked en', () => {
	assert.equal(localizeGuide(guide, undefined, 'de').lang, 'en');
	assert.equal(localizeGuide(guide, undefined, 'de').title, 'Title');
	assert.equal(localizeGuide(guide, translation, 'en').title, 'Title', 'English is never overlaid');
	const short = clone(translation);
	short.sections[0]!.blocks.pop();
	const out = localizeGuide(guide, short, 'de');
	assert.deepEqual([out.lang, out.title], ['en', 'Title']);
});

test('structureProblems names each way a translation departs from its guide', () => {
	assert.deepEqual(structureProblems(guide, translation), []);
	const items = clone(translation);
	(items.sections[0]!.blocks[1] as { items: string[] }).items.push('C');
	assert.deepEqual(structureProblems(guide, items), ['section 1 block 2: 3 items, the guide has 2']);
	const type = clone(translation);
	type.sections[0]!.blocks[0] = { type: 'list', items: ['x'] };
	assert.deepEqual(structureProblems(guide, type), ['section 1 block 1: a list, the guide has a p']);
	const tone = clone(translation);
	tone.sections[0]!.blocks[2] = { type: 'note', tone: 'tip', text: 'N' };
	assert.deepEqual(structureProblems(guide, tone), ['section 1 block 3: a tip note, the guide has a caution note']);
	assert.deepEqual(structureProblems(guide, { ...translation, id: 'h' }), ['translates "h", not "g"']);
	assert.deepEqual(structureProblems(guide, { ...translation, sections: [] }), ['0 sections, the guide has 1']);
});

test('translatableStrings lists every translated string by path, in reading order, and nothing else', () => {
	assert.deepEqual(translatableStrings(guide), [
		['title', 'Title'],
		['summary', 'Summary.'],
		['s0.heading', 'One'],
		['s0.b0', 'Press **Save**.'],
		['s0.b1.i0', 'a'],
		['s0.b1.i1', 'b'],
		['s0.b2', 'n'],
	]);
	const noisy = clone(guide) as Guide & { sections: { blocks: Record<string, unknown>[] }[] };
	noisy.sections[0]!.blocks[0]!.debug = true;
	assert.deepEqual(translatableStrings(noisy), translatableStrings(guide));
});

test('describePath names a string the way the structure messages do', () => {
	assert.equal(describePath('title'), 'title');
	assert.equal(describePath('s0.heading'), 'section 1 heading');
	assert.equal(describePath('s2.b0'), 'section 3 block 1');
	assert.equal(describePath('s0.b1.i3'), 'section 1 block 2 item 4');
});

test('mergeFetchedGuides keeps one guide per English guide, words from the file where they line up', () => {
	const fetched = [
		{ ...localizeGuide(guide, translation, 'de'), routes: ['/evil'], related: [] },
		{ id: 'stranger', lang: 'de', title: 'X', summary: 'Y', sections: [] },
	];
	const other: Guide = { ...guide, id: 'other', title: 'Other' };
	const [g, o] = mergeFetchedGuides([guide, other], fetched, 'de');
	assert.equal(g?.title, 'Titel');
	assert.deepEqual(g?.routes, ['/clubs'], 'only the words come from the fetched file');
	assert.deepEqual(g?.related, ['other']);
	assert.deepEqual([o?.id, o?.lang, o?.title], ['other', 'en', 'Other']);
});

test('mergeFetchedGuides ignores a file that is not guides, or guides in another language', () => {
	for (const raw of [null, {}, 'x', [1, null, { id: 'g' }], [{ ...localizeGuide(guide, translation, 'fr') }]]) {
		const [g] = mergeFetchedGuides([guide], raw, 'de');
		assert.deepEqual([g?.lang, g?.title], ['en', 'Title']);
	}
	const broken = [{ ...localizeGuide(guide, translation, 'de'), sections: [{ heading: 'Eins', blocks: [{ type: 'p' }] }] }];
	assert.equal(mergeFetchedGuides([guide], broken, 'de')[0]?.lang, 'en');
});

const illustrated: Guide = {
	...guide,
	sections: [{ heading: 'One', blocks: [{ type: 'p', text: 'x' }, { type: 'illustration', id: 'map', alt: 'A map.' }] }],
};
const illustratedDe: GuideTranslation = {
	...translation,
	sections: [{ heading: 'Eins', blocks: [{ type: 'p', text: 'X' }, { type: 'illustration', id: 'map', alt: 'Eine Karte.' }] }],
};

test('an illustration translates only its alt text, at a block path', () => {
	assert.deepEqual(translatableStrings(illustrated).slice(3), [
		['s0.b0', 'x'],
		['s0.b1', 'A map.'],
	]);
	const out = localizeGuide(illustrated, illustratedDe, 'de');
	assert.deepEqual(out.sections[0]!.blocks[1], { type: 'illustration', id: 'map', alt: 'Eine Karte.' });
});

test('a translation that names another illustration does not line up, and falls back to English', () => {
	const other = clone(illustratedDe);
	other.sections[0]!.blocks[1] = { type: 'illustration', id: 'chart', alt: 'Eine Karte.' };
	assert.deepEqual(structureProblems(illustrated, other), ['section 1 block 2: illustration "chart", the guide has "map"']);
	assert.equal(localizeGuide(illustrated, other, 'de').lang, 'en');
});

test('mergeFetchedGuides reads an illustration block, and a fetched file cannot swap the picture', () => {
	const fetched = [localizeGuide(illustrated, illustratedDe, 'de')];
	const [g] = mergeFetchedGuides([illustrated], clone(fetched), 'de');
	assert.equal(g?.lang, 'de');
	assert.deepEqual(g?.sections[0]?.blocks[1], { type: 'illustration', id: 'map', alt: 'Eine Karte.' });
	const swapped = clone(fetched);
	(swapped[0]!.sections[0]!.blocks[1] as { id: string }).id = 'other';
	assert.equal(mergeFetchedGuides([illustrated], swapped, 'de')[0]?.lang, 'en');
});

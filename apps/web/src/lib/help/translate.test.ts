// Unit tests for laying a translation over its help guide, and for reading
// the generated per-locale JSON back.
//   npx tsx --test src/lib/help/translate.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { localizeGuide, mergeFetchedGuides, structureProblems, translatableText } from './translate';
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
	source: '0000000000000000',
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

test('translatableText holds the words in a fixed shape and nothing else', () => {
	const noisy = clone(guide) as Guide & { sections: { blocks: Record<string, unknown>[] }[] };
	noisy.sections[0]!.blocks[0]!.debug = true;
	assert.deepEqual(translatableText(noisy), translatableText(guide));
	assert.deepEqual(Object.keys(translatableText(guide)), ['title', 'summary', 'sections']);
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

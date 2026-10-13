// Unit tests for the help-guide markup parser.
//   npx tsx --test src/lib/help/markup.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { markupProblems, parseMarkup, plainText, routeHref, sectionId } from './markup';

test('plain text is one text token', () => {
	assert.deepEqual(parseMarkup('Just words.'), [{ kind: 'text', text: 'Just words.' }]);
	assert.deepEqual(parseMarkup(''), []);
});

test('bold labels, emphasis and both link forms parse in order', () => {
	assert.deepEqual(parseMarkup('Press **Save**, *then* see [[guide:using-help|help]] or [[route:/races|Races]].'), [
		{ kind: 'text', text: 'Press ' },
		{ kind: 'strong', text: 'Save' },
		{ kind: 'text', text: ', ' },
		{ kind: 'em', text: 'then' },
		{ kind: 'text', text: ' see ' },
		{ kind: 'guide', id: 'using-help', text: 'help' },
		{ kind: 'text', text: ' or ' },
		{ kind: 'route', routeId: '/races', text: 'Races' },
		{ kind: 'text', text: '.' },
	]);
});

test('a parameterised route id parses like any other route link', () => {
	assert.deepEqual(parseMarkup('[[route:/clubs/[slug]/events/[id]|the event page]]'), [
		{ kind: 'route', routeId: '/clubs/[slug]/events/[id]', text: 'the event page' },
	]);
});

test('an asterisk inside a word is text, not emphasis', () => {
	assert.deepEqual(parseMarkup('5*3 and a*b'), [{ kind: 'text', text: '5*3 and a*b' }]);
});

test('a link with an unknown scheme or no label is invalid, and reported', () => {
	const [noLabel] = parseMarkup('[[guide:using-help]]');
	assert.equal(noLabel?.kind, 'invalid');
	const [unknown] = parseMarkup('[[page:/races|Races]]');
	assert.deepEqual(unknown, { kind: 'invalid', raw: 'page:/races|Races', text: 'Races' });
	assert.equal(markupProblems('[[page:/races|Races]]').length, 1);
});

test('markupProblems flags unclosed bold, unclosed links and raw HTML', () => {
	assert.deepEqual(markupProblems('Press **Save** then **Done.'), ['stray "*" in " then **Done."']);
	assert.equal(markupProblems('See [[guide:using-help|help').length, 1);
	assert.equal(markupProblems('A <b>bold</b> claim').length, 1);
	assert.equal(markupProblems('Nested **[[guide:a|b]]** links').length, 1);
	assert.deepEqual(markupProblems('Clean **Save** and *this* [[guide:a|b]].'), []);
});

test('plainText drops the markup and keeps the labels', () => {
	assert.equal(plainText('Press **Save** in [[route:/races|Races]].'), 'Press Save in Races.');
});

test('routeHref gives a URL only for routes without params, minus route groups', () => {
	assert.equal(routeHref('/races'), '/races');
	assert.equal(routeHref('/settings/integrations'), '/settings/integrations');
	assert.equal(routeHref('/clubs/[slug]'), null);
	assert.equal(routeHref('/(app)/help'), '/help');
	assert.equal(routeHref('/'), '/');
});

test('sectionId is a url-safe slug, accents folded', () => {
	assert.equal(sectionId('Opening help'), 'opening-help');
	assert.equal(sectionId('Café & results!'), 'cafe-results');
	assert.equal(sectionId('  Step 2: pay  '), 'step-2-pay');
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	SETTING_FLASH_CLASS,
	focusSettingFromHash,
	isNativelyFocusable,
	revealSettingRow,
	settingIdFromHash,
} from './setting_focus';
import { settingRowId } from './settings_search';

test('a fragment names a row only when it is a setting id', () => {
	const id = settingRowId('prefs.showNutrition');
	assert.equal(id, 'setting-prefs-showNutrition');
	assert.equal(settingIdFromHash(`#${id}`), id);
	assert.equal(settingIdFromHash(id), id);
	assert.equal(settingIdFromHash('#gym-nutrition'), null);
	assert.equal(settingIdFromHash('#setting-'), null);
	assert.equal(settingIdFromHash(''), null);
	assert.equal(settingIdFromHash('#%E0%A4%A'), null);
});

const el = (tag: string, attrs: Record<string, string> = {}) => ({
	tagName: tag.toUpperCase(),
	hasAttribute: (n: string) => n in attrs,
});

test('a heading or container takes a tabindex; a control or link does not need one', () => {
	assert.equal(isNativelyFocusable(el('h2')), false);
	assert.equal(isNativelyFocusable(el('div')), false);
	assert.equal(isNativelyFocusable(el('div', { tabindex: '-1' })), true);
	assert.equal(isNativelyFocusable(el('button')), true);
	assert.equal(isNativelyFocusable(el('a', { href: '/x' })), true);
	assert.equal(isNativelyFocusable(el('a')), false);
});

function fakeRow(tag = 'div') {
	const attrs: Record<string, string> = {};
	const classes = new Set<string>();
	const calls: string[] = [];
	return {
		calls,
		attrs,
		classes,
		tagName: tag.toUpperCase(),
		offsetWidth: 0,
		hasAttribute: (n: string) => n in attrs,
		setAttribute: (n: string, v: string) => (attrs[n] = v),
		scrollIntoView: (o: ScrollIntoViewOptions) => calls.push(`scroll:${o.block}:${o.behavior}`),
		focus: (o: FocusOptions) => calls.push(`focus:${o.preventScroll}`),
		classList: { add: (c: string) => classes.add(c), remove: (c: string) => classes.delete(c) },
	};
}

test('revealing a row centres it, focuses it without a second scroll, and highlights it', (t) => {
	t.mock.timers.enable({ apis: ['setTimeout'] });
	const row = fakeRow();
	revealSettingRow(row as unknown as HTMLElement, false);
	assert.equal(row.attrs.tabindex, '-1');
	assert.deepEqual(row.calls, ['scroll:center:smooth', 'focus:true']);
	assert.ok(row.classes.has(SETTING_FLASH_CLASS));
	t.mock.timers.tick(2000);
	assert.ok(!row.classes.has(SETTING_FLASH_CLASS));
});

test('reduced motion jumps instead of scrolling smoothly', (t) => {
	t.mock.timers.enable({ apis: ['setTimeout'] });
	const row = fakeRow('button');
	revealSettingRow(row as unknown as HTMLElement, true);
	assert.equal(row.attrs.tabindex, undefined);
	assert.deepEqual(row.calls, ['scroll:center:auto', 'focus:true']);
});

test('a row already on the page is revealed at once; a fragment naming none is ignored', (t) => {
	t.mock.timers.enable({ apis: ['setTimeout'] });
	const row = fakeRow();
	const doc = {
		defaultView: { matchMedia: () => ({ matches: true }) },
		getElementById: (id: string) => (id === 'setting-prefs-showNutrition' ? row : null),
	} as unknown as Document;
	focusSettingFromHash('#setting-prefs-showNutrition', doc);
	assert.deepEqual(row.calls, ['scroll:center:auto', 'focus:true']);
	row.calls.length = 0;
	focusSettingFromHash('#home-cards', doc);
	assert.deepEqual(row.calls, []);
});

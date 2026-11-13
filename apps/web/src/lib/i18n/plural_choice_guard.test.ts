import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { en } from './locales/en';

// A count that picks between two message keys in code (`n === 1 ? 'x.one' :
// 'x.many'`) applies English plural rules to every locale. French and
// Brazilian Portuguese put 0 in the singular, so the code-picked plural
// rendered « 0 courses ». The count belongs inside one ICU message
// (`{n, plural, one {# course} other {# courses}}`), where interpolate()
// asks Intl.PluralRules for the active locale (decisions § 2497). The
// mobile twin is apps/mobile_android/test/plural_choice_guard_test.dart.

const ROOT = resolve('src');
const KEYS = new Set(Object.keys(en));

// A comparison against 1 that chooses between two messages for a reason
// other than grammatical number. Each names why; the list may only shrink.
const EXEMPT: Record<string, string> = {
	'lib/components/RouteHeatmap.svelte routeHeatmap.locateDenied':
		'GeolocationPositionError.code 1 is PERMISSION_DENIED, not a count',
	'lib/components/RouteBuilder.svelte routeBuilder.locationPermissionDenied':
		'GeolocationPositionError.code 1 is PERMISSION_DENIED, not a count',
	'routes/routes/new/+page.svelte routeBuilder.locationPermissionDenied':
		'GeolocationPositionError.code 1 is PERMISSION_DENIED, not a count',
	'lib/components/RaceStartModePanel.svelte raceStart.joinChooseCourse':
		'more than one course is a different action (choose a course first)',
};

function sources(dir: string): string[] {
	return readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
		const p = join(dir, e.name);
		if (e.isDirectory()) return e.name === 'locales' ? [] : sources(p);
		return /\.(svelte|ts)$/.test(e.name) && !e.name.endsWith('.test.ts') ? [p] : [];
	});
}

// One operand of a ternary starting at `i`: up to the `:` (consequent) or
// to the first `,` `;` `)` `]` `}` (alternate) at bracket depth 0.
function operand(s: string, i: number, stopAtColon: boolean): string {
	let depth = 0;
	let quote = '';
	const start = i;
	for (; i < s.length; i++) {
		const c = s[i];
		if (quote) {
			if (c === '\\') i++;
			else if (c === quote) quote = '';
			continue;
		}
		if (c === "'" || c === '"' || c === '`') quote = c;
		else if (c === '(' || c === '[' || c === '{') depth++;
		else if (c === ')' || c === ']' || c === '}') {
			if (depth === 0) break;
			depth--;
		} else if (depth === 0 && (c === ',' || c === ';')) break;
		else if (depth === 0 && stopAtColon && c === ':') break;
		else if (depth === 0 && c === '?' && s[i + 1] !== '.' && s[i + 1] !== '?') {
			// A nested ternary: its own `? :` pair belongs to this operand.
			const inner = operand(s, i + 1, true);
			i += inner.length + 1;
		}
	}
	return s.slice(start, i);
}

function messageKeys(s: string): string[] {
	return [...s.matchAll(/['"]([\w]+\.[\w.]+)['"]/g)].map((m) => m[1]).filter((k) => KEYS.has(k));
}

export function oneChoices(src: string): { line: number; keys: [string, string] }[] {
	const out: { line: number; keys: [string, string] }[] = [];
	const re = /(?:[!=]==?|[<>]=?)\s*1\s*\?(?![.?])/g;
	for (let m = re.exec(src); m; m = re.exec(src)) {
		const at = m.index + m[0].length;
		const yes = operand(src, at, true);
		if (src[at + yes.length] !== ':') continue;
		const no = operand(src, at + yes.length + 1, false);
		const a = messageKeys(yes);
		const b = messageKeys(no);
		if (a.length && b.length) out.push({ line: src.slice(0, m.index).split('\n').length, keys: [a[0], b[0]] });
	}
	return out;
}

test('the scan finds a key choice made by a count of 1, inline or split', () => {
	const k = [...KEYS];
	const [x, y] = [k[0], k[1]];
	assert.equal(oneChoices(`m(n === 1 ? '${x}' : '${y}', { n })`).length, 1);
	assert.equal(oneChoices(`{n === 1\n\t? m('${x}')\n\t: m('${y}', { n })}`).length, 1);
	assert.equal(oneChoices(`n > 1 ? t('${y}', { n }) : t('${x}')`).length, 1);
	assert.equal(oneChoices(`m('${x}', { n })`).length, 0);
	assert.equal(oneChoices(`n === 1 ? a : '${y}'`).length, 0);
	assert.equal(oneChoices(`n === 1 ? 'not a key' : 'nor.this-one'`).length, 0);
});

test('no message is chosen by comparing a count with 1', () => {
	const offenders: string[] = [];
	const used = new Set<string>();
	for (const file of sources(ROOT)) {
		const rel = relative(ROOT, file);
		for (const { line, keys } of oneChoices(readFileSync(file, 'utf8'))) {
			const id = `${rel} ${keys[0]}`;
			if (id in EXEMPT) used.add(id);
			else offenders.push(`${rel}:${line} ${keys.join(' / ')}`);
		}
	}
	assert.deepEqual(
		offenders,
		[],
		'merge the pair into one ICU message ({n, plural, one {…} other {…}}, =1 for "tomorrow"-style exact phrases) and pass the count',
	);
	assert.deepEqual(
		Object.keys(EXEMPT).filter((id) => !used.has(id)),
		[],
		'stale exemption: the choice it covered is gone, so delete the entry',
	);
});

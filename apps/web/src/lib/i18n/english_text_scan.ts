// The scanner behind `english_text_guard.test.ts`: counts the English prose a
// TypeScript module carries in string literals. Comments are stripped, and a
// line that logs or throws is skipped, since that text reaches a log or an
// `errorCopy` call rather than a reader.

import { readdirSync, readFileSync } from 'node:fs';
import { join, relative } from 'node:path';

import { stripComments } from '../core/strip_comments';

/// A capitalised word and at least two more: "Not enough data yet", "Run by
/// {name}". Identifiers, keys, paths, URLs and single labels do not match.
const PROSE = /^[A-Z][a-z’']+(?:[ ,]+[A-Za-z’'${}.—–-]+){2,}/;
const NOT_PROSE = /https?:|[=<>]|\.\w+\(|^[A-Z][a-z]+ [A-Z][a-z]+ (Bold|Regular|Medium)$/;
const SKIP_LINE = /console\.|\bthrow\b|Error\(|\blogger\b|\blog\(/;

export function englishLiterals(source: string): string[] {
	const lines = stripComments(source)
		.split('\n')
		.filter((l) => !SKIP_LINE.test(l));
	const text = lines.join('\n');
	const out: string[] = [];
	const re = /(['"`])((?:(?!\1)[^\\\n]|\\.){8,})\1/g;
	let m: RegExpExecArray | null;
	while ((m = re.exec(text))) {
		const v = m[2];
		if (PROSE.test(v) && !NOT_PROSE.test(v)) out.push(v);
	}
	return out;
}

/// Every non-test `.ts` module under `dir`, as paths relative to `root`,
/// skipping the catalogues themselves: the locale files, the help guides'
/// English source (`help/guides`) and their translations.
const CATALOGUE_DIRS = new Set(['src/lib/i18n/locales', 'src/lib/help/guides', 'src/lib/help/translations']);

export function scannedModules(root: string, dir: string): string[] {
	const walk = (d: string): string[] =>
		readdirSync(d, { withFileTypes: true }).flatMap((e) => {
			const p = join(d, e.name);
			if (e.isDirectory()) return CATALOGUE_DIRS.has(relative(root, p)) ? [] : walk(p);
			return /\.ts$/.test(e.name) && !/\.(test|d)\.ts$/.test(e.name) ? [p] : [];
		});
	return walk(dir).map((p) => relative(root, p));
}

export function englishCounts(root: string, dir: string): Map<string, number> {
	const counts = new Map<string, number>();
	for (const f of scannedModules(root, dir)) {
		const n = englishLiterals(readFileSync(join(root, f), 'utf8')).length;
		if (n > 0) counts.set(f, n);
	}
	return counts;
}

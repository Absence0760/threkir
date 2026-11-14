// Guard-rail: every on-screen label a help guide quotes is a label the app
// shows (docs/features/help.md § Guards).
//
// A guide marks a UI label as `**Save**` and the reader goes looking for
// exactly that text. Nothing breaks when the label is renamed in a catalogue,
// or was never the label at all, so this reads every `**label**` in every
// guide and every translation and looks for it among the app's strings in the
// guide's own locale:
//
//   web           apps/web/src/lib/i18n/locales/<locale>.ts
//   phone         apps/mobile_android/lib/l10n/app_<locale>.arb (iOS shares it)
//   Wear OS       apps/watch_wear/android/app/src/main/res/values[-<locale>]/strings.xml
//   Apple Watch   apps/watch_ios/WatchApp/Localizable.xcstrings
//
// Every catalogue of the locale counts, whatever the guide's `platforms`: a
// web guide still tells a racer what the phone app's button says, and a
// paragraph is not tagged with the platform it describes.
//
// A label matches a catalogue string that reads the same once both are
// normalised (`...` is `…`, runs of spaces are one). A placeholder (`{n}`,
// `%1$s`, `%@`) matches any run of digits, spaces and punctuation, or nothing, together with the
// brackets around it, so `**Pending requests**` matches "Pending requests
// ({n})" and `**Show all 12 upcoming**` matches "Show all {n} upcoming". It
// never matches a word: "{a} of {b}" would otherwise match every label with
// "of" in it, and did hide two wrong labels and dozens of OS labels before it
// was narrowed. An ICU plural or select matches any one of its branches. A guide may also quote the leading clause of a longer message
// ("a message starting **Tracking paused while you were away**"), so a
// string that begins with the label followed by a dash, colon or full stop
// matches. Case is never folded: the reader sees the case the app renders.
//
//   npx tsx --test src/lib/help/help_labels_guard.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

import { parseMarkup } from './markup';
import type { Block, Guide, GuideTranslation } from './types';
import { SUPPORTED_LOCALES, type Locale } from '../i18n/locale';

const HELP_DIR = import.meta.dirname;
const GUIDES_DIR = join(HELP_DIR, 'guides');
const TRANSLATIONS_DIR = join(HELP_DIR, 'translations');
const REPO_ROOT = resolve(HELP_DIR, '..', '..', '..', '..', '..');
const WEB_LOCALES = join(REPO_ROOT, 'apps/web/src/lib/i18n/locales');
const ARB_DIR = join(REPO_ROOT, 'apps/mobile_android/lib/l10n');
const WEAR_RES = join(REPO_ROOT, 'apps/watch_wear/android/app/src/main/res');
const XCSTRINGS = join(REPO_ROOT, 'apps/watch_ios/WatchApp/Localizable.xcstrings');

const ARB_FILE: Record<Locale, string> = {
	en: 'app_en.arb',
	de: 'app_de.arb',
	fr: 'app_fr.arb',
	es: 'app_es.arb',
	ja: 'app_ja.arb',
	'pt-PT': 'app_pt.arb',
	'pt-BR': 'app_pt_BR.arb',
};
const WEAR_VALUES: Record<Locale, string> = {
	en: 'values',
	de: 'values-de',
	fr: 'values-fr',
	es: 'values-es',
	ja: 'values-ja',
	'pt-PT': 'values-b+pt+PT',
	'pt-BR': 'values-b+pt+BR',
};

/// Labels a guide quotes that no catalogue of ours holds, because the app
/// does not draw them: the reader meets them in the operating system's own
/// settings and permission prompts, in the system's language. May only
/// shrink; an entry fails once the label matches a catalogue or the guide no
/// longer quotes it.
const NOT_IN_A_CATALOGUE: { guide: string; reason: string; labels: Partial<Record<Locale, string[]>> }[] = [
	{
		guide: 'location-permission',
		reason: "Android's and iOS's own location prompt, app-permission and battery settings, drawn by the system in the system language",
		labels: {
			en: [
				'Allow all the time',
				'Precise',
				'While using the app',
				'Permissions',
				'Only this time',
				"Don't allow",
				'Always',
				'Allow While Using App',
				'Allow Once',
				"Don't Allow",
				'Battery',
				'Unrestricted',
				'Use precise location',
				'Privacy & Security',
				'Location Services',
				'While Using the App',
				'Precise Location',
			],
			de: [
				'Immer zulassen',
				'Genau',
				'Während der Nutzung der App',
				'Berechtigungen',
				'Standort',
				'Nur dieses Mal',
				'Nicht zulassen',
				'Immer',
				'Beim Verwenden der App erlauben',
				'Einmal erlauben',
				'Nicht erlauben',
				'Akku',
				'Nicht eingeschränkt',
				'Genauen Standort verwenden',
				'Datenschutz & Sicherheit',
				'Ortungsdienste',
				'Beim Verwenden der App',
				'Genauer Standort',
			],
			fr: [
				'Toujours autoriser',
				'Précise',
				"Lorsque vous utilisez l'appli",
				'Autorisations',
				'Uniquement cette fois-ci',
				'Ne pas autoriser',
				'Toujours',
				"Autoriser lorsque l'app est active",
				'Autoriser une fois',
				'Batterie',
				'Sans restriction',
				'Paramètres',
				'Applications',
				'Utiliser la position exacte',
				'Confidentialité et sécurité',
				'Service de localisation',
				"Lorsque l'app est active",
				'Position exacte',
			],
			es: [
				'Permitir todo el tiempo',
				'Precisa',
				'Mientras la aplicación está en uso',
				'Permisos',
				'Solo esta vez',
				'No permitir',
				'Siempre',
				'Permitir al usar la app',
				'Permitir una vez',
				'Batería',
				'Sin restricciones',
				'Aplicaciones',
				'Usar ubicación precisa',
				'Privacidad y seguridad',
				'Localización',
				'Cuando se use la app',
				'Ubicación exacta',
			],
			ja: [
				'常に許可',
				'正確',
				'アプリの使用時のみ',
				'権限',
				'位置情報',
				'おおよそ',
				'今回のみ',
				'許可しない',
				'常に',
				'Appの使用中は許可',
				'1度だけ許可',
				'バッテリー',
				'制限なし',
				'正確な位置情報を使用',
				'プライバシーとセキュリティ',
				'位置情報サービス',
				'このAppの使用中のみ許可',
				'正確な位置情報',
			],
			'pt-PT': [
				'Permitir sempre',
				'Precisa',
				'Enquanto estiver a utilizar a app',
				'Autorizações',
				'Apenas desta vez',
				'Não permitir',
				'Sempre',
				'Permitir durante a utilização da app',
				'Permitir uma vez',
				'Bateria',
				'Sem restrições',
				'Usar localização exata',
				'Privacidade e Segurança',
				'Serviços de Localização',
				'Durante a utilização da app',
				'Localização exata',
			],
			'pt-BR': [
				'Permitir o tempo todo',
				'Precisa',
				'Durante o uso do app',
				'Permissões',
				'Localização',
				'Apenas esta vez',
				'Não permitir',
				'Sempre',
				'Permitir Durante o Uso do App',
				'Permitir Uma Vez',
				'Não Permitir',
				'Bateria',
				'Sem restrições',
				'Usar local exato',
				'Ajustes',
				'Privacidade e Segurança',
				'Serviços de Localização',
				'Durante o Uso do App',
				'Localização Precisa',
			],
		},
	},
	{
		guide: 'record-your-first-run',
		reason: "Android's own background-location option, drawn by the system in the system language",
		labels: {
			en: ['Allow all the time'],
			de: ['Immer zulassen'],
			fr: ['Toujours autoriser'],
			es: ['Permitir todo el tiempo'],
			ja: ['常に許可'],
			'pt-PT': ['Permitir sempre'],
			'pt-BR': ['Permitir o tempo todo'],
		},
	},
];

// ---------------------------------------------------------------------------
// Matching

function normalise(s: string): string {
	return s
		.replace(/\.\.\./g, '…')
		.replace(/[  ]/g, ' ')
		.replace(/\s+/g, ' ')
		.trim();
}

const escapeRegex = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/// A placeholder, with the spaces around it: digits and punctuation, or nothing; never a letter.
const WILDCARD = '(?:[^\\p{L}]*)';

/// A bracketed aside holding a placeholder is a count (`({n})`, `（{n}件）`),
/// and a guide may leave it out: `Save entries ({n})` also reads as `Save entries`.
const COUNT_ASIDE = /\s*[(（][^()（）]*(?:\{[^{}]*\}|%(?:\d+\$)?(?:@|l{0,2}[dsfu]))[^()（）]*[)）]/gu;

/// The index of the `}` that closes the `{` at `open`.
function closing(s: string, open: number): number {
	let depth = 0;
	for (let i = open; i < s.length; i++) {
		if (s[i] === '{') depth++;
		else if (s[i] === '}' && --depth === 0) return i;
	}
	return -1;
}

/// An ICU message (web catalogue or ARB) as a regex source.
function icuPattern(message: string, inPlural = false): string {
	let out = '';
	let i = 0;
	while (i < message.length) {
		const ch = message[i];
		if (ch === '{') {
			const end = closing(message, i);
			if (end < 0) return out + escapeRegex(message.slice(i));
			const body = message.slice(i + 1, end);
			const choice = /^\s*\w+\s*,\s*(?:plural|select|selectordinal)\s*,/.exec(body);
			if (choice) {
				const branches: string[] = [];
				let j = choice[0].length;
				while (j < body.length) {
					const open = body.indexOf('{', j);
					if (open < 0) break;
					const close = closing(body, open);
					if (close < 0) break;
					branches.push(icuPattern(body.slice(open + 1, close), true));
					j = close + 1;
				}
				out += `(?:${branches.join('|')})`;
			} else {
				out += WILDCARD;
			}
			i = end + 1;
		} else if (ch === '#' && inPlural) {
			out += WILDCARD;
			i++;
		} else {
			out += escapeRegex(ch);
			i++;
		}
	}
	return out;
}

/// A printf-style string (Android resources, Apple string catalogues) as a regex source.
function printfPattern(message: string): string {
	return message
		.split(/(%(?:\d+\$)?(?:@|l{0,2}[dsfu]|\.\d+f))/)
		.map((part, i) => (i % 2 ? WILDCARD : escapeRegex(part)))
		.join('');
}

interface Template {
	/// The normalised string, which holds every letter a match can contain.
	text: string;
	source: string;
	compiled?: RegExp;
}

interface Catalogue {
	exact: Set<string>;
	literals: string[];
	templates: Template[];
}

/// A string with no letters outside its placeholders (`{name}`, `%1$s km`)
/// would match any label, so it is no label at all.
const hasWords = (pattern: string) => /\p{L}/u.test(pattern.split(WILDCARD).join(''));

function catalogue(messages: string[], toPattern: (m: string) => string): Catalogue {
	const literals = messages.map(normalise);
	const forms = [...new Set(literals.flatMap((text) => [text, normalise(text.replace(COUNT_ASIDE, ''))]))];
	const templates = forms.flatMap((text) => {
		const raw = toPattern(text);
		if (!hasWords(raw)) return [];
		const source = raw.split(` ${WILDCARD}`).join(WILDCARD).split(`${WILDCARD} `).join(WILDCARD);
		return source === escapeRegex(text) ? [] : [{ text, source }];
	});
	return { exact: new Set(forms), literals, templates };
}

// A placeholder never supplies a letter, so every word of a matching label is
// already in the template's text; only those few templates get compiled.
function templateMatches(t: Template, label: string, words: string[]): boolean {
	if (!words.every((w) => t.text.includes(w))) return false;
	t.compiled ??= new RegExp(`^${t.source}$`, 'u');
	return t.compiled.test(label);
}

function matches(label: string, cat: Catalogue): boolean {
	const l = normalise(label);
	if (cat.exact.has(l)) return true;
	const words = l.match(/\p{L}+/gu) ?? [];
	if (cat.templates.some((t) => templateMatches(t, l, words))) return true;
	return cat.literals.some((m) => m.startsWith(l) && /^\s*[—–:.：。]/u.test(m.slice(l.length)));
}

// ---------------------------------------------------------------------------
// Catalogues

function unescapeAndroid(s: string): string {
	return s
		.replace(/\\'/g, "'")
		.replace(/\\"/g, '"')
		.replace(/\\n/g, '\n')
		.replace(/&lt;/g, '<')
		.replace(/&gt;/g, '>')
		.replace(/&quot;/g, '"')
		.replace(/&apos;/g, "'")
		.replace(/&amp;/g, '&');
}

async function webMessages(locale: Locale): Promise<string[]> {
	const mod = (await import(pathToFileURL(join(WEB_LOCALES, `${locale}.ts`)).href)) as Record<string, Record<string, string>>;
	return Object.values(locale === 'en' ? mod.en : mod.messages);
}

function arbMessages(locale: Locale): string[] {
	const arb = JSON.parse(readFileSync(join(ARB_DIR, ARB_FILE[locale]), 'utf8')) as Record<string, unknown>;
	return Object.entries(arb)
		.filter(([key, value]) => !key.startsWith('@') && typeof value === 'string')
		.map(([, value]) => value as string);
}

function wearMessages(locale: Locale): string[] {
	const xml = readFileSync(join(WEAR_RES, WEAR_VALUES[locale], 'strings.xml'), 'utf8');
	return [...xml.matchAll(/<(string|item)\b[^>]*>([\s\S]*?)<\/\1>/g)].map((m) => unescapeAndroid(m[2]));
}

function appleWatchMessages(locale: Locale): string[] {
	const file = JSON.parse(readFileSync(XCSTRINGS, 'utf8')) as {
		strings: Record<string, { localizations?: Record<string, { stringUnit?: { value?: string } }> }>;
	};
	return Object.entries(file.strings).flatMap(([key, entry]) => {
		const value = entry.localizations?.[locale]?.stringUnit?.value;
		return value !== undefined ? [value] : locale === 'en' ? [key] : [];
	});
}

const catalogues = new Map<Locale, Record<'web' | 'phone' | 'wear' | 'apple-watch', Catalogue>>();
for (const locale of SUPPORTED_LOCALES) {
	catalogues.set(locale, {
		web: catalogue(await webMessages(locale), icuPattern),
		phone: catalogue(arbMessages(locale), icuPattern),
		wear: catalogue(wearMessages(locale), printfPattern),
		'apple-watch': catalogue(appleWatchMessages(locale), printfPattern),
	});
}

// ---------------------------------------------------------------------------
// Guides

const guides = new Map<string, Guide>();
for (const file of readdirSync(GUIDES_DIR).filter((f) => f.endsWith('.ts'))) {
	const mod = (await import(pathToFileURL(join(GUIDES_DIR, file)).href)) as {
		guide?: Guide;
	};
	if (mod.guide) guides.set(mod.guide.id, mod.guide);
}

/// Every guide's words in every locale: the English guide, then each translation.
const texts: { locale: Locale; id: string; sections: Guide['sections'] }[] = [];
for (const guide of guides.values()) texts.push({ locale: 'en', id: guide.id, sections: guide.sections });
for (const locale of SUPPORTED_LOCALES.filter((l) => l !== 'en')) {
	const dir = join(TRANSLATIONS_DIR, locale);
	if (!existsSync(dir)) continue;
	for (const file of readdirSync(dir)
		.filter((f) => f.endsWith('.ts'))
		.sort()) {
		const mod = (await import(pathToFileURL(join(dir, file)).href)) as {
			translation?: GuideTranslation;
		};
		if (mod.translation)
			texts.push({
				locale,
				id: mod.translation.id,
				sections: mod.translation.sections,
			});
	}
}

function blockStrings(block: Block): string[] {
	if (block.type === 'illustration') return [];
	return block.type === 'steps' || block.type === 'list' ? block.items : [block.text];
}

interface Quoted {
	locale: Locale;
	guide: string;
	where: string;
	label: string;
}

const quoted: Quoted[] = texts.flatMap(({ locale, id, sections }) =>
	sections.flatMap((s, si) =>
		s.blocks.flatMap((b, bi) =>
			blockStrings(b).flatMap((text) =>
				parseMarkup(text)
					.filter((t) => t.kind === 'strong')
					.map((t) => ({
						locale,
						guide: id,
						where: `section ${si + 1} block ${bi + 1}`,
						label: t.text,
					})),
			),
		),
	),
);

function found(q: { locale: Locale; label: string }): boolean {
	return Object.values(catalogues.get(q.locale)!).some((cat) => matches(q.label, cat));
}

const allowed = (q: Quoted) => NOT_IN_A_CATALOGUE.some((e) => e.guide === q.guide && e.labels[q.locale]?.includes(q.label));

// ---------------------------------------------------------------------------

test('the matcher reads placeholders, plurals and leading clauses', () => {
	const icu = catalogue(
		[
			'Pending requests ({n})',
			'GO at {when}',
			'Show all {n} upcoming',
			'{n, plural, one {# run} other {# runs}}',
			'Spectator view',
			'Tracking paused while you were away — your run kept timing.',
			'Search places...',
			'{a} of {b}',
			'項目を保存（{n}件）',
		],
		icuPattern,
	);
	for (const label of [
		'Pending requests',
		'GO at',
		'Show all 12 upcoming',
		'3 runs',
		'1 run',
		'Spectator view',
		'Tracking paused while you were away',
		'Search places…',
		'項目を保存',
	])
		assert.ok(matches(label, icu), label);
	for (const label of ['pending requests', 'Pending', 'Show all', 'Tracking paused', 'Spectator', 'Which of your clubs is this?'])
		assert.ok(!matches(label, icu), label);
	const printf = catalogue(['%1$s km to go', 'Late start', '%@ kilometres'], printfPattern);
	for (const label of ['5 km to go', 'Late start', '4.2 kilometres']) assert.ok(matches(label, printf), label);
});

test('every catalogue the guard reads is non-empty in every locale', () => {
	for (const [locale, cats] of catalogues)
		for (const [name, cat] of Object.entries(cats)) assert.ok(cat.exact.size > 0, `${locale} ${name} holds no strings`);
	assert.ok(
		quoted.some((q) => q.locale !== 'en'),
		'no translated guide quotes a label',
	);
});

test('every **label** a guide quotes is a label the app shows, in that locale', () => {
	const problems = quoted
		.filter((q) => !allowed(q) && !found(q))
		.map(
			(q) =>
				`${q.locale === 'en' ? 'guides' : `translations/${q.locale}`}/${q.guide} › ${q.where}: ` +
				`**${q.label}** is in no ${q.locale} catalogue`,
		);
	assert.deepEqual(
		problems,
		[],
		`Quote the label as the app renders it, or add it to NOT_IN_A_CATALOGUE with a reason:\n${problems.join('\n')}`,
	);
});

test('NOT_IN_A_CATALOGUE only shrinks: every entry is still quoted and still in no catalogue', () => {
	const problems: string[] = [];
	for (const entry of NOT_IN_A_CATALOGUE) {
		assert.ok(entry.reason.trim().length > 0, `${entry.guide}: an allowlist entry needs a reason`);
		if (!guides.has(entry.guide)) problems.push(`${entry.guide}: no such guide`);
		for (const locale of SUPPORTED_LOCALES) {
			for (const label of entry.labels[locale] ?? []) {
				const q = { locale, guide: entry.guide, label };
				if (!quoted.some((x) => x.locale === locale && x.guide === entry.guide && x.label === label))
					problems.push(`${locale}/${entry.guide}: **${label}** is no longer quoted; remove it`);
				else if (found(q)) problems.push(`${locale}/${entry.guide}: **${label}** is in a catalogue now; remove it`);
			}
		}
	}
	assert.deepEqual(problems, [], problems.join('\n'));
});

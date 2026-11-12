/**
 * An AI Coach answer shared into the athlete↔coach thread (issue #1215
 * Phase 3, migration 20271210001215).
 *
 * The server is authoritative on what is sent: `share_coach_message` copies
 * the picked paragraphs out of the athlete's own answer, by index, so the
 * card's AI label always sits on AI text. This module splits an answer the
 * same way the server does (to offer the paragraphs), and turns a card's text
 * into a few typed blocks for the clients to draw as text. It never produces
 * HTML: the text crosses from one user to another, so a renderer that read it
 * as markup would turn a self-XSS in a Coach answer into a stored one
 * (decisions § 110).
 *
 * Mirrored by `apps/mobile_android/lib/coach_share.dart`
 * (docs/architecture/parity_pairs.md).
 */

export type DmKind = 'text' | 'coach_share' | 'ai_assisted' | 'group_renamed';

/** Every `direct_messages.kind` the CHECK admits. */
export const DM_KINDS = ['text', 'coach_share', 'ai_assisted', 'group_renamed'] as const satisfies readonly DmKind[];

/** Must equal the 4000-character cap share_coach_message enforces. */
export const COACH_SHARE_MAX_CHARS = 4000;

/**
 * A row's `kind`, read at the boundary. Anything unknown is drawn as text.
 * `group_renamed` is the system line rename_group writes in a group, its body
 * the new title (migration 20271217000004).
 */
export function parseDmKind(raw: unknown): DmKind {
	return raw === 'coach_share' || raw === 'ai_assisted' || raw === 'group_renamed' ? raw : 'text';
}

const EDGE = /^[ \t\n\r]+|[ \t\n\r]+$/g;

/**
 * The paragraphs of an answer, as `private.coach_answer_paragraphs` splits
 * them: CRLF read as LF, split on a line holding only spaces or tabs, each
 * part trimmed of spaces, tabs and line breaks, empty parts dropped.
 */
export function coachAnswerParagraphs(content: string): string[] {
	return content
		.replace(/\r\n/g, '\n')
		.split(/\n[ \t]*\n/)
		.map((p) => p.replace(EDGE, ''))
		.filter((p) => p.length > 0);
}

/** The picked paragraphs, in answer order, as the card will hold them. */
export function coachShareExcerpt(paragraphs: readonly string[], picked: Iterable<number>): string {
	const idx = [...new Set(picked)]
		.filter((i) => Number.isInteger(i) && i >= 0 && i < paragraphs.length)
		.sort((a, b) => a - b);
	return idx.map((i) => paragraphs[i]).join('\n\n');
}

export type SharedSpanStyle = 'plain' | 'bold' | 'italic' | 'code';

export interface SharedSpan {
	text: string;
	style: SharedSpanStyle;
}

export type SharedBlock =
	| { type: 'paragraph'; spans: SharedSpan[] }
	| { type: 'heading'; spans: SharedSpan[] }
	| { type: 'bullet'; spans: SharedSpan[] }
	| { type: 'ordered'; marker: string; spans: SharedSpan[] };

const LINK = /^\[([^\]\n]+)\]\(([^)\s]*)\)/;

/**
 * Inline marks: `**bold**`, `*italic*` and `` `code` ``, not nested. A link
 * keeps its text and loses its target, so nothing in the card is clickable.
 * An unclosed mark is literal text.
 */
export function parseSharedInline(line: string): SharedSpan[] {
	const out: SharedSpan[] = [];
	let plain = '';
	const push = (text: string, style: SharedSpanStyle) => {
		if (style === 'plain') {
			plain += text;
			return;
		}
		if (plain) out.push({ text: plain, style: 'plain' });
		plain = '';
		out.push({ text, style });
	};
	let i = 0;
	while (i < line.length) {
		const rest = line.slice(i);
		if (rest.startsWith('`')) {
			const end = line.indexOf('`', i + 1);
			if (end > i + 1) {
				push(line.slice(i + 1, end), 'code');
				i = end + 1;
				continue;
			}
		} else if (rest.startsWith('**')) {
			const end = line.indexOf('**', i + 2);
			if (end > i + 2) {
				push(line.slice(i + 2, end), 'bold');
				i = end + 2;
				continue;
			}
		} else if (rest.startsWith('*') && rest.length > 1 && rest[1] !== ' ') {
			const end = line.indexOf('*', i + 1);
			if (end > i + 1 && line[end - 1] !== ' ') {
				push(line.slice(i + 1, end), 'italic');
				i = end + 1;
				continue;
			}
		} else if (rest.startsWith('[')) {
			const link = LINK.exec(rest);
			if (link) {
				push(link[1], 'plain');
				i += link[0].length;
				continue;
			}
		}
		push(line[i], 'plain');
		i += 1;
	}
	if (plain) out.push({ text: plain, style: 'plain' });
	return out;
}

const BULLET = /^[-*+][ \t]+(.*)$/;
const ORDERED = /^(\d{1,3})[.)][ \t]+(.*)$/;
const HEADING = /^#{1,6}[ \t]+(.*)$/;
const QUOTE = /^>[ \t]?(.*)$/;

/**
 * A card's text as blocks: list items, headings (drawn as bold lines), and
 * paragraphs whose single line breaks are kept. A quote marker is dropped,
 * since the whole card is already a quote.
 */
export function parseSharedMarkdown(text: string): SharedBlock[] {
	const blocks: SharedBlock[] = [];
	let para: string[] = [];
	const flush = () => {
		if (para.length === 0) return;
		blocks.push({ type: 'paragraph', spans: parseSharedInline(para.join('\n')) });
		para = [];
	};
	for (const raw of text.replace(/\r\n/g, '\n').split('\n')) {
		const quoted = QUOTE.exec(raw.trim());
		const line = (quoted ? quoted[1] : raw).trim();
		if (!line) {
			flush();
			continue;
		}
		const bullet = BULLET.exec(line);
		const ordered = ORDERED.exec(line);
		const heading = HEADING.exec(line);
		if (bullet) {
			flush();
			blocks.push({ type: 'bullet', spans: parseSharedInline(bullet[1]) });
		} else if (ordered) {
			flush();
			blocks.push({ type: 'ordered', marker: `${ordered[1]}.`, spans: parseSharedInline(ordered[2]) });
		} else if (heading) {
			flush();
			blocks.push({ type: 'heading', spans: parseSharedInline(heading[1]) });
		} else {
			para.push(line);
		}
	}
	flush();
	return blocks;
}

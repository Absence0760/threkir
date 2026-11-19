// Keeps the issues a pull request works on in step with it, from the PR
// body's `## Issues` section (see .github/pull_request_template.md).
//
//   Fixes #12          GitHub closes the issue on merge; nothing to do here.
//   Part of #34        The PR does some of the issue's checklist. The lines
//   - Half marathon    under it name the checkbox lines it completes.
//
// While the PR is open, each `Part of` issue carries the `in-flight` label and
// one comment from this workflow linking the PR, so a session picking work
// skips it. When the PR merges, the named boxes are ticked, the comment says
// which were and which were not found, and the label comes off unless another
// open PR is still working on the issue. Closed unmerged, only the label
// comes off.
//
// Run by .github/workflows/issue-progress.yml with the event payload at
// GITHUB_EVENT_PATH. The PR body is untrusted text: it is only parsed here,
// never interpolated into a shell or evaluated.

import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

export const LABEL = 'in-flight';
const LABEL_COLOR = 'FBCA04';
const MARKER = (/** @type {number} */ pr) => `<!-- issue-progress pr=${pr} -->`;

/**
 * @typedef {{ issue: number, items: string[] }} PartOf
 * @typedef {{ fixes: number[], parts: PartOf[] }} IssuesSection
 */

/** @param {string} s */
const norm = (s) => s.replace(/\s+/g, ' ').trim();

/**
 * Strip a list marker and an optional checkbox from a line: `- [x] Half` -> `Half`.
 * @param {string} line
 */
function itemText(line) {
	return norm(line.replace(/^\s*[-*]\s+(\[[ xX]\]\s+)?/, ''));
}

/**
 * The text outside HTML comments, as GitHub renders a PR body: each
 * `<!-- ... -->` is dropped, and an unclosed `<!--` hides everything after
 * it. Removing one comment can join the text around it into a new opener
 * (`<!<!---->--`), so it repeats until nothing changes, then cuts at any
 * opener left, rather than a single regex replace that can leave one behind.
 *
 * @param {string} body
 */
export function stripHtmlComments(body) {
	let text = body;
	for (;;) {
		let out = '';
		let i = 0;
		let open = text.indexOf('<!--');
		while (open !== -1) {
			const close = text.indexOf('-->', open + 4);
			if (close === -1) break;
			out += text.slice(i, open);
			i = close + 3;
			open = text.indexOf('<!--', i);
		}
		out += text.slice(i);
		if (out === text) break;
		text = out;
	}
	const left = text.indexOf('<!--');
	return left === -1 ? text : text.slice(0, left);
}

/**
 * The PR body's `## Issues` section: the issues it fixes, and the ones it
 * is part of with the checkbox lines it completes. HTML comments are ignored,
 * so the template's guidance never counts as a reference.
 *
 * @param {string | null | undefined} body
 * @returns {IssuesSection}
 */
export function parseIssuesSection(body) {
	/** @type {IssuesSection} */
	const out = { fixes: [], parts: [] };
	if (!body) return out;
	const text = stripHtmlComments(body);
	const lines = text.split(/\r?\n/);
	const start = lines.findIndex((l) => /^##\s+Issues\s*$/i.test(l.trim()));
	if (start === -1) return out;
	/** @type {PartOf | null} */
	let current = null;
	for (const line of lines.slice(start + 1)) {
		if (/^#{1,6}\s/.test(line.trim())) break;
		const fixes = /^\s*(?:fixes|closes|resolves)\s+#(\d+)\b/i.exec(line);
		if (fixes) {
			out.fixes.push(Number(fixes[1]));
			current = null;
			continue;
		}
		const part = /^\s*part of\s+#(\d+)\b/i.exec(line);
		if (part) {
			current = { issue: Number(part[1]), items: [] };
			out.parts.push(current);
			continue;
		}
		if (current && /^\s*[-*]\s+\S/.test(line)) {
			const item = itemText(line);
			if (item) current.items.push(item);
		}
	}
	return out;
}

/**
 * Tick each named checkbox in an issue body. A checkbox matches when its text,
 * whitespace-normalised, equals the item; one already ticked counts as ticked.
 * An item that matches more than one checkbox ticks none of them and is
 * reported as ambiguous: the issue has the same line under two headings (a
 * "10K: 2 laps" for each of three parks), and ticking the first would tick
 * the wrong one.
 *
 * @param {string} body
 * @param {string[]} items
 * @returns {{ body: string, ticked: string[], missing: string[], ambiguous: string[] }}
 */
export function tickItems(body, items) {
	const lines = body.split('\n');
	/** @type {string[]} */
	const ticked = [];
	/** @type {string[]} */
	const missing = [];
	/** @type {string[]} */
	const ambiguous = [];
	for (const item of items) {
		const want = norm(item);
		/** @type {number[]} */
		const hits = [];
		for (let i = 0; i < lines.length; i++) {
			const m = /^(\s*[-*]\s+)\[([ xX])\](\s+)(.*)$/.exec(lines[i]);
			if (m && norm(m[4]) === want) hits.push(i);
		}
		if (hits.length === 0) missing.push(item);
		else if (hits.length > 1) ambiguous.push(item);
		else {
			const i = hits[0];
			const m = /^(\s*[-*]\s+)\[([ xX])\](\s+)(.*)$/.exec(lines[i]);
			if (m) lines[i] = `${m[1]}[x]${m[3]}${m[4]}`;
			ticked.push(item);
		}
	}
	return { body: lines.join('\n'), ticked, missing, ambiguous };
}

/**
 * The workflow's one comment on an issue for a PR, by state.
 *
 * @param {{ pr: number, state: 'open' | 'merged' | 'closed', items: string[], ticked?: string[], missing?: string[], ambiguous?: string[] }} c
 */
export function commentBody(c) {
	const list = (/** @type {string[]} */ xs) => xs.map((x) => `- ${x}`).join('\n');
	const parts = [MARKER(c.pr)];
	if (c.state === 'open') {
		parts.push(`#${c.pr} is working on this issue${c.items.length ? ':' : '.'}`);
		if (c.items.length) parts.push(list(c.items));
	} else if (c.state === 'merged') {
		parts.push(`#${c.pr} merged.`);
		if (c.ticked?.length) parts.push(`Ticked:\n${list(c.ticked)}`);
		if (c.missing?.length) parts.push(`Not found in the checklist, so not ticked (check the wording):\n${list(c.missing)}`);
		if (c.ambiguous?.length) parts.push(`More than one checklist line reads exactly like this, so none was ticked (make the line unique, then tick it by hand):\n${list(c.ambiguous)}`);
		if (!c.items.length) parts.push('It named no checklist items, so nothing was ticked.');
	} else {
		parts.push(`#${c.pr} was closed without merging; nothing was ticked.`);
	}
	return parts.join('\n\n');
}

/**
 * @param {string} token
 * @param {string} repo
 */
function api(token, repo) {
	/**
	 * @param {string} method
	 * @param {string} path
	 * @param {unknown} [body]
	 */
	return async (method, path, body) => {
		const res = await fetch(`https://api.github.com/repos/${repo}${path}`, {
			method,
			headers: {
				Authorization: `Bearer ${token}`,
				Accept: 'application/vnd.github+json',
				'X-GitHub-Api-Version': '2022-11-28',
				...(body ? { 'Content-Type': 'application/json' } : {}),
			},
			body: body ? JSON.stringify(body) : undefined,
		});
		if (res.status === 404 && method === 'DELETE') return null;
		if (!res.ok) throw new Error(`${method} ${path} -> HTTP ${res.status}: ${(await res.text()).slice(0, 300)}`);
		return res.status === 204 ? null : res.json();
	};
}

/**
 * @param {ReturnType<typeof api>} call
 * @param {number} issue
 * @param {number} pr
 * @param {string} body
 */
async function upsertComment(call, issue, pr, body) {
	const comments = /** @type {Array<{ id: number, body: string }>} */ (
		await call('GET', `/issues/${issue}/comments?per_page=100`)
	);
	const mine = comments.find((c) => c.body.startsWith(MARKER(pr)));
	if (mine) await call('PATCH', `/issues/comments/${mine.id}`, { body });
	else await call('POST', `/issues/${issue}/comments`, { body });
}

/**
 * Whether another open PR still names the issue as `Part of`.
 *
 * @param {ReturnType<typeof api>} call
 * @param {number} issue
 * @param {number} pr
 */
async function stillInFlight(call, issue, pr) {
	const open = /** @type {Array<{ number: number, body: string | null }>} */ (
		await call('GET', '/pulls?state=open&per_page=100')
	);
	return open.some((p) => p.number !== pr && parseIssuesSection(p.body).parts.some((x) => x.issue === issue));
}

/** @param {Record<string, any>} event */
export async function run(event, { token = process.env.GITHUB_TOKEN ?? '', repo = process.env.GITHUB_REPOSITORY ?? '' } = {}) {
	const pr = event.pull_request;
	if (!pr) return;
	const { parts } = parseIssuesSection(pr.body);
	if (parts.length === 0) return;
	const call = api(token, repo);

	if (event.action !== 'closed') {
		await call('POST', '/labels', { name: LABEL, color: LABEL_COLOR }).catch(() => {});
		for (const { issue, items } of parts) {
			await call('POST', `/issues/${issue}/labels`, { labels: [LABEL] });
			await upsertComment(call, issue, pr.number, commentBody({ pr: pr.number, state: 'open', items }));
		}
		return;
	}

	for (const { issue, items } of parts) {
		if (pr.merged) {
			const current = /** @type {{ body: string | null }} */ (await call('GET', `/issues/${issue}`));
			const result = tickItems(current.body ?? '', items);
			if (result.ticked.length) await call('PATCH', `/issues/${issue}`, { body: result.body });
			await upsertComment(call, issue, pr.number, commentBody({ pr: pr.number, state: 'merged', items, ...result }));
		} else {
			await upsertComment(call, issue, pr.number, commentBody({ pr: pr.number, state: 'closed', items }));
		}
		if (!(await stillInFlight(call, issue, pr.number))) {
			await call('DELETE', `/issues/${issue}/labels/${LABEL}`);
		}
	}
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
	const path = process.env.GITHUB_EVENT_PATH;
	if (!path) throw new Error('GITHUB_EVENT_PATH is not set');
	await run(JSON.parse(fs.readFileSync(path, 'utf8')));
}

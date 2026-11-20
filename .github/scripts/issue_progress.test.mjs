// Run: node --test .github/scripts/issue_progress.test.mjs

import assert from 'node:assert/strict';
import test from 'node:test';

import { LABEL, commentBody, parseIssuesSection, positiveId, run, stripHtmlComments, tickItems } from './issue_progress.mjs';

const BODY = `## Summary

Builds things.

## Issues

<!-- Part of #999 is template guidance and never counts. -->
Fixes #12
Part of #34
- [x] Export a run: CSV and GPX
- Import   from a file
Part of #56

## Changes

- Part of #78 is not in the Issues section
`;

test('parseIssuesSection reads Fixes and Part of, with the items under each, and ignores comments and other sections', () => {
	assert.deepEqual(parseIssuesSection(BODY), {
		fixes: [12],
		parts: [
			{ issue: 34, items: ['Export a run: CSV and GPX', 'Import from a file'] },
			{ issue: 56, items: [] },
		],
	});
});

test('parseIssuesSection finds nothing in a body without the section', () => {
	assert.deepEqual(parseIssuesSection('Part of #1'), { fixes: [], parts: [] });
	assert.deepEqual(parseIssuesSection(null), { fixes: [], parts: [] });
});

test('tickItems ticks matching checkboxes, keeps ticked ones, and reports the missing', () => {
	const issue = '- [ ] Export a run:  CSV and GPX\n  * [x] Import from a file\n- [ ] 5K\n';
	const r = tickItems(issue, ['Export a run: CSV and GPX', 'Import from a file', '10K']);
	assert.equal(r.body, '- [x] Export a run:  CSV and GPX\n  * [x] Import from a file\n- [ ] 5K\n');
	assert.deepEqual(r.ticked, ['Export a run: CSV and GPX', 'Import from a file']);
	assert.deepEqual(r.missing, ['10K']);
});

test('tickItems ticks nothing for a line the checklist holds twice, and says so', () => {
	const issue = '### Park A\n- [ ] 10K: 2 laps\n### Park B\n- [ ] 10K: 2 laps\n- [ ] Park B 5K\n';
	const r = tickItems(issue, ['10K: 2 laps', 'Park B 5K']);
	assert.equal(r.body, '### Park A\n- [ ] 10K: 2 laps\n### Park B\n- [ ] 10K: 2 laps\n- [x] Park B 5K\n');
	assert.deepEqual(r.ambiguous, ['10K: 2 laps']);
	assert.deepEqual(r.missing, []);
	assert.match(commentBody({ pr: 7, state: 'merged', items: ['10K: 2 laps'], ...r }), /More than one checklist line/);
});

test('tickItems matches whole checkbox text, not a prefix', () => {
	assert.deepEqual(tickItems('- [ ] 5K plan export\n', ['5K']).missing, ['5K']);
});

test('commentBody carries the marker and says what happened', () => {
	assert.match(commentBody({ pr: 7, state: 'open', items: ['A'] }), /^<!-- issue-progress pr=7 -->\n\n#7 is working on this issue:\n\n- A$/);
	const merged = commentBody({ pr: 7, state: 'merged', items: ['A', 'B'], ticked: ['A'], missing: ['B'] });
	assert.match(merged, /Ticked:\n- A/);
	assert.match(merged, /Not found in the checklist[^\n]*\n- B/);
	assert.match(commentBody({ pr: 7, state: 'closed', items: [] }), /closed without merging/);
});

/**
 * A stub of the REST calls run() makes, recording each one.
 *
 * @param {{ issueBody?: string, openPrs?: Array<{ number: number, body: string }>, comments?: Array<{ id: number, body: string }> }} state
 */
function stubGitHub(state) {
	/** @type {Array<{ method: string, path: string, body: any }>} */
	const calls = [];
	const original = globalThis.fetch;
	globalThis.fetch = /** @type {typeof fetch} */ (
		async (/** @type {any} */ url, /** @type {any} */ init) => {
			const path = String(url).replace('https://api.github.com/repos/o/r', '');
			const body = init?.body ? JSON.parse(init.body) : undefined;
			calls.push({ method: init?.method ?? 'GET', path, body });
			/** @type {unknown} */
			let json = {};
			if (path.endsWith('/comments?per_page=100')) json = state.comments ?? [];
			else if (path.startsWith('/pulls?')) json = state.openPrs ?? [];
			else if (/^\/issues\/\d+$/.test(path) && (init?.method ?? 'GET') === 'GET') json = { body: state.issueBody ?? '' };
			return new Response(JSON.stringify(json), { status: 200 });
		}
	);
	return { calls, restore: () => (globalThis.fetch = original) };
}

const opts = { token: 't', repo: 'o/r' };
const prBody = '## Issues\n\nPart of #34\n- Half\n';

test('run on an opened PR labels the issue in-flight and comments once', async () => {
	const gh = stubGitHub({});
	try {
		await run({ action: 'opened', pull_request: { number: 7, body: prBody, merged: false } }, opts);
	} finally {
		gh.restore();
	}
	assert.deepEqual(
		gh.calls.map((c) => `${c.method} ${c.path}`),
		['POST /labels', 'POST /issues/34/labels', 'GET /issues/34/comments?per_page=100', 'POST /issues/34/comments'],
	);
	assert.deepEqual(gh.calls[1].body, { labels: [LABEL] });
});

test('run on an edited PR updates its own comment rather than adding another', async () => {
	const gh = stubGitHub({ comments: [{ id: 5, body: '<!-- issue-progress pr=7 -->\n\nold' }] });
	try {
		await run({ action: 'edited', pull_request: { number: 7, body: prBody, merged: false } }, opts);
	} finally {
		gh.restore();
	}
	assert.ok(gh.calls.some((c) => c.method === 'PATCH' && c.path === '/issues/comments/5'));
	assert.ok(!gh.calls.some((c) => c.method === 'POST' && c.path === '/issues/34/comments'));
});

test('run on a merged PR ticks the boxes and removes the label when no other PR is working on it', async () => {
	const gh = stubGitHub({ issueBody: '- [ ] Half\n- [ ] Full\n', openPrs: [{ number: 8, body: 'no section' }] });
	try {
		await run({ action: 'closed', pull_request: { number: 7, body: prBody, merged: true } }, opts);
	} finally {
		gh.restore();
	}
	const patch = gh.calls.find((c) => c.method === 'PATCH' && c.path === '/issues/34');
	assert.equal(patch?.body.body, '- [x] Half\n- [ ] Full\n');
	assert.ok(gh.calls.some((c) => c.method === 'DELETE' && c.path === `/issues/34/labels/${LABEL}`));
});

test('run keeps the label while another open PR is still part of the issue, and ticks nothing when closed unmerged', async () => {
	const gh = stubGitHub({ issueBody: '- [ ] Half\n', openPrs: [{ number: 9, body: '## Issues\nPart of #34\n' }] });
	try {
		await run({ action: 'closed', pull_request: { number: 7, body: prBody, merged: false } }, opts);
	} finally {
		gh.restore();
	}
	assert.ok(!gh.calls.some((c) => c.method === 'PATCH' && c.path === '/issues/34'));
	assert.ok(!gh.calls.some((c) => c.method === 'DELETE'));
});

test('run does nothing for a PR with no Part of issues', async () => {
	const gh = stubGitHub({});
	try {
		await run({ action: 'opened', pull_request: { number: 7, body: '## Issues\nFixes #3\n', merged: false } }, opts);
	} finally {
		gh.restore();
	}
	assert.equal(gh.calls.length, 0);
});

test('stripHtmlComments drops every comment, overlapping or unclosed, and leaves no opener behind', () => {
	assert.equal(stripHtmlComments('a<!-- x -->b<!-- y -->c'), 'abc');
	assert.equal(stripHtmlComments('a<!--<!-- x -->-->b'), 'a-->b');
	// Removing the inner comment joins `<!` and `--` into a new opener.
	assert.equal(stripHtmlComments('a<!<!---->-- Part of #1 -->b'), 'ab');
	assert.equal(stripHtmlComments('keep <!-- never closed\nPart of #2'), 'keep ');
	assert.equal(stripHtmlComments('no comments'), 'no comments');
	for (const s of ['<!<!---->--', '<!--<!---->--', 'x<!<!<!------>-->-->y']) {
		assert.ok(!stripHtmlComments(s).includes('<!--'), s);
	}
});

test('parseIssuesSection ignores a reference hidden in an unclosed comment', () => {
	assert.deepEqual(parseIssuesSection('## Issues\nPart of #3\n<!-- Part of #4'), { fixes: [], parts: [{ issue: 3, items: [] }] });
});

test('positiveId takes a positive whole number and refuses anything else', () => {
	assert.equal(positiveId(34, 'x'), 34);
	for (const bad of [0, -1, 1.5, Number.NaN, '34', null, undefined, 2 ** 60]) {
		assert.throws(() => positiveId(bad, 'issue number'), /issue number must be a positive whole number/);
	}
});

test('run refuses a PR number or repository that is not well formed, before calling GitHub', async () => {
	const gh = stubGitHub({});
	try {
		await assert.rejects(run({ action: 'opened', pull_request: { number: '7', body: prBody } }, opts), /pull_request\.number/);
		await assert.rejects(run({ action: 'opened', pull_request: { number: 7, body: prBody } }, { token: 't', repo: 'o/r/../x' }), /GITHUB_REPOSITORY/);
	} finally {
		gh.restore();
	}
	assert.equal(gh.calls.length, 0);
});

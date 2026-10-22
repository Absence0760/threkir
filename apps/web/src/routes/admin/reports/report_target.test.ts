import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { en } from '#lib/i18n/locales/en.ts';
import type { ReportTargetKind } from '#lib/types.ts';
import { REPORT_TARGETS, reportTargetHref, reportTargetLabelKey } from './report_target.ts';

const PAGE = 'p-1';

// One row per `reports.target_kind` value: the label a moderator reads and
// the page the queue link opens, given the `page_id` fetch_pending_reports
// resolved (the item itself, or the run / club / route carrying it).
const EXPECTED: Record<ReportTargetKind, { label: string; href: string | null }> = {
	user: { label: 'User', href: `/u/${PAGE}` },
	club: { label: 'Club', href: `/clubs/${PAGE}` },
	route: { label: 'Route', href: `/routes/${PAGE}` },
	run: { label: 'Run', href: `/runs/${PAGE}` },
	comment: { label: 'Comment', href: `/runs/${PAGE}` },
	club_post: { label: 'Club post', href: `/clubs/${PAGE}` },
	route_review: { label: 'Route review', href: `/routes/${PAGE}` },
	direct_message: { label: 'Direct message', href: null },
};

// EXPECTED is a Record over the union, which check_constraint_unions.mjs
// holds to the CHECK, so a kind added there fails to compile here too.
test('the spec table covers exactly the kinds this test expects', () => {
	assert.deepEqual(Object.keys(REPORT_TARGETS).sort(), Object.keys(EXPECTED).sort());
});

for (const [kind, want] of Object.entries(EXPECTED) as [ReportTargetKind, (typeof EXPECTED)[ReportTargetKind]][]) {
	test(`${kind}: label and link`, () => {
		const key = reportTargetLabelKey(kind);
		assert.ok(key);
		assert.equal(en[key], want.label);
		assert.equal(reportTargetHref(kind, PAGE), want.href);
	});
}

test('distinct kinds get distinct labels', () => {
	const labels = Object.keys(REPORT_TARGETS).map((k) => reportTargetLabelKey(k as ReportTargetKind));
	assert.equal(new Set(labels).size, labels.length);
});

test('no page id means no link, for every kind', () => {
	for (const kind of Object.keys(REPORT_TARGETS) as ReportTargetKind[]) {
		assert.equal(reportTargetHref(kind, null), null, kind);
	}
});

test('a kind this build does not know gets no label key and no link', () => {
	const unknown = 'future_kind' as ReportTargetKind;
	assert.equal(reportTargetLabelKey(unknown), null);
	assert.equal(reportTargetHref(unknown, PAGE), null);
});

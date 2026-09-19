// Source-level guard: no half of a registered TS<->Dart parity pair asks a
// question only one of the two runtimes can answer.
//
// `localeCompare` is an ICU collation. Dart ships no collator at all -- its
// only ordering primitive is `String.compareTo`, UTF-16 code-unit order -- so a
// collation inside a pair half is a divergence by construction, not a risk that
// might be realised. Measured over the 145,672 Unicode letters as
// single-character names, the two orderings disagree about 31.75 % of all pairs
// (decisions 1337).
//
// The criterion this enforces is the one four rounds each re-derived from
// scratch (1276, 1334/1337, 1383, 1400) and none of them wrote down anywhere a
// tool could read: FOLD where a Dart twin exists, because that runtime ships no
// collator and the two lists must agree; COLLATE where the surface is web-only,
// because a collation gives each reader their own correct order and a fold
// gives everyone the English one. The second half needs no guard -- it permits
// rather than requires -- and it stays permitted here automatically, since a
// web-only module is not in the registry. The four surfaces 1400 examined
// (`social/search_ranking.ts`, `social/dm_recipients.ts`, `core/data.ts`'s
// suggested-people sort and the `/coaching` roster) are exactly those.
//
// The pair list is READ from `.claude/agents/shared-library-syncer.md`, the
// registry the syncer agent itself works from, so registering a new pair puts
// it under this guard the same day rather than the day someone remembers.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { existsSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { SYNCER_DOC, parseSyncerRows } from '../../../../../scripts/check_parity_pair_registry.mjs';
import { stripComments } from '../core/strip_comments';

const REPO_ROOT = resolve('../..');

/// A collation, however it is spelled. `Intl.Collator` is the same instrument
/// under another name, and the banned reason is what it ASKS, not the call it
/// is written as.
const COLLATION = /\.localeCompare\s*\(|new\s+Intl\.Collator\s*\(/;

function pairHalves(): Map<string, string> {
	const { rows, errors } = parseSyncerRows(readFileSync(SYNCER_DOC, 'utf-8'));
	assert.deepEqual(errors, [], 'the syncer registry did not parse');
	return new Map([...rows].map(([name, row]) => [name, row.web]));
}

test('the guard reads a registry that is actually there', () => {
	// A guard whose source has moved reports nothing at all, which reads as a
	// clean sweep. Anchor on the registry's size and on a member whose web half
	// this tree owns.
	const halves = pairHalves();
	assert.ok(halves.size > 100, `only ${halves.size} pairs parsed — has the registry moved?`);
	assert.equal(halves.get('catalogue_browse'), 'apps/web/src/lib/segments/catalogue_browse.ts');
	for (const [name, web] of halves) {
		assert.ok(existsSync(join(REPO_ROOT, web)), `${name}'s web half is not on disk: ${web}`);
	}
});

test('no registered parity-pair half orders with a collation', () => {
	const offenders: string[] = [];
	for (const [name, web] of pairHalves()) {
		if (COLLATION.test(stripComments(readFileSync(join(REPO_ROOT, web), 'utf-8')))) {
			offenders.push(`  ${web}  (pair ${name})`);
		}
	}
	assert.deepEqual(
		offenders,
		[],
		'Order a pair half with compareFoldedNames from $lib/segments/catalogue_browse, ' +
			'never a collation — Dart has no collator, so the phone cannot reproduce the ' +
			'answer at all and the two platforms then order one list two ways ' +
			'(decisions 1337, 1383, 1400):\n' +
			offenders.join('\n'),
	);
});

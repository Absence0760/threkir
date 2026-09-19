import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { check, parseTagMap, parseTable, inspectWorkflow, readInputs } from './check_release_table.mjs';

/**
 * The guard's subject is a doc that describes workflows, so every case here
 * builds both halves in memory. The live tree is exercised once at the end —
 * a guard that only ever sees its own fixtures is one nothing proves fires on
 * the repo it ships in.
 */

const TAG_BLOCK = `
mobile_ios@1.2.3       → .github/workflows/release-ios.yml
web@1.2.3              → .github/workflows/release-web.yml
`;

const TABLE = (/** @type {string} */ iosAttaches, /** @type {string} */ webAttaches = '`.zip`') => `
| Release tag | Runs | Signs | Publishes to | Attaches back to the Release |
|---|---|---|---|---|
| \`mobile_ios@*\` | macos-latest | *unsigned today* | — | ${iosAttaches} |
| \`web@*\` | ubuntu-latest | — | AWS | ${webAttaches} |
`;

const IOS_NO_ATTACH = `
jobs:
  build:
    runs-on: macos-latest
    steps:
      - run: flutter build ipa --no-codesign
      # - uses: softprops/action-gh-release@abc
      #   with:
      #     files: apps/mobile_ios/build/ios/ipa/*.ipa
`;

const WEB_ATTACH = `
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: softprops/action-gh-release@abc
        with:
          files: web-build.zip
          fail_on_unmatched_files: true
`;

const docOf = (/** @type {string} */ table) => `# Releasing\n\`\`\`${TAG_BLOCK}\`\`\`\n${table}`;
const wf = (/** @type {Record<string, string>} */ map) => (/** @type {string} */ file) => map[file] ?? null;

const GOOD = {
	doc: docOf(TABLE('— (build smoke-check only)')),
	workflowOf: wf({ '.github/workflows/release-ios.yml': IOS_NO_ATTACH, '.github/workflows/release-web.yml': WEB_ATTACH }),
};

test('a table that matches its workflows passes', () => {
	const { problems } = check(GOOD);
	assert.deepEqual(problems, []);
});

test('the § 1673 bug: a row promising an artifact the workflow cannot produce fails', () => {
	const { problems } = check({ ...GOOD, doc: docOf(TABLE('`.ipa`')) });
	assert.equal(problems.length, 1);
	assert.match(problems[0], /promises the Release carries `\.ipa`/);
	assert.match(problems[0], /no live `softprops\/action-gh-release` step/);
});

test('a commented-out upload step is not read as a live one', () => {
	// The whole point of the § 1673 shape: release-ios.yml's upload block exists,
	// commented, awaiting signing. Counting it live would pass the broken row.
	const wfInfo = inspectWorkflow(IOS_NO_ATTACH);
	assert.equal(wfInfo.attaches, false);
});

test('a row understating what a release publishes fails too', () => {
	const { problems } = check({ ...GOOD, doc: docOf(TABLE('— (build smoke-check only)', '—')) });
	assert.equal(problems.length, 1);
	assert.match(problems[0], /says nothing is attached, but .* has a live upload step/);
});

test('an artifact extension that disagrees with the upload glob fails', () => {
	const { problems } = check({ ...GOOD, doc: docOf(TABLE('— (build smoke-check only)', '`.aab`')) });
	assert.equal(problems.length, 1);
	assert.match(problems[0], /uploads `web-build\.zip`, which is not a \.aab/);
});

test('a runner the table states wrongly fails', () => {
	const doc = docOf(TABLE('— (build smoke-check only)').replace('| `mobile_ios@*` | macos-latest', '| `mobile_ios@*` | ubuntu-latest'));
	const { problems } = check({ ...GOOD, doc });
	assert.equal(problems.length, 1);
	assert.match(problems[0], /runs on `ubuntu-latest` where .* declares `runs-on: macos-latest`/);
});

test('an upload glob without fail_on_unmatched_files fails, because its failure is silent', () => {
	const weak = WEB_ATTACH.replace('          fail_on_unmatched_files: true\n', '');
	const { problems } = check({ ...GOOD, workflowOf: wf({ '.github/workflows/release-ios.yml': IOS_NO_ATTACH, '.github/workflows/release-web.yml': weak }) });
	assert.equal(problems.length, 1);
	assert.match(problems[0], /without `fail_on_unmatched_files: true`/);
});

test('a table row with no workflow in the tag list fails', () => {
	// Appended INSIDE the table — a row after the blank line that ends it is not
	// a row, which is the parser behaving correctly rather than a case to assert.
	const doc = GOOD.doc.replace(
		'| `web@*` | ubuntu-latest | — | AWS | `.zip` |',
		'| `web@*` | ubuntu-latest | — | AWS | `.zip` |\n| `ghost@*` | ubuntu-latest | — | — | — |',
	);
	const { problems } = check({ ...GOOD, doc });
	assert.ok(problems.some((p) => /`ghost@\*` row that the tag-to-workflow list above it does not name/.test(p)));
});

test('a workflow in the tag list with no table row fails — the other direction', () => {
	const doc = docOf(TABLE('— (build smoke-check only)')).replace(/^\| `web@\*`.*$/m, '');
	const { problems } = check({ ...GOOD, doc });
	assert.ok(problems.some((p) => /release-web\.yml is listed for `web@\*` but has no row/.test(p)));
});

test('a mapped workflow that does not exist fails rather than being skipped', () => {
	const { problems } = check({ ...GOOD, workflowOf: wf({ '.github/workflows/release-web.yml': WEB_ATTACH }) });
	assert.ok(problems.some((p) => /release-ios\.yml, which does not exist/.test(p)));
});

test('a parser that matches nothing is a hard error, not a pass', () => {
	const { problems } = check({ doc: '# Releasing\n\nno table, no list.\n', workflowOf: () => null });
	assert.equal(problems.length, 2);
	assert.ok(problems.every((p) => /parsed to zero/.test(p)));
});

test('the parsers read the shapes the live doc actually uses', () => {
	const { doc } = readInputs();
	const tags = parseTagMap(doc);
	const table = parseTable(doc);
	assert.ok(tags.size >= 8, `tag map parsed ${tags.size} entries from the live doc`);
	assert.ok(table.size >= 8, `release table parsed ${table.size} rows from the live doc`);
	// Every row must resolve, or the guard is silently checking a subset.
	for (const app of table.keys()) assert.ok(tags.has(app), `no workflow mapped for ${app}`);
});

test('the live tree passes its own guard', () => {
	const { problems } = check(readInputs());
	assert.deepEqual(problems, [], problems.join('\n'));
});

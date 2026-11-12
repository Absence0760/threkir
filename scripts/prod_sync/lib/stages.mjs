// The production sync's plumbing (issue #1349, decisions § 2429): one stage
// per concern, each a SQL body whose ONE result set says what it did. A stage
// runs in its own transaction, committed, or rolled back on a dry run, and its
// rows become a table in the job's step summary. Pure: ../run.mjs owns psql
// and the files.
//
// Adding a concern is adding a stage to STAGES in ../run.mjs. A stage is
// either one SQL body (`sql`), or a `run(ctx)` for one that needs more than
// one transaction or the Supabase CLI (issue #1350's cron URLs, Edge Function
// env and one-off tasks, decisions § 2430). A `run` stage reports a table and,
// when it failed after doing part of its work, why.

/**
 * @typedef {{ header: string[], rows: string[][] }} Table
 * @typedef {{ ok: boolean, stdout: string, stderr: string }} CommandResult
 * @typedef {{
 *   dryRun: boolean,
 *   runSql: (script: string) => CommandResult,
 *   exec: (command: string, args: string[]) => CommandResult,
 *   env: Record<string, string | undefined>,
 * }} StageContext
 * @typedef {{ table: Table, failed?: string }} StageResult
 * @typedef {{
 *   id: string,
 *   title: string,
 *   note?: string,
 *   sql?: string,
 *   run?: (ctx: StageContext) => StageResult,
 * }} Stage
 */

/** Each stage's transaction waits this long for a lock before it fails. */
export const LOCK_TIMEOUT = '5s';
/** And may run this long in all. */
export const STATEMENT_TIMEOUT = '5min';

/**
 * A stage body wrapped in its transaction.
 *
 * @param {string} sql
 * @param {{ dryRun: boolean }} opts
 */
export function stageScript(sql, { dryRun }) {
	return (
		'\\set ON_ERROR_STOP on\n' +
		'begin;\n' +
		`set local lock_timeout = '${LOCK_TIMEOUT}';\n` +
		`set local statement_timeout = '${STATEMENT_TIMEOUT}';\n` +
		sql +
		(sql.endsWith('\n') ? '' : '\n') +
		(dryRun ? 'rollback;\n' : 'commit;\n')
	);
}

/**
 * psql's `--csv` output: one header line, then rows, RFC 4180 quoting.
 *
 * @param {string} text
 * @returns {Table}
 */
export function parseCsv(text) {
	/** @type {string[][]} */
	const records = [];
	/** @type {string[]} */
	let record = [];
	let field = '';
	let quoted = false;
	let any = false;
	for (let i = 0; i < text.length; i++) {
		const ch = text[i];
		if (quoted) {
			if (ch === '"' && text[i + 1] === '"') {
				field += '"';
				i++;
			} else if (ch === '"') quoted = false;
			else field += ch;
			continue;
		}
		if (ch === '"') {
			quoted = true;
			any = true;
		} else if (ch === ',') {
			record.push(field);
			field = '';
			any = true;
		} else if (ch === '\n' || ch === '\r') {
			if (ch === '\r' && text[i + 1] === '\n') i++;
			if (any || field !== '') record.push(field);
			if (record.length > 0) records.push(record);
			record = [];
			field = '';
			any = false;
		} else {
			field += ch;
			any = true;
		}
	}
	if (quoted) throw new Error('unterminated quoted field in psql output');
	if (any || field !== '') record.push(field);
	if (record.length > 0) records.push(record);
	if (records.length === 0) return { header: [], rows: [] };
	const [header, ...rows] = records;
	for (const row of rows) {
		if (row.length !== header.length) {
			throw new Error(`psql output row has ${row.length} fields, the header ${header.length}`);
		}
	}
	return { header, rows };
}

/** @param {string} cell */
const mdCell = (cell) => (cell === '' ? ' ' : cell.replace(/\\/g, '\\\\').replace(/\|/g, '\\|').replace(/\n/g, ' '));

/** @param {Table} table */
export function markdownTable({ header, rows }) {
	if (header.length === 0) return '_No rows._\n';
	return [
		`| ${header.map(mdCell).join(' | ')} |`,
		`| ${header.map(() => '---').join(' | ')} |`,
		...rows.map((r) => `| ${r.map(mdCell).join(' | ')} |`),
	]
		.join('\n')
		.concat('\n');
}

/**
 * How many rows carry each `action`, in first-seen order, or null when the
 * stage's rows have no `action` column.
 *
 * @param {Table} table
 */
export function actionCounts({ header, rows }) {
	const i = header.indexOf('action');
	if (i < 0) return null;
	/** @type {Map<string, number>} */
	const counts = new Map();
	for (const row of rows) counts.set(row[i], (counts.get(row[i]) ?? 0) + 1);
	return [...counts].map(([action, n]) => `${n} ${action}`).join(', ') || 'no rows';
}

/**
 * The step-summary section for one stage that ran.
 *
 * @param {Stage} stage
 * @param {Table} table
 * @param {{ dryRun: boolean }} opts
 */
export function stageSummary(stage, table, { dryRun }) {
	const counts = actionCounts(table);
	return (
		`### ${stage.title}${dryRun ? ' (dry run, rolled back)' : ''}\n\n` +
		(stage.note ? `${stage.note}\n\n` : '') +
		(counts ? `${counts}.\n\n` : '') +
		markdownTable(table) +
		'\n'
	);
}

/**
 * The step-summary section for a stage that failed. The error is psql's
 * stderr, which names no credential: the connection string never reaches it.
 *
 * A `run` stage commits per transaction, so its failure says only "failed"
 * and the table above it says what was done.
 *
 * @param {Stage} stage
 * @param {string} error
 */
export function failureSummary(stage, error) {
	return `### ${stage.title}: ${stage.run ? 'failed' : 'failed, rolled back'}\n\n\`\`\`\n${error.trim().slice(0, 4000)}\n\`\`\`\n\n`;
}

/** @type {StageContext['exec']} */
const noExec = (command) => ({ ok: false, stdout: '', stderr: `${command} is not available to this run` });

/**
 * Runs each stage in order and stops at the first failure.
 *
 * @param {Stage[]} stages
 * @param {{
 *   dryRun: boolean,
 *   runSql: StageContext['runSql'],
 *   write: (markdown: string) => void,
 *   exec?: StageContext['exec'],
 *   env?: StageContext['env'],
 * }} opts
 * @returns {boolean} whether every stage succeeded
 */
export function runStages(stages, { dryRun, runSql, write, exec = noExec, env = {} }) {
	write(`## Sync production state${dryRun ? ' (dry run)' : ''}\n\n`);
	for (const stage of stages) {
		if (stage.run) {
			/** @type {StageResult} */
			let result;
			try {
				result = stage.run({ dryRun, runSql, exec, env });
			} catch (err) {
				write(failureSummary(stage, err instanceof Error ? err.message : String(err)));
				return false;
			}
			write(stageSummary(stage, result.table, { dryRun }));
			if (result.failed !== undefined) {
				write(failureSummary(stage, result.failed));
				return false;
			}
			continue;
		}
		const result = runSql(stageScript(stage.sql ?? '', { dryRun }));
		if (!result.ok) {
			write(failureSummary(stage, result.stderr));
			return false;
		}
		write(stageSummary(stage, parseCsv(result.stdout), { dryRun }));
	}
	return true;
}

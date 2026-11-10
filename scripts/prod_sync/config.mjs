// Production config as code (issue #1350, decisions § 2430): reads
// apps/backend/ops/prod_config.json and the repo facts it is checked against,
// and builds the sync stages from it. The rules themselves are pure, in
// ./lib/prod_config.mjs.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
	checkAgainstRepo,
	checkTasks,
	cronFunctionsFromMigrations,
	flagNamesFromMigrations,
	functionEnvReads,
	parseProdConfig,
	webFlagsFrom,
} from './lib/prod_config.mjs';
import { cronUrlsStage, featureFlagsStage, functionEnvStage, opsTasksStage, webEnvStage } from './lib/config_stages.mjs';

export const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

/** @param {string} root */
export function paths(root = REPO) {
	return {
		config: path.join(root, 'apps', 'backend', 'ops', 'prod_config.json'),
		tasks: path.join(root, 'apps', 'backend', 'ops', 'tasks'),
		migrations: path.join(root, 'apps', 'backend', 'supabase', 'migrations'),
		functions: path.join(root, 'apps', 'backend', 'supabase', 'functions'),
		webLib: path.join(root, 'apps', 'web', 'src', 'lib'),
		releaseWeb: path.join(root, '.github', 'workflows', 'release-web.yml'),
	};
}

/**
 * @param {string} dir
 * @param {(name: string) => boolean} keep
 * @returns {string[]}
 */
function walk(dir, keep) {
	/** @type {string[]} */
	const out = [];
	for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
		const p = path.join(dir, e.name);
		if (e.isDirectory()) {
			if (e.name !== 'node_modules') out.push(...walk(p, keep));
		} else if (keep(e.name)) {
			out.push(p);
		}
	}
	return out;
}

/** @param {string} p */
const read = (p) => fs.readFileSync(p, 'utf8');

/** @param {string} root */
export function readTasks(root = REPO) {
	const dir = paths(root).tasks;
	if (!fs.existsSync(dir)) return [];
	return fs
		.readdirSync(dir)
		.filter((f) => fs.statSync(path.join(dir, f)).isFile())
		.sort()
		.map((file) => ({ file, body: read(path.join(dir, file)) }));
}

/**
 * Parses the committed config and checks it against the repo. Throws
 * nothing; the caller decides what a problem stops.
 *
 * @param {string} root
 */
export function checkProdConfig(root = REPO) {
	const p = paths(root);
	/** @type {string[]} */
	const problems = [];
	let json;
	try {
		json = JSON.parse(read(p.config));
	} catch (err) {
		return { config: null, problems: [`${path.relative(root, p.config)}: ${err instanceof Error ? err.message : String(err)}`], notices: [], tasks: [] };
	}
	const parsed = parseProdConfig(json);
	problems.push(...parsed.problems);
	const tasks = readTasks(root);
	problems.push(...checkTasks(tasks));
	/** @type {string[]} */
	let notices = [];
	if (parsed.config) {
		const migrations = fs
			.readdirSync(p.migrations)
			.filter((f) => f.endsWith('.sql'))
			.map((f) => read(path.join(p.migrations, f)));
		const fnSources = walk(p.functions, (n) => n.endsWith('.ts') && !n.endsWith('.test.ts')).map(read);
		const flagModules = walk(p.webLib, (n) => /_flag\.ts$/.test(n) && n !== 'env_flag.ts').map(read);
		const repo = checkAgainstRepo(parsed.config, {
			flagNames: flagNamesFromMigrations(migrations),
			functionEnvRead: functionEnvReads(fnSources),
			webFlags: webFlagsFrom(flagModules, read(p.releaseWeb)),
			cronFunctions: cronFunctionsFromMigrations(migrations),
			docExists: (rel) => fs.existsSync(path.join(root, rel)),
		});
		problems.push(...repo.problems);
		notices = repo.notices;
	}
	return { config: problems.length === 0 ? parsed.config : null, problems, notices, tasks };
}

/**
 * The prod config stages, in the order the sync runs them. Throws when the
 * config fails its guard, so no stage runs.
 *
 * @param {string} root
 */
export function prodConfigStages(root = REPO) {
	const checked = checkProdConfig(root);
	if (!checked.config) throw new Error(`apps/backend/ops/prod_config.json fails its guard:\n- ${checked.problems.join('\n- ')}`);
	const { config, tasks } = checked;
	return [featureFlagsStage(config), functionEnvStage(config), webEnvStage(config), cronUrlsStage(config), opsTasksStage(tasks)];
}

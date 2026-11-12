// Production config as code (issue #1350, decisions § 2430): the shape of
// apps/backend/ops/prod_config.json and every rule that can be checked from
// the repo alone. Pure: ../check_prod_config.mjs and ../config.mjs read the
// files and hand the derived sets in.
//
// An entry absent from the file is left untouched, which is why the
// committed file starts empty: the first release that carries it changes
// nothing.

/**
 * @typedef {{ enabled: boolean, signoff: string | null }} Toggle
 * @typedef {{
 *   feature_flags: Record<string, Toggle>,
 *   function_env: Record<string, Toggle>,
 *   web_env: Record<string, Toggle>,
 *   cron_urls: string[],
 *   retired_functions: string[],
 *   retired_function_env: string[],
 * }} ProdConfig
 */

export const SECTIONS = ['feature_flags', 'function_env', 'web_env', 'cron_urls', 'retired_functions', 'retired_function_env'];

/**
 * Edge Function env toggles the backend release may set with `supabase
 * secrets set`. Only booleans an Edge Function reads, so this can never carry
 * a credential; the guard also proves each one is still read.
 *
 * @type {readonly string[]}
 */
export const FUNCTION_ENV_ALLOW = [];

/**
 * Toggles that look like function env but are read somewhere a backend
 * release cannot reach. Named so the guard can say where they are set instead
 * of only refusing them.
 *
 * @type {Record<string, string>}
 */
export const ELSEWHERE = {
	AI_PLAN_ENABLED: 'the coach Lambda, from coach_config_keys in the sops file (infra/modules/web-stack/main.tf)',
	AI_PLAN_EDIT_ENABLED: 'the coach Lambda, from coach_config_keys in the sops file (infra/modules/web-stack/main.tf)',
	COACH_ASSIST_ENABLED: 'the coach Lambda, from coach_config_keys in the sops file (infra/modules/web-stack/main.tf)',
	COACH_FUEL_ENABLED: 'the coach Lambda, from coach_config_keys in the sops file (infra/modules/web-stack/main.tf)',
	PLATE_PHOTO_ENABLED: 'the coach Lambda, from coach_config_keys in the sops file (infra/modules/web-stack/main.tf)',
	ADAPTIVE_FITNESS_GATE: 'the mobile dotenv, which ships in a store build (apps/mobile_android/deployment.md)',
	WEIGHT_FLUID_ENABLED: 'the mobile dotenv, which ships in a store build (apps/mobile_android/deployment.md)',
};

/**
 * Each web flag and its server half (docs/ops/deployment.md § AI features
 * beside the Coach, § Adaptive fitness gate, § Weight-based fluid). `home`
 * is where the server half is set. When it is a section of this file the two
 * must be declared together and agree; otherwise the guard notes where the
 * other half goes.
 *
 * @type {{ web: string, server: string, home: 'function_env' | 'coach Lambda' | 'mobile dotenv' }[]}
 */
export const PAIRS = [
	{ web: 'PUBLIC_AI_PLAN_ENABLED', server: 'AI_PLAN_ENABLED', home: 'coach Lambda' },
	{ web: 'PUBLIC_AI_PLAN_EDIT_ENABLED', server: 'AI_PLAN_EDIT_ENABLED', home: 'coach Lambda' },
	{ web: 'PUBLIC_COACH_ASSIST_ENABLED', server: 'COACH_ASSIST_ENABLED', home: 'coach Lambda' },
	{ web: 'PUBLIC_PLATE_PHOTO_ENABLED', server: 'PLATE_PHOTO_ENABLED', home: 'coach Lambda' },
	{ web: 'PUBLIC_COACH_FUEL_ENABLED', server: 'COACH_FUEL_ENABLED', home: 'coach Lambda' },
	{ web: 'PUBLIC_ADAPTIVE_FITNESS_GATE', server: 'ADAPTIVE_FITNESS_GATE', home: 'mobile dotenv' },
	{ web: 'PUBLIC_WEIGHT_FLUID_ENABLED', server: 'WEIGHT_FLUID_ENABLED', home: 'mobile dotenv' },
];

/** Web flags that render nothing unless the Coach is on as well. */
export const NEEDS_COACH = ['PUBLIC_AI_PLAN_ENABLED', 'PUBLIC_AI_PLAN_EDIT_ENABLED', 'PUBLIC_PLATE_PHOTO_ENABLED', 'PUBLIC_COACH_FUEL_ENABLED', 'PUBLIC_COACH_ASSIST_ENABLED'];

const FLAG_NAME = /^[a-z][a-z0-9_]*$/;
const ENV_NAME = /^[A-Z][A-Z0-9_]*$/;
const FUNCTION_NAME = /^[a-z][a-z0-9_]*$/;
const FUNCTION_DIR = /^[a-z][a-z0-9-]*$/;
const SIGNOFF_URL = /^https:\/\/github\.com\/Absence0760\/[A-Za-z0-9_.-]+\/(issues|pull)\/[0-9]+(#(issuecomment|discussion_r|pullrequestreview)-?[0-9]+)?$/;
const SIGNOFF_PATH = /^(reviews|docs)\/[A-Za-z0-9_./-]+\.md(#[a-z0-9-]+)?$/;

/** @param {string} signoff */
export function signoffProblem(signoff) {
	if (SIGNOFF_URL.test(signoff)) return null;
	if (SIGNOFF_PATH.test(signoff) && !signoff.includes('..')) return null;
	return 'is neither a GitHub issue / PR / comment URL in Absence0760 nor a reviews/ or docs/ .md path';
}

/**
 * @param {unknown} value
 * @param {string} where
 * @param {string[]} problems
 * @returns {Toggle | null}
 */
function parseToggle(value, where, problems) {
	if (!value || typeof value !== 'object' || Array.isArray(value)) {
		problems.push(`${where} must be an object { enabled, signoff }`);
		return null;
	}
	const v = /** @type {Record<string, unknown>} */ (value);
	const extra = Object.keys(v).filter((k) => k !== 'enabled' && k !== 'signoff');
	if (extra.length > 0) problems.push(`${where} has unknown key(s) ${extra.join(', ')}`);
	if (typeof v.enabled !== 'boolean') {
		problems.push(`${where}.enabled must be true or false`);
		return null;
	}
	let signoff = null;
	if (v.signoff !== undefined) {
		if (typeof v.signoff !== 'string' || v.signoff.trim() === '') {
			problems.push(`${where}.signoff must be a non-empty string`);
		} else {
			const problem = signoffProblem(v.signoff);
			if (problem) problems.push(`${where}.signoff ${v.signoff} ${problem}`);
			signoff = v.signoff;
		}
	}
	if (v.enabled && signoff === null && v.signoff === undefined) {
		problems.push(`${where} is enabled with no signoff; link the approval that allows it`);
	}
	return { enabled: v.enabled, signoff };
}

/**
 * Parses the committed file and reports every shape problem at once.
 *
 * @param {unknown} json
 * @returns {{ config: ProdConfig | null, problems: string[] }}
 */
export function parseProdConfig(json) {
	/** @type {string[]} */
	const problems = [];
	if (!json || typeof json !== 'object' || Array.isArray(json)) {
		return { config: null, problems: ['prod_config.json must be an object'] };
	}
	const obj = /** @type {Record<string, unknown>} */ (json);
	const keys = Object.keys(obj);
	const unknown = keys.filter((k) => !SECTIONS.includes(k));
	const missing = SECTIONS.filter((k) => !keys.includes(k));
	if (unknown.length > 0) problems.push(`unknown section(s) ${unknown.join(', ')}; the sections are ${SECTIONS.join(', ')}`);
	if (missing.length > 0) problems.push(`missing section(s) ${missing.join(', ')}; an empty one is {} or []`);

	/** @type {ProdConfig} */
	const config = { feature_flags: {}, function_env: {}, web_env: {}, cron_urls: [], retired_functions: [], retired_function_env: [] };
	for (const [section, nameRe] of /** @type {const} */ ([
		['feature_flags', FLAG_NAME],
		['function_env', ENV_NAME],
		['web_env', ENV_NAME],
	])) {
		const raw = obj[section];
		if (raw === undefined) continue;
		if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
			problems.push(`${section} must be an object`);
			continue;
		}
		for (const [name, value] of Object.entries(raw)) {
			if (!nameRe.test(name)) {
				problems.push(`${section}.${name} is not a valid name`);
				continue;
			}
			const toggle = parseToggle(value, `${section}.${name}`, problems);
			if (toggle) config[section][name] = toggle;
		}
	}
	const cron = obj.cron_urls;
	if (cron !== undefined) {
		if (!Array.isArray(cron)) {
			problems.push('cron_urls must be a list of function names');
		} else {
			for (const fn of cron) {
				if (typeof fn !== 'string' || !FUNCTION_NAME.test(fn)) {
					problems.push(`cron_urls entry ${JSON.stringify(fn)} is not a function name like race_listings_sweep`);
				} else if (config.cron_urls.includes(fn)) {
					problems.push(`cron_urls names ${fn} twice`);
				} else {
					config.cron_urls.push(fn);
				}
			}
		}
	}
	for (const [section, nameRe, example] of /** @type {const} */ ([
		['retired_functions', FUNCTION_DIR, 'parkrun-import'],
		['retired_function_env', ENV_NAME, 'PARKRUN_USER_AGENT'],
	])) {
		const raw = obj[section];
		if (raw === undefined) continue;
		if (!Array.isArray(raw)) {
			problems.push(`${section} must be a list of names`);
			continue;
		}
		for (const name of raw) {
			if (typeof name !== 'string' || !nameRe.test(name)) {
				problems.push(`${section} entry ${JSON.stringify(name)} is not a name like ${example}`);
			} else if (config[section].includes(name)) {
				problems.push(`${section} names ${name} twice`);
			} else {
				config[section].push(name);
			}
		}
	}
	return { config: problems.length === 0 ? config : null, problems };
}

/**
 * The rules that need the repo: every declared name exists where it is read.
 *
 * @param {ProdConfig} config
 * @param {{
 *   flagNames: Set<string>,
 *   functionEnvRead: Set<string>,
 *   webFlags: Set<string>,
 *   cronFunctions: Set<string>,
 *   functionDirs: Set<string>,
 *   docExists: (path: string) => boolean,
 * }} repo
 * @param {readonly string[]} [allow] the function env allow-list; a parameter so the rules can be exercised while the shipped list is empty
 * @returns {{ problems: string[], notices: string[] }}
 */
export function checkAgainstRepo(config, repo, allow = FUNCTION_ENV_ALLOW) {
	/** @type {string[]} */
	const problems = [];
	/** @type {string[]} */
	const notices = [];

	for (const [name, toggle] of Object.entries(config.feature_flags)) {
		if (!repo.flagNames.has(name)) {
			problems.push(`feature_flags.${name}: no migration reads or seeds a private.feature_flags row of that name`);
		}
		checkSignoffPath(`feature_flags.${name}`, toggle, repo, problems);
	}

	for (const name of allow) {
		if (!repo.functionEnvRead.has(name)) {
			problems.push(`FUNCTION_ENV_ALLOW names ${name}, which no Edge Function reads with Deno.env.get any more; drop it from the allow-list`);
		}
	}
	for (const [name, toggle] of Object.entries(config.function_env)) {
		if (ELSEWHERE[name]) {
			problems.push(`function_env.${name}: no Edge Function reads it; it is set in ${ELSEWHERE[name]}`);
		} else if (!allow.includes(name)) {
			problems.push(`function_env.${name} is not on the allow-list of boolean Edge Function toggles (${allow.join(', ') || 'none'}); a function secret that is not a reviewed boolean toggle never goes in this file`);
		}
		checkSignoffPath(`function_env.${name}`, toggle, repo, problems);
	}

	for (const fn of config.retired_functions) {
		if (repo.functionDirs.has(fn)) {
			problems.push(`retired_functions names ${fn}, which still has a directory under supabase/functions; the release would deploy it and then delete it`);
		}
	}
	for (const name of config.retired_function_env) {
		if (repo.functionEnvRead.has(name)) {
			problems.push(`retired_function_env names ${name}, which an Edge Function still reads with Deno.env.get`);
		}
		if (name in config.function_env) {
			problems.push(`retired_function_env names ${name}, which function_env also sets`);
		}
	}

	for (const [name, toggle] of Object.entries(config.web_env)) {
		if (!repo.webFlags.has(name)) {
			problems.push(`web_env.${name} is not a PUBLIC_* flag a *_flag.ts gate in apps/web/src/lib reads and release-web.yml writes`);
		}
		checkSignoffPath(`web_env.${name}`, toggle, repo, problems);
	}

	for (const pair of PAIRS) {
		const web = config.web_env[pair.web];
		if (pair.home === 'function_env') {
			const server = config.function_env[pair.server];
			if (web && !server) problems.push(`web_env.${pair.web} is declared without its server half function_env.${pair.server}; declare both`);
			if (server && !web) problems.push(`function_env.${pair.server} is declared without its web half web_env.${pair.web}; declare both`);
			if (web && server && web.enabled !== server.enabled) {
				problems.push(`web_env.${pair.web} is ${web.enabled} but function_env.${pair.server} is ${server.enabled}; a paired flag flips both halves together`);
			}
		} else if (web) {
			notices.push(`web_env.${pair.web} is ${web.enabled}: set its other half ${pair.server} to match in the ${pair.home} (${ELSEWHERE[pair.server] ?? pair.home}).`);
		}
	}
	const coach = config.web_env.PUBLIC_COACH_ENABLED;
	for (const name of NEEDS_COACH) {
		if (config.web_env[name]?.enabled && coach && !coach.enabled) {
			problems.push(`web_env.${name} is on but web_env.PUBLIC_COACH_ENABLED is off, so the feature renders nothing; turn the Coach on or this flag off`);
		}
	}

	for (const fn of config.cron_urls) {
		if (!repo.cronFunctions.has(fn)) {
			problems.push(`cron_urls: no migration defines public.invoke_${fn}() reading the Vault entry ${fn}_url`);
		}
	}
	return { problems, notices };
}

/**
 * @param {string} where
 * @param {Toggle} toggle
 * @param {{ docExists: (path: string) => boolean }} repo
 * @param {string[]} problems
 */
function checkSignoffPath(where, toggle, repo, problems) {
	// reviews/ is gitignored, so only a docs/ path can be checked for presence.
	if (toggle.signoff?.startsWith('docs/') && !repo.docExists(toggle.signoff.replace(/#.*$/, ''))) {
		problems.push(`${where}.signoff names ${toggle.signoff}, which does not exist`);
	}
}

/**
 * The flag names the migrations define: every literal a migration compares
 * `private.feature_flags.name` against, or seeds a row under.
 *
 * @param {string[]} migrationSources
 */
export function flagNamesFromMigrations(migrationSources) {
	/** @type {Set<string>} */
	const names = new Set();
	for (const raw of migrationSources) {
		if (!raw.includes('feature_flags')) continue;
		const src = raw.replace(/--[^\n]*/g, '');
		for (const m of src.matchAll(/private\.feature_flags(?:\s+(?!where\b)\w+)?\s+where\s+(?:\w+\.)?name\s*=\s*'([a-z][a-z0-9_]*)'/gi)) {
			names.add(m[1]);
		}
		for (const m of src.matchAll(/insert\s+into\s+private\.feature_flags\s*\([^)]*\)\s*values\s*\(\s*'([a-z][a-z0-9_]*)'/gi)) {
			names.add(m[1]);
		}
	}
	return names;
}

/**
 * The functions whose `public.invoke_<fn>()` reads a `<fn>_url` Vault entry.
 *
 * @param {string[]} migrationSources
 */
export function cronFunctionsFromMigrations(migrationSources) {
	/** @type {Set<string>} */
	const fns = new Set();
	for (const src of migrationSources) {
		for (const m of src.matchAll(/function\s+public\.invoke_([a-z][a-z0-9_]*)\s*\(\s*\)([\s\S]*?)\$\$\s*;/gi)) {
			if (m[2].includes(`'${m[1]}_url'`)) fns.add(m[1]);
		}
	}
	return fns;
}

/**
 * The env names an Edge Function reads with `Deno.env.get('NAME')`.
 *
 * @param {string[]} functionSources non-test sources under supabase/functions
 */
export function functionEnvReads(functionSources) {
	/** @type {Set<string>} */
	const names = new Set();
	for (const src of functionSources) {
		for (const m of src.matchAll(/Deno\.env\.get\(\s*['"]([A-Z][A-Z0-9_]*)['"]\s*\)/g)) names.add(m[1]);
	}
	return names;
}

/**
 * The PUBLIC_* gates the web build can take from this file: named by a
 * `*_flag.ts` module (the derivation ci_workflow_guards.test.ts uses) and
 * written into apps/web/.env by release-web.yml.
 *
 * @param {string[]} flagModuleSources
 * @param {string} releaseWebYml
 */
export function webFlagsFrom(flagModuleSources, releaseWebYml) {
	/** @type {Set<string>} */
	const vars = new Set();
	for (const src of flagModuleSources) {
		for (const [, list] of src.matchAll(/import\s*\{([^}]*)\}\s*from\s*'\$app\/env\/public'/g)) {
			for (const m of list.matchAll(/\bPUBLIC_[A-Z0-9_]+\b/g)) vars.add(m[0]);
		}
		for (const m of src.matchAll(/\bimport\.meta\.env\.(PUBLIC_[A-Z0-9_]+)/g)) vars.add(m[1]);
	}
	return new Set([...vars].filter((v) => new RegExp(`^\\s*${v}=\\$\\{${v}\\}$`, 'm').test(releaseWebYml)));
}

/**
 * Rewrites the declared web_env keys in a dotenv body, leaving every other
 * line (and every undeclared flag's secret-sourced value) as it was. A
 * declared key with no line is appended.
 *
 * @param {string} dotenv
 * @param {Record<string, Toggle>} webEnv
 * @returns {{ text: string, applied: string[] }}
 */
export function overlayDotenv(dotenv, webEnv) {
	const entries = Object.entries(webEnv);
	/** @type {string[]} */
	const applied = [];
	const seen = new Set();
	const lines = dotenv.split('\n').map((line) => {
		const m = /^([A-Z][A-Z0-9_]*)=/.exec(line);
		if (!m || !webEnv[m[1]]) return line;
		seen.add(m[1]);
		applied.push(m[1]);
		return `${m[1]}=${webEnv[m[1]].enabled ? 'true' : 'false'}`;
	});
	for (const [name, toggle] of entries) {
		if (seen.has(name)) continue;
		if (lines.length > 0 && lines[lines.length - 1] === '') lines.pop();
		lines.push(`${name}=${toggle.enabled ? 'true' : 'false'}`, '');
		applied.push(name);
	}
	return { text: lines.join('\n'), applied };
}

const TASK_FILE = /^([0-9]{14})_([a-z0-9]+(?:_[a-z0-9]+)*)\.sql$/;

/**
 * The static half of the one-off task rules. The run-once and never-edited
 * half is the ledger's (private.begin_ops_task).
 *
 * @param {{ file: string, body: string }[]} tasks every file in apps/backend/ops/tasks
 */
export function checkTasks(tasks) {
	/** @type {string[]} */
	const problems = [];
	const stamps = new Map();
	for (const { file, body } of tasks) {
		if (file === 'README.md') continue;
		const m = TASK_FILE.exec(file);
		if (!m) {
			problems.push(`ops/tasks/${file} is not <14-digit timestamp>_<snake_name>.sql`);
			continue;
		}
		if (stamps.has(m[1])) problems.push(`ops/tasks/${file} reuses the timestamp of ${stamps.get(m[1])}`);
		stamps.set(m[1], file);
		const code = body.replace(/--[^\n]*/g, '').trim();
		if (code === '') problems.push(`ops/tasks/${file} has no SQL`);
		if (/^\s*\\/m.test(code)) problems.push(`ops/tasks/${file} holds a psql meta-command; a task is plain SQL`);
		if (/(^|;)\s*(begin|commit|rollback|end|start\s+transaction|savepoint|release)\b\s*(transaction|work)?\s*;/im.test(code)) {
			problems.push(`ops/tasks/${file} controls its own transaction; the sync runs each task in one`);
		}
	}
	return problems;
}

/** @param {string} file */
export const taskName = (file) => file.replace(/\.sql$/, '');

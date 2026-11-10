#!/usr/bin/env node
// The web half of production config as code (issue #1350, decisions § 2430):
// release-web.yml runs this after writing apps/web/.env from its secrets, and
// every PUBLIC_* flag apps/backend/ops/prod_config.json declares replaces the
// secret's value. A flag the file does not declare keeps its secret, so the
// committed (empty) file changes no build.
// Run: node scripts/prod_sync/web_env.mjs apps/web/.env

import fs from 'node:fs';

import { checkProdConfig } from './config.mjs';
import { overlayDotenv } from './lib/prod_config.mjs';

const file = process.argv[2];
if (!file || process.argv.length > 3) {
	console.error('usage: node scripts/prod_sync/web_env.mjs <path to apps/web/.env>');
	process.exit(2);
}
const { config, problems } = checkProdConfig();
if (!config) {
	for (const problem of problems) console.error(`::error title=prod_config.json::${problem}`);
	process.exit(1);
}
const { text, applied } = overlayDotenv(fs.readFileSync(file, 'utf8'), config.web_env);
fs.writeFileSync(file, text);
console.log(
	applied.length === 0
		? 'prod_config.json declares no web flags; every PUBLIC_* flag keeps its repo secret.'
		: `prod_config.json set ${applied.map((n) => `${n}=${config.web_env[n].enabled}`).join(', ')}.`,
);

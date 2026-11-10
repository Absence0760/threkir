#!/usr/bin/env node
// Guard for production config as code (issue #1350, decisions § 2430): fails
// the PR when apps/backend/ops/prod_config.json or apps/backend/ops/tasks/
// breaks a rule the release would otherwise refuse at deploy time: the shape,
// a sign-off for every enabled entry, every flag a migration defines, the
// Edge Function env allow-list, web flags the build reads, paired flags that
// agree, cron functions that have an invoker, and well-formed task files.
// The release runs the same check before any stage.
// Run: node scripts/prod_sync/check_prod_config.mjs

import { checkProdConfig } from './config.mjs';

const { problems, notices, tasks } = checkProdConfig();
for (const notice of notices) console.log(`::notice title=prod_config.json::${notice}`);
if (problems.length > 0) {
	for (const problem of problems) console.error(`::error title=prod_config.json::${problem}`);
	console.error(`\n${problems.length} problem(s) in apps/backend/ops/prod_config.json or apps/backend/ops/tasks/. See apps/backend/ops/README.md.`);
	process.exit(1);
}
console.log(`OK: prod_config.json is well-formed and matches the repo; ${tasks.filter((t) => t.file !== 'README.md').length} ops task file(s).`);

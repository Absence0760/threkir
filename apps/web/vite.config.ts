import { sveltekit } from "@sveltejs/kit/vite";
import { fileURLToPath } from "node:url";
import { defineConfig, loadEnv, type Plugin } from "vite";

import { esbuildTarget } from "./scripts/browser_baseline.mjs";
import { i18nAreaCatalogues } from "./src/lib/i18n/vite_plugin.ts";
import { checkEnvIsolation, formatGuardError } from "./scripts/env_isolation.mjs";

function envIsolationGuard(): Plugin {
	return {
		name: "env-isolation-guard",
		config(_config, { command, mode }) {
			if (command !== "serve") return;
			const env = loadEnv(mode, process.cwd(), "");
			const merged = { ...process.env, ...env };
			const result = checkEnvIsolation(merged);
			if (result.override) {
				console.warn(
					"\n[env-isolation] ALLOW_PROD_URL_IN_DEV=true — guard bypassed. " +
						"This is a power-user override; do not commit a setup that depends on it.\n",
				);
				return;
			}
			if (!result.ok) {
				throw new Error(formatGuardError(result, { scope: "vite" }));
			}
		},
	};
}

export default defineConfig({
	plugins: [
		envIsolationGuard(),
		// Splits each locale catalogue into core + per-area chunks (decisions § 1802).
		i18nAreaCatalogues({ srcDir: fileURLToPath(new URL("./src", import.meta.url)) }),
		sveltekit(),
	],
	build: {
		// Vite's default is `baseline-widely-available`, a list it regenerates
		// on every major — so the syntax floor moved on a dependency bump and
		// sat four Firefox releases below the one the source's own `:has()`
		// already required. The floor is declared in `package.json` now and
		// this reads it (decisions § 1670).
		target: esbuildTarget(),
	},
});

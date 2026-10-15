import { defineEnvVars } from "@sveltejs/kit/env";

// An unset variable reads as `undefined`, as it did under `$env/dynamic/*`:
// every caller below already treats absence as "feature off" or "fall back".
const optional = (value: string | undefined) => value;

export const variables = defineEnvVars({
	// Inlined at build time and required, as `$env/static/public` was — a
	// build without them fails rather than shipping a client that cannot
	// reach Supabase.
	PUBLIC_SUPABASE_URL: { public: true, static: true },
	PUBLIC_SUPABASE_ANON_KEY: { public: true, static: true },

	PUBLIC_ADAPTIVE_FITNESS_GATE: { public: true, schema: optional },
	PUBLIC_AI_PLAN_ENABLED: { public: true, schema: optional },
	PUBLIC_APPLE_AUTH_ENABLED: { public: true, schema: optional },
	PUBLIC_APP_RELEASE: { public: true, schema: optional },
	PUBLIC_BYPASS_PAYWALL: { public: true, schema: optional },
	PUBLIC_COACH_ENABLED: { public: true, schema: optional },
	PUBLIC_CYCLE_PLANS_ENABLED: { public: true, schema: optional },
	PUBLIC_EXPORT_HUB_URL: { public: true, schema: optional },
	PUBLIC_FUNDRAISING_ENABLED: { public: true, schema: optional },
	PUBLIC_GOOGLE_AUTH_ENABLED: { public: true, schema: optional },
	PUBLIC_LIVE_HUB_URL: { public: true, schema: optional },
	PUBLIC_MAPTILER_KEY: { public: true, schema: optional },
	PUBLIC_OFF_ROUTE_ESCALATION_ENABLED: { public: true, schema: optional },
	PUBLIC_REVENUECAT_WEB_CHECKOUT_URL: { public: true, schema: optional },
	PUBLIC_REVENUECAT_WEB_PORTAL_URL: { public: true, schema: optional },
	PUBLIC_ROUTE_GEN_ENABLED: { public: true, schema: optional },
	PUBLIC_SENTRY_DSN: { public: true, schema: optional },
	PUBLIC_SITE_URL: { public: true, schema: optional },
	PUBLIC_STRAVA_CLIENT_ID: { public: true, schema: optional },
	PUBLIC_TILE_STYLE_URL: { public: true, schema: optional },
	PUBLIC_USDA_FDC_API_KEY: { public: true, schema: optional },
	PUBLIC_VAPID_PUBLIC_KEY: { public: true, schema: optional },
	PUBLIC_WEIGH_IN_ENABLED: { public: true, schema: optional },

	ANTHROPIC_API_KEY: { schema: optional },
	APP_RELEASE: { schema: optional },
	BYPASS_PAYWALL: { schema: optional },
	COACH_PROVIDER: { schema: optional },
	GRAPHHOPPER_API_KEY: { schema: optional },
	GRAPHHOPPER_URL: { schema: optional },
	GRAPH_CYCLE_API_KEY: { schema: optional },
	GRAPH_CYCLE_URL: { schema: optional },
	NODE_ENV: { schema: optional },
	OPENAI_API_KEY: { schema: optional },
	OPENAI_BASE_URL: { schema: optional },
	OPENAI_MODEL: { schema: optional },
	OSRM_URL: { schema: optional },
	SENTRY_DSN: { schema: optional },
	SUPABASE_SECRET_KEY: { schema: optional },
});

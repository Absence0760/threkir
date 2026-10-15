import * as Sentry from "@sentry/sveltekit";
import { dev } from "$app/env";
import { PUBLIC_APP_RELEASE, PUBLIC_SENTRY_DSN } from "$app/env/public";
import type { HandleClientError } from "@sveltejs/kit/hooks";
import {
	redactBreadcrumb,
	redactEventSignedUrls,
	redactStreamedSpan,
	type SentryEventWithSpans,
} from "#lib/sentry/redact.ts";
import { SENTRY_DATA_COLLECTION } from "#lib/sentry/data_collection.ts";
import { hasAcceptedConsent } from "#lib/settings/consent.svelte.ts";
import { logClientError } from "#lib/core/client_error_log.ts";

const dsn = PUBLIC_SENTRY_DSN ?? "";
const release = PUBLIC_APP_RELEASE || "dev";

if (!dev && dsn && hasAcceptedConsent()) {
	Sentry.init({
		dsn,
		release,
		environment: release !== "dev" ? "production" : "development",
		dataCollection: SENTRY_DATA_COLLECTION,
		tracesSampleRate: 0.1,
		replaysSessionSampleRate: 0,
		replaysOnErrorSampleRate: 0,
		beforeBreadcrumb: (breadcrumb) => {
			if (
				breadcrumb.category === 'fetch' ||
				breadcrumb.category === 'xhr' ||
				breadcrumb.category === 'console'
			) {
				return redactBreadcrumb(breadcrumb);
			}
			return breadcrumb;
		},
		beforeSend: (event) => redactEventSignedUrls(event as SentryEventWithSpans) as typeof event,
		beforeSendSpan: (span) => redactStreamedSpan(span),
	});
}

// Wrap rather than directly exporting `Sentry.handleErrorWithSentry()`
// so the consent gate is enforced at handler-call time. The Sentry
// SDK currently no-ops when `init` was never called, but that's a
// version-fragile contract — making the gate explicit here means a
// future Sentry SDK upgrade can't silently re-route errors through
// a minimal-init path. /audit/owasp May 2026 Medium #3.
// Cast the Sentry wrapper through `unknown` to a SvelteKit
// HandleClientError — @sentry/sveltekit v10's exported type lists
// the server-side RequestEvent shape, which is wider than the client
// NavigationEvent SvelteKit passes here. The runtime is identical;
// only the static types differ.
const handleErrorViaSentry = Sentry.handleErrorWithSentry() as unknown as HandleClientError;
export const handleError: HandleClientError = (input) => {
	logClientError(input);
	if (!hasAcceptedConsent()) return;
	return handleErrorViaSentry(input);
};

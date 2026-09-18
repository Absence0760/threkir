// Sentry reporting for the Function-URL Lambdas.
//
// The Lambda twin of `apps/backend/supabase/functions/_shared/sentry.ts`,
// and deliberately a different shape. That one wraps `serve` because an
// Edge Function lets its errors reach the wrapper; every Lambda in this
// directory already catches its own and answers with a chosen status, so
// an outer wrapper here would sit above a `catch` that never rethrows and
// fire almost never. This module is therefore called FROM the outermost
// catch, beside the `console.error` that was previously the only record.
//
// Report unexpected failures only. Several handlers catch deliberately —
// generate-route falling back when an engine is unreachable, share-* when
// an optional upstream is slow — and those are control flow, not faults.
// Routing them here would spend the issue quota on working code and train
// the reader to ignore the project.
//
// Off when `SENTRY_DSN` is unset, which is the dev and CI default: no
// init, no network, no flush. Terraform feeds the var from the sops file
// via `local.sentry_env` (infra/modules/web-stack/main.tf).

import * as Sentry from '@sentry/node';

let initialized = false;

function ensureInit(): boolean {
	if (initialized) return true;
	const dsn = process.env.SENTRY_DSN;
	if (!dsn) return false;
	Sentry.init({
		dsn,
		release: process.env.APP_RELEASE || 'dev',
		environment: process.env.APP_RELEASE && process.env.APP_RELEASE !== 'dev'
			? 'production'
			: 'development',
		// Same data-minimisation posture as the Edge Function wrapper: the
		// lawful basis for sending anything to Sentry is legitimate interest
		// in service reliability, which does not extend to the caller's IP,
		// headers, cookies or JWT. `sendDefaultPii: false` covers the first
		// two; `beforeSend` drops the rest of the envelope explicitly rather
		// than trusting that default to keep its meaning across an SDK bump.
		sendDefaultPii: false,
		// Errors only. These functions are on the request path -- coach
		// streams a response and the share Lambdas render social unfurls for
		// crawlers -- so tracing would add per-request latency and spans
		// nobody reads to buy nothing this change is for.
		tracesSampleRate: 0,
		beforeSend: (event) => {
			delete event.request;
			delete event.user;
			delete event.server_name;
			return event;
		},
	});
	initialized = true;
	return true;
}

/// Report an unexpected failure from a Lambda's outermost catch.
///
/// `fn` is the Lambda's own name ('coach', 'share-run', ...) and becomes
/// the `lambda` tag, which is what makes one project's issues separable
/// per function -- the Edge Function wrapper tags the same way.
///
/// Always awaited, never rethrows. The flush is the Lambda-specific part
/// and the reason this cannot just be `captureException`: the runtime
/// freezes the execution environment the moment the handler returns, so an
/// event still sitting in the transport queue is simply lost -- silently,
/// and only for the errors that happen to be the last thing a container
/// does. A reporting failure must never become the caller's failure, so
/// everything here is inside its own try/catch: this function is called
/// from a path that is already handling one fault and must not add a
/// second.
export async function reportException(
	fn: string,
	err: unknown,
	context?: Record<string, unknown>,
): Promise<void> {
	try {
		if (!ensureInit()) return;
		Sentry.withScope((scope) => {
			scope.setTag('lambda', fn);
			if (context) scope.setContext('handler', context);
			Sentry.captureException(err);
		});
		await Sentry.flush(2000);
	} catch {
		// Reporting is best-effort. The caller is mid-failure already.
	}
}

// What every web-side `Sentry.init` is allowed to collect: nothing about the
// person beyond the error itself.
//
// Sentry 11 removed `sendDefaultPii` and replaced it with `dataCollection`,
// whose defaults are the old `sendDefaultPii: true` — user info, cookies,
// headers, every request and response body, DB query parameters and
// stack-frame local variables. An init that sets nothing therefore went
// from minimal to maximal on the bump, with no type error to say so. The
// lawful basis for sending anything to Sentry is legitimate interest in
// service reliability, which covers none of that, so every category is off
// here rather than restored to v10's partial denylist.
//
// One constant for all three init sites (hooks.client.ts, hooks.server.ts,
// core/lambda_sentry.ts) so they cannot drift apart; data_collection.test.ts
// fails when an init stops passing it.

import type { NodeOptions } from '@sentry/node';

export const SENTRY_DATA_COLLECTION = {
	userInfo: false,
	cookies: false,
	httpHeaders: false,
	httpBodies: [],
	urlQueryParams: false,
	genAI: { inputs: false, outputs: false },
	databaseQueryData: false,
	queues: false,
	graphQL: { document: false, variables: false },
	stackFrameVariables: false,
} satisfies NonNullable<NodeOptions['dataCollection']>;

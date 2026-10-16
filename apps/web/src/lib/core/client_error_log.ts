/**
 * The local half of the client `handleError` hook. Sentry only sees an
 * unexpected client error when the reader has consented, so without this a
 * production "500 Internal Error" leaves nothing in DevTools to say what threw.
 * Writing to the reader's own console sends nothing anywhere, so it needs no
 * consent and runs before, and independent of, the Sentry path.
 *
 * The e2e crash net (tests-e2e/fixtures/crash-net.ts) recognises a console
 * error by this prefix, which is how it catches a client error boundary even
 * when the spec closes its page before the boundary could be inspected.
 */
export const CLIENT_ERROR_LOG_PREFIX = '[threkir] unhandled client error';

/**
 * The client `handleError` input as SvelteKit 3 passes it: a `kind`
 * discriminant and the caught `error`, with no top-level status or message.
 * A framework error (a 404, a failed load) carries its own status and safe
 * message; an app error carries the `App.Error` body; anything else is an
 * unknown throw, which the boundary renders as 500 Internal Error.
 */
export interface ClientErrorInput {
	kind: 'app' | 'framework' | 'unknown';
	error: unknown;
	event: { route?: { id: string | null } | null };
}

function describe(input: ClientErrorInput): { status: number; message: string } {
	const err = input.error as { status?: unknown; message?: unknown } | null | undefined;
	const message = typeof err?.message === 'string' ? err.message : '';
	if (input.kind === 'framework' && typeof err?.status === 'number') {
		return { status: err.status, message: message || 'Error' };
	}
	if (input.kind === 'app') {
		return { status: typeof err?.status === 'number' ? err.status : 500, message: message || 'Error' };
	}
	return { status: 500, message: 'Internal Error' };
}

export type ErrorSink = (...data: unknown[]) => void;

export function logClientError(input: ClientErrorInput, sink: ErrorSink = console.error): void {
	// SvelteKit calls the hook for a client-side navigation to an unmatched
	// route too. A 404 is a page the reader asked for that does not exist, not
	// something that threw, and logging it would make the crash net fail every
	// spec that visits one on purpose.
	try {
		const { status, message } = describe(input);
		if (status === 404) return;
		const route = input.event.route?.id ?? '(no route)';
		sink(CLIENT_ERROR_LOG_PREFIX, `${status} ${message} on ${route}`, input.error);
	} catch {
		// A broken console must not stop the error reaching the boundary or the
		// consent-gated Sentry path.
	}
}

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

export interface ClientErrorInput {
	error: unknown;
	status: number;
	message: string;
	event: { route?: { id: string | null } | null };
}

export type ErrorSink = (...data: unknown[]) => void;

export function logClientError(input: ClientErrorInput, sink: ErrorSink = console.error): void {
	// SvelteKit calls the hook for a client-side navigation to an unmatched
	// route too. A 404 is a page the reader asked for that does not exist, not
	// something that threw, and logging it would make the crash net fail every
	// spec that visits one on purpose.
	if (input.status === 404) return;
	try {
		const route = input.event.route?.id ?? '(no route)';
		sink(CLIENT_ERROR_LOG_PREFIX, `${input.status} ${input.message} on ${route}`, input.error);
	} catch {
		// A broken console must not stop the error reaching the boundary or the
		// consent-gated Sentry path.
	}
}

/// The loggable part of an AI-provider failure: name, HTTP status and the
/// provider's error type — never the message. An Anthropic SDK APIError's
/// message is the status followed by the response body, and a 400 body can
/// quote the runner's own text, so neither it nor the stack (which repeats
/// it) may reach a log line.
export function providerErrorFields(e: unknown): Record<string, unknown> {
	if (!e || typeof e !== 'object') return { kind: typeof e };
	const o = e as { name?: unknown; status?: unknown; error?: { error?: { type?: unknown } } };
	return {
		name: typeof o.name === 'string' ? o.name : 'unknown',
		status: typeof o.status === 'number' ? o.status : null,
		type: typeof o.error?.error?.type === 'string' ? o.error.error.type : null,
	};
}

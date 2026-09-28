// Pure helpers for stripping Supabase Storage signed-URL tokens
// before they land in a Sentry breadcrumb / span / event. Extracted
// from `apps/web/src/hooks.client.ts` so the logic can be unit-
// tested under `tsx --test` (the hooks file imports `$app/environment`
// + `$env/dynamic/public`, which are SvelteKit-only).
//
// Signed URLs embed an HMAC token in the query that grants access to
// a bucket object; we don't want them in the error-reporting tail.
// Match is broad — "/storage/v1/object/sign/" anywhere in the URL —
// so it covers run-photos and any future private bucket.

export function redactSignedUrl(url: string): string {
	if (!url.includes('/storage/v1/object/sign/')) return url;
	const q = url.indexOf('?');
	return q === -1 ? url : url.slice(0, q) + '?<redacted>';
}

/// Strip the JWT querystring from a live-hub WebSocket subscribe URL.
/// Browser WS API can't set Authorization headers on the upgrade, so
/// the auth token rides on `?token=…`. If a `console.log` or breadcrumb
/// ever captures the URL, the JWT must NOT reach Sentry. Matches
/// either subscribe or snapshot paths under `/v1/live/{id}/…`.
/// /audit/owasp May 2026 Low #6.
export function redactLiveHubToken(url: string): string {
	if (!/\/v1\/live\/[^/]+\/(subscribe|snapshot)\b/.test(url)) return url;
	return url.replace(/([?&])token=[^&]*/g, '$1token=<redacted>');
}

/// Apply every URL redactor in series. Cheap (each is a single
/// includes/test) and order-independent because each gates on its
/// own URL shape.
export function redactUrl(url: string): string {
	return redactLiveHubToken(redactSignedUrl(url));
}

export function redactBreadcrumb<
	T extends { category?: string; message?: string; data?: Record<string, unknown> },
>(b: T): T {
	const u = b.data?.url;
	if (typeof u === 'string') {
		b.data!.url = redactUrl(u);
	}
	// `console` breadcrumbs carry the log message in `message` and
	// `data.arguments`. apps/web/src/lib/core/data.ts logs Storage paths via
	// console.warn on delete-failure paths; redact any occurrence of a
	// signed-URL substring.
	if (b.category === 'console' && typeof b.message === 'string') {
		b.message = redactUrl(b.message);
	}
	return b;
}

export interface SentrySpanLike {
	data?: Record<string, unknown>;
}
export interface SentryEventWithSpans {
	transaction?: string;
	spans?: SentrySpanLike[];
	request?: { url?: string };
}

export function redactEventSignedUrls(event: SentryEventWithSpans): SentryEventWithSpans {
	if (typeof event.transaction === 'string') {
		event.transaction = redactUrl(event.transaction);
	}
	if (event.request?.url) {
		event.request.url = redactUrl(event.request.url);
	}
	if (Array.isArray(event.spans)) {
		for (const s of event.spans) {
			const u = s.data?.url;
			if (typeof u === 'string') {
				s.data!.url = redactUrl(u);
			}
		}
	}
	return event;
}

/// Sentry 11 streams spans by default and runs them through
/// `beforeSendSpan`; `beforeSendTransaction` never fires in that mode, so
/// `redactEventSignedUrls` no longer sees a span. A streamed span carries its
/// URL in `name` ("GET https://…") and in attributes (`url.full`,
/// `http.url`, …), each either a bare value or `{ value, unit }`. Every
/// string is run through `redactUrl` rather than a list of known keys:
/// each redactor gates on its own URL shape, so an unrelated string is
/// returned untouched, and a key the SDK renames next major is still covered.
export interface StreamedSpanLike {
	name: string;
	attributes: Record<string, unknown>;
}

export function redactStreamedSpan<T extends StreamedSpanLike>(span: T): T {
	span.name = redactUrl(span.name);
	for (const [key, value] of Object.entries(span.attributes)) {
		if (typeof value === 'string') {
			span.attributes[key] = redactUrl(value);
		} else if (
			value !== null &&
			typeof value === 'object' &&
			typeof (value as { value?: unknown }).value === 'string'
		) {
			const attr = value as { value: string };
			attr.value = redactUrl(attr.value);
		}
	}
	return span;
}

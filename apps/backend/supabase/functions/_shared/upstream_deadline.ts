/// The bound on a function's calls to a third-party feed.
///
/// Nothing else bounds them. The Edge runtime kills a request at 150 s of wall
/// clock and answers a bare 500, and pg_net drops its side of a cron call after
/// 60 s while the worker keeps waiting, so a feed that accepts the connection
/// and never answers holds the request until it is killed, writing nothing and
/// saying nothing.
///
/// It is a budget for the whole request, not for one call: a function that
/// makes several calls in sequence (race-results-import's RunSignUp leg makes
/// up to nine) takes ONE signal at its first call and hands it to every later
/// one, so nine slow answers cannot sum past it. The signal is passed to
/// `fetch`, which bounds the headers and the body read together — a feed that
/// sends its headers and then trickles the body is as stuck as one that never
/// answers. A 500-race RunSignUp page is ~2.9 MB and answers in seconds; a
/// request whose upstream calls have not finished in this long are not going to.
export const UPSTREAM_TIMEOUT_MS = 30_000;

/// Whether a rejected fetch or body read is the deadline firing. Measured
/// against Deno's own fetch, a timed-out request and a timed-out body read both
/// reject with a `TimeoutError` DOMException; anything else that rejects a
/// fetch is the feed being unreachable.
export function isUpstreamTimeout(err: unknown): boolean {
  return err instanceof DOMException && err.name === 'TimeoutError';
}

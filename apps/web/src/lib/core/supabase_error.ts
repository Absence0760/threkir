/// Extract only the log-safe fields from a Supabase/PostgREST error.
/// `.code` + `.message` are safe to log; `.details` and `.hint` can
/// echo row fragments — on the coach path the caller's chat content is
/// Art 9 health/injury data, and on the route paths it is location —
/// and the raw object must never reach CloudWatch.
///
/// Lives here rather than beside its first caller so a server handler
/// can scrub a log line without importing the coach handler (and the
/// Anthropic SDK behind it). Mirrors the `.code`/`.message` pattern used
/// in rate_limit_errors.ts + the Edge Functions, and is the shape the
/// edge_function_guards.test.ts raw-object ban enforces. /audit/pii-in-logs.
export function supabaseErrorFields(
	err: { code?: string; message?: string } | null | undefined,
): { code: string | undefined; message: string | undefined } {
	return { code: err?.code, message: err?.message };
}

/// SQLSTATE 23505 — `unique_violation`. Postgres raises it when an insert
/// re-states a row that already exists, which for every join-shaped write in
/// this app (bookmark a route, join a club, follow a runner, join a challenge)
/// is the SUCCESS case restated: a double-tap, a stale list whose "joined"
/// flag was computed before someone else's tab wrote the row, an offline
/// replay. Absorbing it is the difference between a no-op and a raw failure
/// toast on a button the user has already succeeded at pressing.
///
/// One predicate rather than a comparison against the literal at each site:
/// the sites drifted, and `joinChallenge` was the one that never got it.
export function isDuplicateKeyError(err: unknown): boolean {
	return typeof err === 'object' && err !== null && (err as { code?: unknown }).code === '23505';
}

/// A failed Supabase result, thrown. postgrest-js hands back `error` as the
/// parsed JSON body — a plain object, not an `Error` — so throwing it raw gave
/// Sentry "Object captured as exception" with no stack and made `instanceof
/// Error` lie. This carries the two fields callers branch on (`code` for
/// `isDuplicateKeyError`, PGRST116, 42501 / 23514; `status` where the source
/// had one) and nothing else: `details` and `hint` can echo row data, and the
/// original is deliberately not kept as `cause`, because Node's
/// `console.error` prints a `cause` — even a non-enumerable one — into
/// CloudWatch. /audit/pii-in-logs, decisions § 1917.
export class DbError extends Error {
	readonly code: string | undefined;
	readonly status: number | undefined;

	constructor(message: string, code?: string, status?: number) {
		super(code ? (message ? `${message} (${code})` : `(${code})`) : message);
		this.name = 'DbError';
		this.code = code;
		this.status = status;
	}
}

/// SQLSTATE 23P01 — `exclusion_violation`. The only exclusion constraint in
/// the schema is training_plans_active_no_overlap (decisions § 2008), so a
/// date shift, re-plan, resume or week duplication that would make two active
/// plans share a day lands here. Raw, it reads as a code; this says what
/// happened and what to do about it.
export class PlanOverlapError extends DbError {
	constructor(status?: number) {
		super('', '23P01', status);
		this.name = 'PlanOverlapError';
		this.message =
			'These dates overlap another active training plan. End that plan earlier or pick dates after it.';
	}
}

export function isPlanOverlapError(err: unknown): boolean {
	return typeof err === 'object' && err !== null && (err as { code?: unknown }).code === '23P01';
}

/// SQLSTATE TR001 — trim_training_plan refusing to end a plan early because a
/// workout the runner already completed falls after the cut (decisions
/// § 2062). The create and clone RPCs raise it for `p_overlap = 'trim'`.
export function isPlanTrimBlockedError(err: unknown): boolean {
	return typeof err === 'object' && err !== null && (err as { code?: unknown }).code === 'TR001';
}

/// Turn a Supabase result's `error` into something fit to throw. An `Error`
/// that is not postgrest-js's own `PostgrestError` (auth-js, storage-js and
/// functions-js all throw real subclasses, and a FunctionsHttpError's
/// `context` is read by callers) passes through as it is; a `PostgrestError`
/// is rebuilt, since its `toJSON` serialises `details` and `hint`.
export function dbError(e: unknown): Error {
	if (e instanceof Error && e.name !== 'PostgrestError') return e;
	let err: DbError;
	if (e && typeof e === 'object') {
		const { message, code, status } = e as { message?: unknown; code?: unknown; status?: unknown };
		if (code === '23P01') {
			const overlap = new PlanOverlapError(typeof status === 'number' ? status : undefined);
			Error.captureStackTrace?.(overlap, dbError);
			return overlap;
		}
		err = new DbError(
			typeof message === 'string' ? message : '',
			typeof code === 'string' && code !== '' ? code : undefined,
			typeof status === 'number' ? status : undefined,
		);
	} else {
		err = new DbError(typeof e === 'string' ? e : '');
	}
	Error.captureStackTrace?.(err, dbError);
	return err;
}

/// The message of an `Error` the app raised on purpose, or null for a database
/// failure or a value that is not an `Error`. For a surface whose fallback is
/// its own localised copy (`appErrorMessage(e) ?? m('x.saveFailed')`): before
/// the data layer threw `DbError`, a failed query arrived as a plain object and
/// fell through `e instanceof Error ? e.message : m(…)` to that copy, so this
/// keeps "invalid invite token (P0001)" from replacing "This invite link is
/// invalid or expired". Use `thrownMessage` where the detail is the point.
export function appErrorMessage(e: unknown): string | null {
	return e instanceof Error && (!(e instanceof DbError) || e instanceof PlanOverlapError) ? e.message : null;
}

/// The user-facing detail of a thrown value. The data layer throws `DbError`
/// (above), but a third-party or legacy throw can still be a plain object, and
/// `e instanceof Error ? e.message : String(e)` renders one as "[object
/// Object]". A value with no readable message yields '' so the caller shows its
/// own copy rather than noise.
export function thrownMessage(e: unknown): string {
	if (e instanceof Error) return e.message;
	if (typeof e === 'string') return e;
	if (e && typeof e === 'object' && typeof (e as { message?: unknown }).message === 'string') {
		const { message, code } = e as { message: string; code?: unknown };
		return typeof code === 'string' && code !== '' ? `${message} (${code})` : message;
	}
	return '';
}

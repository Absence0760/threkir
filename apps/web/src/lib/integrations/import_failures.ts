/// Structured failure recording for the bulk importers (Strava export zip,
/// Garmin Account Data bundle).
///
/// Both importers used to swallow the caught error and increment a bare
/// counter, so a five-year migration reported `failed: 47` and nothing
/// else — no activity name, no reason, no way to tell a transient network
/// drop (re-run the import and it lands) from a corrupt archive member
/// (it never will). Re-running an import IS the retry, because both
/// importers dedupe against what already landed; what the runner was
/// missing is the information needed to decide whether re-running is
/// worth it.
///
/// `detail` deliberately carries only the log-safe `.code` / `.message`
/// fields of a Supabase/PostgREST error, never `.details` / `.hint` —
/// those echo row fragments (see core/supabase_error.ts).

export type ImportFailureReason =
	| 'network'
	| 'auth'
	| 'rate_limited'
	| 'too_large'
	| 'unparseable'
	| 'rejected'
	| 'unknown';

export interface ImportFailure {
	name: string;
	startedAt: string | null;
	reason: ImportFailureReason;
	detail: string;
}

export interface ImportFailureLog {
	items: ImportFailure[];
	truncated: number;
}

/// A pathological archive can fail on every one of tens of thousands of
/// members; cap what we hold in memory and report the overflow rather
/// than letting the failure list itself become the OOM.
export const MAX_RECORDED_IMPORT_FAILURES = 200;

const MAX_DETAIL_CHARS = 200;

export function newImportFailureLog(): ImportFailureLog {
	return { items: [], truncated: 0 };
}

function errorMessage(err: unknown): string {
	if (err == null) return '';
	if (typeof err === 'string') return err;
	if (typeof err === 'object') {
		const m = (err as { message?: unknown }).message;
		if (typeof m === 'string') return m;
		return '';
	}
	return String(err);
}

function errorCode(err: unknown): string {
	if (err && typeof err === 'object') {
		const c = (err as { code?: unknown }).code;
		if (typeof c === 'string') return c;
		if (typeof c === 'number') return String(c);
	}
	return '';
}

function errorStatus(err: unknown): number | null {
	if (err && typeof err === 'object') {
		const s = (err as { status?: unknown }).status;
		if (typeof s === 'number' && Number.isFinite(s)) return s;
	}
	return null;
}

function tidyDetail(code: string, message: string): string {
	const collapsed = message.replace(/\s+/g, ' ').trim();
	const prefixed = code && collapsed ? `${code}: ${collapsed}` : code || collapsed;
	return prefixed.length > MAX_DETAIL_CHARS
		? `${prefixed.slice(0, MAX_DETAIL_CHARS - 1)}…`
		: prefixed;
}

/// Bucket a thrown value into a reason the UI can explain and act on.
/// Order matters: an "invalid token" reads as auth, not as unparseable,
/// and a "payload too large" as too_large, not as rejected.
export function classifyImportFailure(err: unknown): {
	reason: ImportFailureReason;
	detail: string;
} {
	const message = errorMessage(err);
	const code = errorCode(err);
	const status = errorStatus(err);
	const detail = tidyDetail(code, message);

	if (status === 429) return { reason: 'rate_limited', detail };
	if (status === 401 || status === 403) return { reason: 'auth', detail };
	if (status === 413) return { reason: 'too_large', detail };

	if (code === 'P0001' && /rate limit exceeded/i.test(message))
		return { reason: 'rate_limited', detail };

	if (/failed to fetch|networkerror|network error|load failed|fetch failed|err_internet/i.test(message))
		return { reason: 'network', detail };
	if (/not signed in|unauthoriz|unauthentic|jwt|invalid token|session (has )?expired/i.test(message))
		return { reason: 'auth', detail };
	if (/too many requests|rate limit/i.test(message)) return { reason: 'rate_limited', detail };
	if (/too large|maximum allowed size|exceeds the maximum|payload too large|quota/i.test(message))
		return { reason: 'too_large', detail };

	// Any remaining SQLSTATE / PGRST code means the server answered and
	// refused — a data-exception class like 22P02 ("invalid input syntax")
	// otherwise fell through to the `invalid` message pattern below and
	// reported a server rejection as an unreadable file. Same principle as
	// settings_write.ts's classifyWriteFailure: a code at all is `rejected`.
	if (code) return { reason: 'rejected', detail };

	if (/row-level security|violates|permission denied|forbidden/i.test(message))
		return { reason: 'rejected', detail };
	if (
		/parse|malformed|corrupt|unsupported file format|no track|no fit file|invalid|not a valid/i.test(
			message,
		)
	)
		return { reason: 'unparseable', detail };

	return { reason: 'unknown', detail };
}

/// Append one failure, classifying the thrown value. Past the cap the
/// entry is counted in `truncated` instead of retained.
export function recordImportFailure(
	log: ImportFailureLog,
	entry: { name: string; startedAt?: string | null },
	err: unknown,
): void {
	if (log.items.length >= MAX_RECORDED_IMPORT_FAILURES) {
		log.truncated++;
		return;
	}
	const { reason, detail } = classifyImportFailure(err);
	log.items.push({
		name: entry.name.trim() || 'Unnamed activity',
		startedAt: entry.startedAt ?? null,
		reason,
		detail,
	});
}

/// Total order on two reason identifiers, in UTF-16 code units — the one
/// ordering both runtimes hold, because Dart ships no collator and
/// `String.compareTo` is all the phone has. `localeCompare` asked the host's
/// ICU data instead, so the summary line's order was a property of the
/// reader's browser rather than of the reasons: a Hawaiian collation files the
/// vowel-initial `unknown` and `unparseable` ahead of every consonant-initial
/// reason, over the seven that already exist (decisions § 1656).
export function compareImportFailureReasons(a: string, b: string): number {
	if (a === b) return 0;
	return a < b ? -1 : 1;
}

/// Reason tallies for the summary line, commonest first, then by reason
/// name so the order is stable across renders.
export function groupImportFailures(
	log: ImportFailureLog,
): { reason: ImportFailureReason; count: number }[] {
	const counts = new Map<ImportFailureReason, number>();
	for (const f of log.items) counts.set(f.reason, (counts.get(f.reason) ?? 0) + 1);
	return [...counts.entries()]
		.map(([reason, count]) => ({ reason, count }))
		.sort((a, b) => b.count - a.count || compareImportFailureReasons(a.reason, b.reason));
}

function csvField(value: string): string {
	return `"${value.replace(/"/g, '""')}"`;
}

/// A downloadable report of what did not import. Column headers are
/// English identifiers, not localized copy — the file is a data artefact
/// a runner pastes into a spreadsheet or a support thread, and a locale
/// that renamed the columns would make two reports unmergeable.
export function importFailureReportCsv(log: ImportFailureLog): string {
	const lines = ['Activity,Started,Reason,Detail'];
	for (const f of log.items) {
		lines.push(
			[csvField(f.name), csvField(f.startedAt ?? ''), csvField(f.reason), csvField(f.detail)].join(
				',',
			),
		);
	}
	if (log.truncated > 0) {
		lines.push(
			[
				csvField(`(${log.truncated} further failures not recorded)`),
				csvField(''),
				csvField('truncated'),
				csvField(`recording cap ${MAX_RECORDED_IMPORT_FAILURES} reached`),
			].join(','),
		);
	}
	return lines.join('\n');
}

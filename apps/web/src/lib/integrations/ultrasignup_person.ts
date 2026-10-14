/// The runner's UltraSignup person: who they are on UltraSignup, as Settings
/// stores it and the race import sends it (decisions § 1841).
///
/// UltraSignup's results feed is keyed by NAME and answers with every
/// same-named person, so an import needs the name AND the `Id` the runner picked
/// out of the people it returns. The Edge Function owns the validation; this
/// module reads its answers defensively and turns the stored `integrations` row
/// back into a link.

/// The longest name part the Edge Function sends, and the
/// `integrations.external_*_name` CHECK (20270726000003).
export const ULTRASIGNUP_NAME_MAX_LEN = 60;

export interface UltraSignUpCandidate {
	id: string;
	firstName: string;
	lastName: string;
	/// Null where UltraSignup does not know it.
	age: number | null;
	resultCount: number;
	recentEvents: { name: string; date: string | null }[];
}

export interface UltraSignUpPersonLink {
	personId: string;
	firstName: string;
	lastName: string;
}

const ID = /^[1-9][0-9]{0,11}$/;
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

function str(v: unknown): string {
	return typeof v === 'string' ? v.trim() : '';
}

/// Whether a name can be looked up: both halves present and within the cap.
/// Only the shape the form can see — the function decides the rest and answers
/// `ultrasignup_name_required` when it disagrees.
export function ultraSignUpNameReady(firstName: string, lastName: string): boolean {
	const ok = (s: string) => {
		const t = s.trim();
		return t.length > 0 && Array.from(t).length <= ULTRASIGNUP_NAME_MAX_LEN;
	};
	return ok(firstName) && ok(lastName);
}

/// The lookup's `candidates`, keeping only rows that could be stored: a person
/// without a usable id or name could never be linked, so offering them would
/// only fail one step later. Anything that is not the expected envelope is no
/// candidates rather than a guess.
export function parseUltraSignUpCandidates(payload: unknown): UltraSignUpCandidate[] {
	const rows = (payload as { candidates?: unknown } | null)?.candidates;
	if (!Array.isArray(rows)) return [];
	const out: UltraSignUpCandidate[] = [];
	for (const raw of rows) {
		if (!raw || typeof raw !== 'object') continue;
		const r = raw as Record<string, unknown>;
		const id = str(r.id);
		const firstName = str(r.firstName);
		const lastName = str(r.lastName);
		if (!ID.test(id) || !firstName || !lastName) continue;
		const age =
			typeof r.age === 'number' && Number.isInteger(r.age) && r.age > 0 ? r.age : null;
		const resultCount =
			typeof r.resultCount === 'number' && Number.isInteger(r.resultCount) && r.resultCount >= 0
				? r.resultCount
				: 0;
		const recentEvents = Array.isArray(r.recentEvents)
			? r.recentEvents.flatMap((e) => {
					const ev = (e ?? {}) as Record<string, unknown>;
					const name = str(ev.name);
					if (!name) return [];
					const date = str(ev.date);
					return [{ name, date: ISO_DATE.test(date) ? date : null }];
				})
			: [];
		out.push({ id, firstName, lastName, age, resultCount, recentEvents });
	}
	return out;
}

/// The link a picked candidate becomes. UltraSignup's own spelling of the name
/// is kept, not the runner's typing — it is the spelling the feed answered to.
export function linkFromCandidate(c: UltraSignUpCandidate): UltraSignUpPersonLink {
	return { personId: c.id, firstName: c.firstName, lastName: c.lastName };
}

/// The stored `integrations` row as a link, or null when there is none or it
/// is not a whole one.
export function ultraSignUpLinkFromRow(
	row: {
		external_id: string | null;
		external_first_name: string | null;
		external_last_name: string | null;
	} | null
): UltraSignUpPersonLink | null {
	if (!row) return null;
	const personId = str(row.external_id);
	const firstName = str(row.external_first_name);
	const lastName = str(row.external_last_name);
	if (!ID.test(personId) || !firstName || !lastName) return null;
	return { personId, firstName, lastName };
}

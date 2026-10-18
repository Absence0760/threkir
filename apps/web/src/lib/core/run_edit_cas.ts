// Compare-and-swap for the run-detail edit (decisions § 2120). Pure apart
// from the injected `io`, so the conflict rule is unit-tested without a
// Supabase stack; `updateRunMetadata` in `data.ts` supplies the queries.

import { applyRunMetadataPatch, normaliseRunMetadataFields } from './data_normalise';
import type { JsonObject } from '../types';

/// The columns of a `runs` row the edit reads and writes. `updated_at` is the
/// server's own stamp (migration 20270918000005), carried as the string the
/// server sent so the equality filter compares exactly what Postgres holds.
export type RunEditRow = {
	updated_at: string | null;
	metadata: JsonObject | null;
	is_dnf: boolean;
};

export type RunEditFields = { title?: string; notes?: string };

export type RunEditPatch = { metadata: JsonObject; is_dnf?: boolean };

export interface RunEditIo<R extends RunEditRow> {
	/// UPDATE the row only while its `updated_at` is still [base] (IS NULL for
	/// a null base), returning the rows written: empty when the row moved.
	swap(patch: RunEditPatch, base: string | null): Promise<R[]>;
	/// The row as the server holds it now, or null when it no longer exists.
	reload(): Promise<R | null>;
}

export type RunEditOutcome<R> =
	| { kind: 'saved'; row: R }
	/// Another writer changed a field this edit also changes. Nothing was
	/// written; [row] is the server's copy, for the runner to look at.
	| { kind: 'conflict'; row: R }
	| { kind: 'gone' };

/// The UPDATE body for an edit of [fields] (and of `is_dnf` when [isDnf] is
/// set) made on [row].
export function runEditPatch(
	row: RunEditRow,
	fields: RunEditFields,
	isDnf?: boolean,
): RunEditPatch {
	const metadata = applyRunMetadataPatch(row.metadata, fields);
	return isDnf === undefined ? { metadata } : { metadata, is_dnf: isDnf };
}

/// The subset of [fields] whose normalised value differs from [loaded]'s. The
/// dialog hands over every field it shows, edited or not, and writing an
/// untouched one back would revert whatever another writer put there.
export function changedEditFields(loaded: RunEditRow, fields: RunEditFields): RunEditFields {
	const normalised = normaliseRunMetadataFields(fields);
	const out: RunEditFields = {};
	for (const key of ['title', 'notes'] as const) {
		if (typeof fields[key] !== 'string') continue;
		if (!sameJson(loaded.metadata?.[key], normalised[key])) out[key] = fields[key];
	}
	return out;
}

/// Whether [fresh] differs from [loaded] in a field this edit writes. The
/// edit's text was typed against [loaded], so a change there is one the
/// runner has not seen and must not be written over.
export function editedFieldsMoved(
	loaded: RunEditRow,
	fresh: RunEditRow,
	fields: RunEditFields,
	isDnf?: boolean,
): boolean {
	for (const key of Object.keys(fields)) {
		if (!sameJson(loaded.metadata?.[key], fresh.metadata?.[key])) return true;
	}
	return isDnf !== undefined && loaded.is_dnf !== fresh.is_dnf;
}

/// Save a run edit made on [loaded], the copy the page last read, as a
/// compare-and-swap on its `updated_at`. Only the fields the runner changed
/// ([changedEditFields]) are written. When the row moved, it is read again:
/// a change to a field this edit does not touch (the page's own route link
/// or visibility switch, a job's stamp, another device's notes) is kept and
/// the edit is re-applied on top of it once; a change to a field this edit
/// does touch is reported as a conflict and nothing is written.
export async function saveRunEdit<R extends RunEditRow>(
	io: RunEditIo<R>,
	loaded: R,
	edited: RunEditFields,
	isDnf?: boolean,
): Promise<RunEditOutcome<R>> {
	const fields = changedEditFields(loaded, edited);
	if (Object.keys(fields).length === 0 && isDnf === undefined) {
		return { kind: 'saved', row: loaded };
	}
	const first = await io.swap(runEditPatch(loaded, fields, isDnf), loaded.updated_at);
	if (first.length > 0) return { kind: 'saved', row: first[0] };
	const fresh = await io.reload();
	if (!fresh) return { kind: 'gone' };
	if (editedFieldsMoved(loaded, fresh, fields, isDnf)) return { kind: 'conflict', row: fresh };
	const second = await io.swap(runEditPatch(fresh, fields, isDnf), fresh.updated_at);
	if (second.length > 0) return { kind: 'saved', row: second[0] };
	const latest = await io.reload();
	return latest ? { kind: 'conflict', row: latest } : { kind: 'gone' };
}

function sameJson(a: unknown, b: unknown): boolean {
	return JSON.stringify(a ?? null) === JSON.stringify(b ?? null);
}

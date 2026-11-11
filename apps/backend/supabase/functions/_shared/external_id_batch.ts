/// The last step of the race-results importer: a batch of `runs` rows about to
/// be inserted in ONE statement, each carrying an `external_id`, reconciled
/// against the ids the caller already has stored.
///
/// Comparing the batch against the rows ALREADY stored is half of it; the batch
/// also has to be compared against ITSELF. `runs_user_external_id` (migration
/// 20260528000003) is a per-user partial unique index over
/// `(user_id, external_id)`, so two rows in one batch carrying the same id raise
/// 23505 and take the WHOLE insert down, not the duplicate: the caller sees a
/// bare 500, nothing is imported, and a retry produces the same 500 because the
/// input has not changed.
///
/// A collision is not hypothetical. RunSignUp returns results under
/// `individual_results_sets[]` — one set per event, plus re-scored and
/// provisional sets — and `extractRunSignUpResults` flattens every one of them,
/// so a runner appearing in two sets yields two rows whose id is
/// `race:{name}:{date}:{bib}` with the same bib on both.
///
/// `skipped` is returned rather than left to the caller to subtract, because
/// that subtraction is the honesty half and it was written out twice. A row
/// dropped for being a duplicate of one already stored and a row dropped for
/// being a duplicate of its own batch-mate are the same answer to the caller:
/// it was not imported, and it was not lost either.
///
/// Keep this file pure — no `Deno.env`, no network.

export interface ImportBatchReconciliation<T> {
  /// The rows to insert, in input order. First occurrence of an id wins:
  /// both callers build their rows in upstream order.
  fresh: T[];
  /// How many input rows are not in `fresh`. Always `rows.length - fresh.length`.
  skipped: number;
}

export function reconcileImportBatch<T extends { external_id: string }>(
  rows: readonly T[],
  storedExternalIds: Iterable<string>,
): ImportBatchReconciliation<T> {
  const seen = new Set<string>(storedExternalIds);
  const fresh: T[] = [];
  for (const row of rows) {
    if (seen.has(row.external_id)) continue;
    seen.add(row.external_id);
    fresh.push(row);
  }
  return { fresh, skipped: rows.length - fresh.length };
}

// Dirty tracking for create/edit forms: a snapshot of the seeded field values
// captured once, compared against a freshly taken snapshot whenever someone
// asks. Pure — no Svelte, no DOM — so it runs under `npx tsx --test`.
//
// The snapshot is a function rather than a value because dirtiness is probed
// at NAVIGATION time, not at build time: a form's fields live in many separate
// runes and a value captured when the guard mounts is stale by the first
// keystroke (mobile hit the same wall from the other direction — see
// decisions.md § 478).

function deepEqual(a: unknown, b: unknown): boolean {
	if (a === b) return true;
	if (a === null || b === null) return false;
	if (typeof a !== 'object' || typeof b !== 'object') return false;
	if (Array.isArray(a) !== Array.isArray(b)) return false;
	if (Array.isArray(a) && Array.isArray(b)) {
		if (a.length !== b.length) return false;
		return a.every((v, i) => deepEqual(v, b[i]));
	}
	const ka = Object.keys(a as object);
	const kb = Object.keys(b as object);
	if (ka.length !== kb.length) return false;
	return ka.every(
		(k) =>
			Object.prototype.hasOwnProperty.call(b, k) &&
			deepEqual((a as Record<string, unknown>)[k], (b as Record<string, unknown>)[k]),
	);
}

function isRecord(v: unknown): v is Record<string, unknown> {
	return v !== null && typeof v === 'object' && !Array.isArray(v);
}

export interface DirtyTracker {
	/// Whether the form's fields differ from the last baseline.
	isDirty(): boolean;
	/// Re-take the baseline: the form's current values become the new "clean"
	/// state. For a successful save — the edits are persisted, so leaving
	/// loses nothing. Never for a seed that lands while the user may be
	/// typing: it would absorb their edits too and disarm the guard. Use
	/// `seed` for that.
	rebaseline(): void;
	/// Apply a default that arrives after the form is built (a preference
	/// fetch, an account currency) without it reading as a user edit. Only the
	/// fields `apply` itself changes move into the baseline, so an edit made
	/// before the seed landed stays dirty.
	seed(apply: () => void): void;
}

export function trackDirty<T>(snapshot: () => T): DirtyTracker {
	let baseline = snapshot();
	return {
		isDirty: () => !deepEqual(baseline, snapshot()),
		rebaseline: () => {
			baseline = snapshot();
		},
		seed: (apply) => {
			const before = snapshot();
			apply();
			const after = snapshot();
			if (isRecord(baseline) && isRecord(before) && isRecord(after)) {
				const next: Record<string, unknown> = { ...baseline };
				for (const k of Object.keys(after)) {
					if (!deepEqual(before[k], after[k])) next[k] = after[k];
				}
				baseline = next as T;
			} else if (deepEqual(baseline, before)) {
				// A snapshot that is not a record has no fields to separate, so the
				// seed is absorbed only onto a clean form; on a dirty one the prompt
				// errs toward asking.
				baseline = after;
			}
		},
	};
}

// Writes a built season (season_plan.ts) one plan at a time through the
// normal create path. Each plan is its own `create_training_plan`
// transaction, so a season is not atomic; what this guarantees instead is
// that a part-written season is always reported, with the plans created
// named and the rest resumable from where it stopped. Web-only: mobile keeps
// the same loop in its season screen.
//
// Only the first plan may overlap a plan the runner already has (the season
// starts while an old plan is running), so only it goes through the overlap
// dialog. The later plans are checked before anything is written: one that
// would land on an existing plan blocks the whole season up front rather than
// failing after the first plans exist.

import type { PlanOverlapChoice } from '../core/data';
import { attemptPlanCreate, type OverlapPlan } from './plan_overlap';
import type { SeasonPlanDraft } from './season_plan';

export interface SeasonCreated {
	index: number;
	id: string;
}

export type SeasonCreateOutcome =
	| { kind: 'done'; created: SeasonCreated[] }
	/// The first plan overlaps an active plan: ask, then call again with the choice.
	| { kind: 'overlap'; overlapping: OverlapPlan[] }
	| { kind: 'trimBlocked'; overlapping: OverlapPlan[] }
	/// A later plan would overlap an active plan; nothing was written.
	| { kind: 'blocked'; index: number; overlapping: OverlapPlan[] }
	/// Plans before `failedIndex` exist (`created`); it and the rest do not.
	| { kind: 'failed'; created: SeasonCreated[]; failedIndex: number; error: unknown };

export interface SeasonCreateDeps {
	create: (draft: SeasonPlanDraft, overlap: PlanOverlapChoice) => Promise<{ id: string }>;
	lookupOverlaps: (startIso: string, endIso: string) => Promise<OverlapPlan[]>;
}

export async function createSeasonPlans(
	drafts: SeasonPlanDraft[],
	options: { from: number; firstOverlap: PlanOverlapChoice; created: SeasonCreated[] },
	deps: SeasonCreateDeps
): Promise<SeasonCreateOutcome> {
	const created = [...options.created];
	if (options.from === 0) {
		for (let i = 1; i < drafts.length; i++) {
			const hits = await deps.lookupOverlaps(drafts[i].startDate, drafts[i].endDate);
			if (hits.length > 0) return { kind: 'blocked', index: i, overlapping: hits };
		}
	}
	for (let i = options.from; i < drafts.length; i++) {
		const draft = drafts[i];
		try {
			if (i === 0) {
				const outcome = await attemptPlanCreate(
					() => deps.create(draft, options.firstOverlap),
					() => deps.lookupOverlaps(draft.startDate, draft.endDate)
				);
				if (outcome.kind !== 'created') return outcome;
				created.push({ index: i, id: outcome.value.id });
			} else {
				const plan = await deps.create(draft, 'refuse');
				created.push({ index: i, id: plan.id });
			}
		} catch (error) {
			return { kind: 'failed', created, failedIndex: i, error };
		}
	}
	return { kind: 'done', created };
}

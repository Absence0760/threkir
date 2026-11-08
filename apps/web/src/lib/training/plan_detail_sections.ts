import type { DisclosureState } from '#lib/util/disclosure_state.ts';

/// The named expanders on `/plans/[id]`, in the order the page draws them,
/// and the state each opens in before the runner has chosen one.
///
/// Today's session, this week's strip, the adherence flags and any re-plan
/// preview lead the page unfolded; every section here starts shut, so the
/// current week is drawn once (the strip) rather than three times (strip,
/// calendar month, week list). A runner who opens one keeps it open: the
/// choice is remembered per account by `util/disclosure_state.ts`
/// (decisions § 2375). Mobile twin: `kPlanDetailDisclosureDefaults` in
/// `plan_detail_screen.dart`, held to this one by `plan_detail_sections.test.ts`.
export const PLAN_DETAIL_DISCLOSURE_SCOPE = 'plan_detail';

export const PLAN_DETAIL_DISCLOSURE_DEFAULTS: DisclosureState = {
	progress: false,
	rules: false,
	calendar: false,
	weeks: false,
	share: false
};

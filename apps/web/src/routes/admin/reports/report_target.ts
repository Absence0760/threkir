import type { MessageKey } from '#lib/i18n/messages.ts';
import type { ReportTargetKind } from '#lib/types.ts';
import { disputeTargetHref } from '#lib/social/organiser_dispute.ts';

interface ReportTargetSpec {
	labelKey: MessageKey;
	/** The page that shows the reported item, from the queue's `page_id` —
	 *  the item itself, or the run / club / route that carries it. Null when
	 *  no page can show it to a moderator. */
	path: ((pageId: string) => string) | null;
}

// A Record over the union, so a kind added to `reports.target_kind` fails
// to compile here until it has a label and a decision about its link.
export const REPORT_TARGETS: Record<ReportTargetKind, ReportTargetSpec> = {
	user: { labelKey: 'admin.reports.kind.user', path: (id) => `/u/${id}` },
	// /clubs/[slug] forwards a club uuid to its canonical slug URL.
	club: { labelKey: 'admin.reports.kind.club', path: (id) => `/clubs/${id}` },
	route: { labelKey: 'admin.reports.kind.route', path: (id) => `/routes/${id}` },
	run: { labelKey: 'admin.reports.kind.run', path: (id) => `/runs/${id}` },
	comment: { labelKey: 'admin.reports.kind.comment', path: (id) => `/runs/${id}` },
	club_post: { labelKey: 'admin.reports.kind.clubPost', path: (id) => `/clubs/${id}` },
	route_review: { labelKey: 'admin.reports.kind.routeReview', path: (id) => `/routes/${id}` },
	// The thread belongs to its two participants; the evidence is the
	// report-time snapshot on each report.
	direct_message: { labelKey: 'admin.reports.kind.directMessage', path: null },
	// Reported only as an organiser name dispute (decisions § 2441).
	training_plan: { labelKey: 'admin.reports.kind.trainingPlan', path: (id) => disputeTargetHref('training_plan', id) },
	gym_routine: { labelKey: 'admin.reports.kind.gymRoutine', path: (id) => disputeTargetHref('gym_routine', id) },
	challenge: { labelKey: 'admin.reports.kind.challenge', path: (id) => disputeTargetHref('challenge', id) },
	race_listing: { labelKey: 'admin.reports.kind.raceListing', path: (id) => disputeTargetHref('race_listing', id) },
};

export function reportTargetLabelKey(kind: ReportTargetKind): MessageKey | null {
	return REPORT_TARGETS[kind]?.labelKey ?? null;
}

export function reportTargetHref(kind: ReportTargetKind, pageId: string | null): string | null {
	const path = REPORT_TARGETS[kind]?.path;
	if (!path || !pageId) return null;
	return path(pageId);
}

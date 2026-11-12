// Organiser name disputes (issue #1363, decisions § 2441).
//
// submit_organiser_dispute is the gate: it refuses anyone who is not an active
// owner or admin of a verified, public, unhidden club. This module only decides
// what to offer and how to word it. Mobile's organiser_dispute.dart answers the
// same way.

import type { MessageKey } from '#lib/i18n/messages.ts';
import type { OrganiserDisputeTargetKind } from '#lib/types.ts';
import type { OrganiserClubCandidate } from '#lib/integrations/race_course_access.ts';

/** Mirrors resolve_organiser_dispute's default and bounds. */
export const DISPUTE_DEADLINE_DEFAULT_DAYS = 14;
export const DISPUTE_DEADLINE_MIN_DAYS = 1;
export const DISPUTE_DEADLINE_MAX_DAYS = 60;

/** Mirrors submit_organiser_dispute's notes cap. */
export const DISPUTE_NOTES_MAX = 600;

/** The clubs the runner may file for: their verified clubs other than the one
 *  the content belongs to (the RPC refuses disputing your own content). */
export function disputeClubsFor(
	myOrganiserClubs: readonly OrganiserClubCandidate[],
	targetClubId: string | null,
): OrganiserClubCandidate[] {
	return myOrganiserClubs.filter((c) => c.id !== targetClubId);
}

/** A whole number of days the RPC accepts, or null when the input is not one. */
export function deadlineDaysOrNull(raw: string | number | null | undefined): number | null {
	const n = typeof raw === 'number' ? raw : Number(String(raw ?? '').trim());
	if (!Number.isInteger(n)) return null;
	if (n < DISPUTE_DEADLINE_MIN_DAYS || n > DISPUTE_DEADLINE_MAX_DAYS) return null;
	return n;
}

export function deadlinePassed(deadlineAt: string | null, now: Date = new Date()): boolean {
	if (!deadlineAt) return false;
	const t = Date.parse(deadlineAt);
	return Number.isFinite(t) && t <= now.getTime();
}

const PATHS: Record<OrganiserDisputeTargetKind, (id: string) => string> = {
	club: (id) => `/clubs/${id}`,
	route: (id) => `/routes/${id}`,
	training_plan: (id) => `/plans/library/${id}`,
	gym_routine: (id) => `/gym/routines/library/${id}`,
	challenge: (id) => `/challenges/${id}`,
	race_listing: (id) => `/races/${id}`,
};

export function disputeTargetHref(kind: OrganiserDisputeTargetKind, id: string): string {
	return PATHS[kind](id);
}

const KIND_LABELS: Record<OrganiserDisputeTargetKind, MessageKey> = {
	club: 'admin.reports.kind.club',
	route: 'admin.reports.kind.route',
	training_plan: 'admin.reports.kind.trainingPlan',
	gym_routine: 'admin.reports.kind.gymRoutine',
	challenge: 'admin.reports.kind.challenge',
	race_listing: 'admin.reports.kind.raceListing',
};

export function disputeKindLabelKey(kind: OrganiserDisputeTargetKind): MessageKey {
	return KIND_LABELS[kind];
}

/** What each side reads for the latest action. The content's owner never sees
 *  a filing alone (my_organiser_disputes does not return one). */
export function disputeStatusKey(
	action: 'filed' | 'takedown' | 'rename_notice' | 'dismiss' | 'unhide',
	side: 'owner' | 'organiser',
): MessageKey {
	switch (action) {
		case 'filed':
			return 'organiserDispute.status.filed';
		case 'takedown':
			return side === 'owner' ? 'organiserDispute.status.hiddenOwner' : 'organiserDispute.status.hiddenOrganiser';
		case 'rename_notice':
			return side === 'owner' ? 'organiserDispute.status.renameOwner' : 'organiserDispute.status.renameOrganiser';
		case 'dismiss':
			return 'organiserDispute.status.dismissed';
		case 'unhide':
			return 'organiserDispute.status.restored';
	}
}

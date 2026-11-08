// Single source of truth for the notification → deep-link routing. The bell
// popover and the full inbox list both turn a NotificationView into the href a
// click should navigate to; the two switch statements used to be byte-identical
// copies, so a new NotificationKind meant editing the same routing table twice
// (the drift the notification_kind_coverage guard was pinning). Extracted here
// so the routing lives — and is unit-tested — once. verbFor stays per-component
// because its message keys are namespaced (notificationBell.* vs
// notificationsList.*); only the pure href mapping is shared.
//
// Typed against a structural subset of NotificationView so this module stays
// free of a runtime import from core/data.ts and remains tsx-testable.
export interface NotificationLinkInput {
	row: {
		kind: string;
		user_id: string;
		run_id: string | null;
		actor_id: string | null;
		event_id: string | null;
		plan_id: string | null;
		achievement_id: string | null;
		challenge_id: string | null;
	};
	event_club_slug: string | null;
	club_slug: string | null;
}

export function notificationLinkFor(item: NotificationLinkInput): string | null {
	const r = item.row;
	switch (r.kind) {
		case 'kudos':
		case 'comment':
		case 'comment_reply':
		case 'reaction':
		case 'comment_like':
		case 'mention':
		case 'run_completed':
			// None of these need be the recipient's run; /runs/[id] serves a
			// non-owner the shared view of any run their audience admits, inside
			// the app shell. /share/run is the logged-out page and would drop a
			// signed-in reader out of the app.
			return r.run_id ? `/runs/${r.run_id}` : null;
		case 'follow':
			return r.actor_id ? `/u/${r.actor_id}` : null;
		case 'follow_request':
			// Approve and decline live on the requests page; the requester's
			// own profile may be closed to the recipient.
			return '/follow-requests';
		case 'event_rsvp':
		case 'event_reminder':
		case 'event_waitlist_slot':
		case 'event_updated':
			return r.event_id && item.event_club_slug
				? `/clubs/${item.event_club_slug}/events/${r.event_id}`
				: null;
		case 'event_cancel':
			// A deleted event's notice links no event (it would have been
			// erased with it, 20271112000013); the club it belonged to is the
			// nearest page that still exists.
			if (r.event_id) {
				return item.event_club_slug ? `/clubs/${item.event_club_slug}/events/${r.event_id}` : null;
			}
			return item.club_slug ? `/clubs/${item.club_slug}` : null;
		case 'plan_update':
		case 'plan_assigned':
		case 'plan_ai_edit':
		case 'plan_change_request':
		case 'plan_change_decision':
		case 'workout_reminder':
			return r.plan_id ? `/plans/${r.plan_id}` : null;
		case 'message':
			return r.actor_id ? `/messages/${r.actor_id}` : null;
		case 'club_post':
		case 'club_join_approved':
		case 'club_join_request':
		case 'club_verification':
			// A request's approve and decline sit on the club page for its admins,
			// as does the verification card that says what changed and why.
			return item.club_slug ? `/clubs/${item.club_slug}` : null;
		case 'achievement':
			// The recipient earned it, so it is on their own Achievements tab —
			// even while private, where /share/badge would answer "not found".
			return r.achievement_id
				? `/u/${r.user_id}?tab=achievements&badge=${r.achievement_id}`
				: null;
		case 'personal_record':
			// The run's own page with the PR card open in the share editor.
			return r.run_id ? `/runs/${r.run_id}?share=pr` : null;
		case 'challenge_complete':
			return r.challenge_id ? `/challenges/${r.challenge_id}` : null;
		case 'data_export_ready':
			// The export card lives on Settings → Account, which mints the
			// signed download URL at the moment the subject asks for it. The
			// notification carries no URL of its own and must not: one minted
			// when the worker finished would already be expiring (decisions
			// § 717 + § 729). No FK — the export is not a `notifications`
			// column, so this is the one kind whose link needs no id.
			return '/settings/account';
		case 'refund_failed':
			// The event page carries the same explanation at length (§ 825).
			// A DONATION refund failure has no FK to carry and no surface to
			// point at — `donations` has no client SELECT policy — so it
			// degrades to null and the row stays a plain, unlinked message,
			// which is the whole message anyway.
			return r.event_id && item.event_club_slug
				? `/clubs/${item.event_club_slug}/events/${r.event_id}`
				: null;
		case 'content_hidden':
			return null;
		default:
			return null;
	}
}

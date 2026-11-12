// The Coach's plan-edit handoff link, read back out of its reply so the web
// chat can show the change as a reviewable card (decisions § 2230).
//
// `planEditHandoffAddendum` tells the model to write exactly one
// `[Adjust my plan](/plans/<plan id>?adjust=<request>)` link. The link is
// untrusted model output, so this only ever yields a plan id shaped like a
// uuid and a request string, nothing else: the card sends both to
// `/api/coach/plan-edit`, which reads the plan under the runner's own JWT and
// validates every operation against it (`validatePlanEditOps`), so an id the
// runner does not own is a 404 there. Mobile keeps the same link and opens it
// on web (`coachPlanAdjustWebUri`).

import { MAX_PLAN_EDIT_REQUEST_CHARS } from '../training/plan_edit/ops';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const LINK_TARGET = /\]\(\s*<?(\/plans\/[^)\s>]+)>?(?:\s+"[^"]*")?\s*\)/g;

export interface PlanEditHandoff {
	planId: string;
	request: string;
}

/// The first plan-edit link in a Coach reply, or null. Only a root-relative
/// `/plans/<uuid>` path with a non-empty `adjust` parameter counts; the
/// request is trimmed and cut to the length the endpoint accepts.
export function planEditHandoff(content: string): PlanEditHandoff | null {
	for (const match of content.matchAll(LINK_TARGET)) {
		let url: URL;
		try {
			url = new URL(match[1], 'https://app.invalid');
		} catch {
			continue;
		}
		if (url.origin !== 'https://app.invalid') continue;
		const parts = url.pathname.split('/');
		if (parts.length !== 3 || parts[1] !== 'plans' || !UUID.test(parts[2])) continue;
		const request = (url.searchParams.get('adjust') ?? '').trim().slice(0, MAX_PLAN_EDIT_REQUEST_CHARS);
		if (!request) continue;
		return { planId: parts[2].toLowerCase(), request };
	}
	return null;
}

/// `club-verification-recheck` — the scheduled re-check of verified clubs'
/// domain proof (issue #1190 § 2, decisions § 2398).
///
/// pg_cron (`invoke_club_verification_recheck`, through pg_net) calls it every
/// hour with the CRON_SECRET bearer. Each run takes up to ten approvals proven
/// by DNS or by the `.well-known` file that have not been checked for 20
/// hours (`club_verifications_due_for_recheck`), runs the same checks the
/// owner's "Check now" runs, and records each result. Three failed re-checks
/// in a row lapse the approval and drop the badge — in SQL, so the count and
/// the lapse are one transaction.
///
/// A result that says nothing about the domain (our resolver down, or the
/// deadline spent on our side for both checks) is skipped, not recorded, so
/// an outage here never counts against a club.
///
/// Gates, fail-closed: 503 when CRON_SECRET is unset or short, 403 on a
/// missing or wrong bearer (rate-limited per IP only on a wrong one, as the
/// other cron functions do).

import type { DbClient } from '../_shared/database.ts';
import { discardBody } from '../_shared/body_limit.ts';
import { checkRateLimit, ipBucketKey } from '../_shared/rate_limit.ts';
import { cronGate } from '../events-refund-sweep/lib.ts';
import { checkDomainProof, isInconclusive, type ProofDeps } from '../_shared/domain_proof.ts';
import { recordArgs } from '../club-verification/handler.ts';

export const RECHECKS_PER_RUN = 10;

export interface RecheckDeps {
	getEnv: (name: string) => string | undefined;
	serviceClient: () => DbClient;
	proof: ProofDeps;
}

export function makeRecheckHandler(deps: RecheckDeps): (req: Request) => Promise<Response> {
	return async (req: Request) => {
		discardBody(req);

		const gate = cronGate(deps.getEnv('CRON_SECRET'), req.headers.get('Authorization'));
		if (gate === 'not_configured') return Response.json({ error: 'cron_not_configured' }, { status: 503 });
		if (gate !== 'ok') {
			if (gate === 'mismatch') {
				const denied = await checkRateLimit(
					deps.serviceClient(),
					await ipBucketKey(req),
					'club-verification-recheck:anon',
					60,
					3600,
					{ failClosed: true },
				);
				if (denied) return denied;
			}
			return Response.json({ error: 'forbidden' }, { status: 403 });
		}

		const db = deps.serviceClient();
		const { data: due, error } = await db.rpc('club_verifications_due_for_recheck', { p_limit: RECHECKS_PER_RUN });
		if (error) {
			console.error('club-verification-recheck: due list failed', { code: error.code });
			return Response.json({ error: 'due_list_failed' }, { status: 500 });
		}

		const summary = { checked: 0, verified: 0, failed: 0, lapsed: 0, skipped: 0, errors: 0 };
		// Sequential: each check already has its own deadline, and ten in a row
		// fit inside the cron call's 60 s with room to spare.
		for (const row of due ?? []) {
			const result = await checkDomainProof(row.domain, row.token, deps.proof);
			if (isInconclusive(result)) {
				summary.skipped++;
				continue;
			}
			const args = recordArgs(result);
			const { data: status, error: recordError } = await db.rpc('record_club_verification_check', {
				p_request_id: row.id,
				p_method: args.method,
				p_ok: args.ok,
				p_detail: args.detail,
			});
			if (recordError) {
				console.error('club-verification-recheck: record failed', { code: recordError.code });
				summary.errors++;
				continue;
			}
			summary.checked++;
			if (status === 'verified') summary.verified++;
			else if (status === 'lapsed') summary.lapsed++;
			else summary.failed++;
		}
		return Response.json(summary, { status: summary.errors > 0 ? 500 : 200 });
	};
}

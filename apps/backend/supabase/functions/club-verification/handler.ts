/// `club-verification` — runs the DNS TXT and `.well-known` proof checks for a
/// club verification request (issue #1190 § 2, decisions § 2398).
///
/// POST `{ request_id }` with the caller's session. The request is read with
/// the caller's own client, so RLS decides who may check it: the club's owner
/// and active admins. The checks themselves live in `_shared/domain_proof.ts`
/// (DoH lookups, the SSRF-fenced file fetch). The result is written by
/// `record_club_verification_check`, which only service_role may call, so a
/// client can never record a proof it did not pass.
///
/// A pass records the proof on the request; a reviewer still approves it.
/// Rate-limited per user (fail-closed), because each call makes outbound
/// requests to a host the caller chose.
///
/// The handler takes its database, network and rate-limit access as injected
/// deps so `handler.test.ts` drives every branch without a stack; `index.ts`
/// is the wiring.

import { readJsonWithLimit } from '../_shared/body_limit.ts';
import { checkDomainProof, type DomainProofResult, type ProofDeps } from '../_shared/domain_proof.ts';

export const CHECKS_PER_HOUR = 12;

export interface CheckableRequest {
	id: string;
	domain: string;
	token: string;
	status: string;
}

export interface ClubVerificationDeps {
	authenticate(): Promise<string | null>;
	rateLimit(userId: string): Promise<Response | null>;
	/// The request as the CALLER may see it, or null.
	loadRequest(requestId: string): Promise<CheckableRequest | null>;
	record(requestId: string, result: DomainProofResult): Promise<string | null>;
	proof: ProofDeps;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function makeClubVerificationHandler(deps: ClubVerificationDeps): (req: Request) => Promise<Response> {
	return async (req: Request) => {
		if (req.method !== 'POST') return Response.json({ error: 'method_not_allowed' }, { status: 405 });

		const userId = await deps.authenticate();
		if (!userId) return Response.json({ error: 'unauthorized' }, { status: 401 });

		const parsed = await readJsonWithLimit<{ request_id?: unknown }>(req, 1024);
		if ('tooLarge' in parsed) return parsed.tooLarge;
		const requestId = parsed.body?.request_id;
		if (typeof requestId !== 'string' || !UUID_RE.test(requestId)) {
			return Response.json({ error: 'invalid_request_id' }, { status: 400 });
		}

		const denied = await deps.rateLimit(userId);
		if (denied) return denied;

		const request = await deps.loadRequest(requestId);
		if (!request) return Response.json({ error: 'not_found' }, { status: 404 });
		if (request.status !== 'pending') return Response.json({ error: 'not_pending' }, { status: 409 });

		const result = await checkDomainProof(request.domain, request.token, deps.proof);
		const status = await deps.record(request.id, result);
		if (status === null) return Response.json({ error: 'record_failed' }, { status: 500 });

		return Response.json({ status, method: result.method, checks: result.checks });
	};
}

/// What `record_club_verification_check` is told: the method that passed, or
/// a miss reported against DNS with both outcomes in the detail.
export function recordArgs(result: DomainProofResult): { method: 'dns_txt' | 'well_known'; ok: boolean; detail: string } {
	return { method: result.method ?? 'dns_txt', ok: result.verified, detail: result.detail };
}

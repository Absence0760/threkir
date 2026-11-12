/// Club verification requests (issue #1190 § 2, decisions § 2398): the
/// vocabularies, the proof instructions a club owner follows, and the reading
/// of a club's request history. The network calls live in core/data.ts; this
/// module is pure so it is unit-testable.

import type { MessageKey } from '../i18n/messages';

/// `club_verification_requests.status` — `check_constraint_unions.mjs` pins
/// this list to the CHECK.
export const CLUB_VERIFICATION_STATUSES = ['pending', 'approved', 'rejected', 'revoked', 'lapsed', 'withdrawn'] as const;
export type ClubVerificationStatus = (typeof CLUB_VERIFICATION_STATUSES)[number];

/// `club_verification_requests.proof_method`.
export const CLUB_VERIFICATION_PROOF_METHODS = ['dns_txt', 'well_known', 'email', 'manual'] as const;
export type ClubVerificationProofMethod = (typeof CLUB_VERIFICATION_PROOF_METHODS)[number];

/// `club_verification_audit.action`.
export const CLUB_VERIFICATION_AUDIT_ACTIONS = [
	'submit',
	'withdraw',
	'email_sent',
	'proof_verified',
	'proof_failed',
	'approve',
	'reject',
	'revoke',
	'lapse',
] as const;
export type ClubVerificationAuditAction = (typeof CLUB_VERIFICATION_AUDIT_ACTIONS)[number];

/// The reason codes a system lapse records in `close_reason`. A revoke's
/// reason is the reviewer's own text.
export const LAPSE_REASONS = ['proof_missing', 'name_changed', 'slug_changed', 'domain_changed'] as const;
export type LapseReason = (typeof LAPSE_REASONS)[number];

export interface ClubVerificationRequest {
	id: string;
	club_id: string;
	organisation: string;
	domain: string;
	note: string | null;
	token: string;
	status: ClubVerificationStatus;
	proof_method: ClubVerificationProofMethod | null;
	proof_verified_at: string | null;
	proof_detail: string | null;
	last_checked_at: string | null;
	decision_reason: string | null;
	close_reason: string | null;
	created_at: string;
	decided_at: string | null;
	closed_at: string | null;
}

/// The columns the club card reads.
export const CLUB_VERIFICATION_REQUEST_COLUMNS =
	'id, club_id, organisation, domain, note, token, status, proof_method, proof_verified_at, proof_detail, last_checked_at, decision_reason, close_reason, created_at, decided_at, closed_at';

export const TXT_LABEL = '_threkir-verification';
export const WELL_KNOWN_PATH = '/.well-known/threkir-verification';
export const PROOF_PREFIX = 'threkir-verification=';
/// `send_club_verification_email` allows three a request a day.
export const EMAILS_PER_DAY = 3;

export interface ProofInstructions {
	txtName: string;
	txtValue: string;
	fileUrl: string;
	fileBody: string;
}

/// What the owner publishes. The same names `_shared/domain_proof.ts` reads.
export function proofInstructions(domain: string, token: string): ProofInstructions {
	return {
		txtName: `${TXT_LABEL}.${domain}`,
		txtValue: `${PROOF_PREFIX}${token}`,
		fileUrl: `https://${domain}${WELL_KNOWN_PATH}`,
		fileBody: `${PROOF_PREFIX}${token}`,
	};
}

/// The part of an address before the @, as `send_club_verification_email`
/// accepts it: letters, digits and `._+-`, not starting or ending with a
/// separator, no `..`. Trimmed and lower-cased; null when unusable.
export function normaliseEmailLocalPart(raw: string): string | null {
	const v = raw.trim().toLowerCase();
	if (!/^[a-z0-9]([a-z0-9._+-]{0,62}[a-z0-9])?$/.test(v) || v.includes('..')) return null;
	return v;
}

export interface ClubVerificationState {
	/// The request in force: pending, or the approval of a verified club.
	live: ClubVerificationRequest | null;
	/// The most recent request that ended, for "your last request …".
	lastClosed: ClubVerificationRequest | null;
}

/// Reads a club's requests (any order) into the live one and the last closed
/// one. A closed request older than the live one is history, not news.
export function readVerificationState(rows: readonly ClubVerificationRequest[]): ClubVerificationState {
	const sorted = [...rows].sort((a, b) => b.created_at.localeCompare(a.created_at) || b.id.localeCompare(a.id));
	const live = sorted.find((r) => r.status === 'pending' || r.status === 'approved') ?? null;
	const lastClosed = live ? null : (sorted.find((r) => r.status !== 'pending' && r.status !== 'approved') ?? null);
	return { live, lastClosed };
}

/// Whether a lapse reason is one of the system codes (so it has its own copy)
/// rather than free text.
export function isLapseReason(v: string | null): v is LapseReason {
	return v !== null && (LAPSE_REASONS as readonly string[]).includes(v);
}

/// The i18n key for an error the verification RPCs raise. Each RPC raises a
/// stable code as its message; anything else is null, and the data layer
/// passes the failure on unchanged for `errorCopy` to classify.
const ERROR_KEYS: Record<string, MessageKey> = {
	club_website_required: 'clubVerification.websiteRequired',
	organisation_required: 'clubVerification.organisationRequired',
	request_already_pending: 'clubVerification.alreadyPending',
	club_already_verified: 'clubVerification.alreadyVerified',
	request_not_pending: 'clubVerification.notPending',
	invalid_email_local_part: 'clubVerification.emailInvalid',
	email_rate_limited: 'clubVerification.emailRateLimited',
	manual_review_note_required: 'admin.clubVerification.approveNoteRequired',
	club_website_changed: 'admin.clubVerification.websiteChanged',
	reason_required: 'admin.clubVerification.reasonRequired',
};

export function verificationErrorKey(err: unknown): MessageKey | null {
	const raw = err !== null && typeof err === 'object' ? (err as { message?: unknown }).message : err;
	const msg = typeof raw === 'string' ? raw : '';
	for (const [code, key] of Object.entries(ERROR_KEYS)) {
		if (msg.includes(code)) return key;
	}
	return null;
}

/// The `club-verification` Edge Function's per-method outcomes.
export type ProofOutcome =
	| 'ok'
	| 'not_found'
	| 'unreachable'
	| 'timeout'
	| 'resolver_error'
	| 'refused_address'
	| 'refused_redirect'
	| 'too_large';

export interface ProofCheckResult {
	status: 'verified' | 'not_found' | 'not_live';
	method: 'dns_txt' | 'well_known' | null;
	checks: { dns_txt: ProofOutcome; well_known: ProofOutcome };
}

/// The one message a check result earns: found; refused (the file is behind
/// a redirect off the domain, an address we will not fetch, or too big);
/// didn't run (our side); or not found yet.
export function checkResultKey(r: ProofCheckResult): string {
	if (r.status === 'verified') return 'clubVerification.checkVerified';
	const outcomes = [r.checks.dns_txt, r.checks.well_known];
	if (outcomes.some((o) => o === 'refused_address' || o === 'refused_redirect' || o === 'too_large')) {
		return 'clubVerification.checkRefused';
	}
	if (outcomes.every((o) => o === 'resolver_error' || o === 'timeout')) return 'clubVerification.checkFailed';
	return 'clubVerification.checkNotFound';
}

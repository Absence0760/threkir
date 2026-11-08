// Unit suite for club_verification.ts (issue #1190 § 2, decisions § 2398).

import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import {
	checkResultKey,
	type ClubVerificationRequest,
	isLapseReason,
	normaliseEmailLocalPart,
	proofInstructions,
	readVerificationState,
	verificationErrorKey,
} from './club_verification';

function req(over: Partial<ClubVerificationRequest>): ClubVerificationRequest {
	return {
		id: 'r1',
		club_id: 'c1',
		organisation: 'Org',
		domain: 'race.example.org',
		note: null,
		token: '0123456789abcdef0123456789abcdef',
		status: 'pending',
		proof_method: null,
		proof_verified_at: null,
		proof_detail: null,
		last_checked_at: null,
		decision_reason: null,
		close_reason: null,
		created_at: '2026-11-01T00:00:00Z',
		decided_at: null,
		closed_at: null,
		...over,
	};
}

test('the proof instructions name the record and the file the Edge Function reads', () => {
	const p = proofInstructions('race.example.org', 'abc');
	assert.equal(p.txtName, '_threkir-verification.race.example.org');
	assert.equal(p.txtValue, 'threkir-verification=abc');
	assert.equal(p.fileUrl, 'https://race.example.org/.well-known/threkir-verification');
	assert.equal(p.fileBody, 'threkir-verification=abc');
});

test('an email local part is the bit before the @ and nothing else', () => {
	assert.equal(normaliseEmailLocalPart(' Hostmaster '), 'hostmaster');
	assert.equal(normaliseEmailLocalPart('first.last+race'), 'first.last+race');
	assert.equal(normaliseEmailLocalPart('a@b.com'), null);
	assert.equal(normaliseEmailLocalPart('.dot'), null);
	assert.equal(normaliseEmailLocalPart('two..dots'), null);
	assert.equal(normaliseEmailLocalPart(''), null);
	assert.equal(normaliseEmailLocalPart('x'.repeat(65)), null);
});

test('the live request wins over history, and history shows only when nothing is live', () => {
	const closed = req({ id: 'old', status: 'rejected', created_at: '2026-10-01T00:00:00Z', decided_at: '2026-10-02T00:00:00Z' });
	const pending = req({ id: 'new', status: 'pending', created_at: '2026-11-01T00:00:00Z' });
	assert.deepEqual(readVerificationState([closed, pending]), { live: pending, lastClosed: null });
	assert.deepEqual(readVerificationState([closed]), { live: null, lastClosed: closed });
	assert.deepEqual(readVerificationState([]), { live: null, lastClosed: null });
});

test('the most recent closed request is the one reported', () => {
	const a = req({ id: 'a', status: 'lapsed', created_at: '2026-09-01T00:00:00Z' });
	const b = req({ id: 'b', status: 'withdrawn', created_at: '2026-10-01T00:00:00Z' });
	assert.equal(readVerificationState([a, b]).lastClosed?.id, 'b');
});

test('lapse codes are told apart from a reviewer\'s free text', () => {
	assert.ok(isLapseReason('domain_changed'));
	assert.ok(!isLapseReason('Impersonation report upheld'));
	assert.ok(!isLapseReason(null));
});

test('RPC error codes map to their copy, unknown errors to none', () => {
	assert.equal(verificationErrorKey(new Error('email_rate_limited')), 'clubVerification.emailRateLimited');
	assert.equal(verificationErrorKey(new Error('club_website_required')), 'clubVerification.websiteRequired');
	assert.equal(verificationErrorKey(new Error('manual_review_note_required')), 'admin.clubVerification.approveNoteRequired');
	assert.equal(verificationErrorKey(new Error('something else')), null);
});

test('a check result earns one message', () => {
	const base = { method: null, checks: { dns_txt: 'not_found', well_known: 'not_found' } } as const;
	assert.equal(checkResultKey({ ...base, status: 'verified', method: 'dns_txt' }), 'clubVerification.checkVerified');
	assert.equal(checkResultKey({ ...base, status: 'not_found' }), 'clubVerification.checkNotFound');
	assert.equal(
		checkResultKey({ status: 'not_found', method: null, checks: { dns_txt: 'not_found', well_known: 'refused_redirect' } }),
		'clubVerification.checkRefused',
	);
	assert.equal(
		checkResultKey({ status: 'not_found', method: null, checks: { dns_txt: 'resolver_error', well_known: 'timeout' } }),
		'clubVerification.checkFailed',
	);
});

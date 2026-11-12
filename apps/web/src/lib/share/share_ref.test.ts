import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	isLikelyBot,
	isTrackedShareKind,
	parseShareRef,
	shareRefFromSearch,
	shareSignupHref,
	signupShareFromTarget,
	withShareRef,
} from './share_ref.js';

const REF = 'a1b2c3d4e5';
const ID = '0b9f3c2e-1111-4222-8333-944455556666';

test('parseShareRef accepts exactly ten lowercase letters and digits', () => {
	assert.equal(parseShareRef(REF), REF);
	for (const bad of ['A1B2C3D4E5', 'a1b2c3d4e', 'a1b2c3d4e5f', 'a1b2c3d4e_', '', null, undefined, 42]) {
		assert.equal(parseShareRef(bad), null, String(bad));
	}
});

test('shareRefFromSearch reads a valid ref and drops anything else', () => {
	assert.equal(shareRefFromSearch(`?ref=${REF}`), REF);
	assert.equal(shareRefFromSearch(`?x=1&ref=${REF}`), REF);
	assert.equal(shareRefFromSearch('?ref=<script>'), null);
	assert.equal(shareRefFromSearch(''), null);
	assert.equal(shareRefFromSearch(null), null);
});

test('withShareRef adds the ref to an absolute URL or a path, keeping query and hash', () => {
	assert.equal(withShareRef(`https://threkir.com/share/plan/${ID}`, REF), `https://threkir.com/share/plan/${ID}?ref=${REF}`);
	assert.equal(withShareRef('/share/plan/x?a=1#top', REF), `/share/plan/x?a=1&ref=${REF}#top`);
	assert.equal(withShareRef('/share/plan/x?ref=zzzzzzzzzz', REF), `/share/plan/x?ref=${REF}`);
});

test('withShareRef leaves the URL alone without a valid ref', () => {
	assert.equal(withShareRef('/share/plan/x', null), '/share/plan/x');
	assert.equal(withShareRef('/share/plan/x', 'NOT VALID'), '/share/plan/x');
});

test('signupShareFromTarget reads a share page or the plan library preview', () => {
	assert.deepEqual(signupShareFromTarget(`/share/challenge/${ID}?ref=${REF}`), { kind: 'challenge', id: ID, ref: REF });
	assert.deepEqual(signupShareFromTarget(`/plans/library/${ID.toUpperCase()}?ref=${REF}`), { kind: 'plan', id: ID, ref: REF });
	assert.deepEqual(signupShareFromTarget(`/share/profile/${ID}?ref=${REF}`), { kind: 'profile', id: ID, ref: REF });
});

test('signupShareFromTarget refuses a target without a ref, an untracked kind or a non-uuid', () => {
	assert.equal(signupShareFromTarget(`/share/plan/${ID}`), null);
	assert.equal(signupShareFromTarget(`/share/club/${ID}?ref=${REF}`), null);
	assert.equal(signupShareFromTarget(`/share/plan/not-a-uuid?ref=${REF}`), null);
	assert.equal(signupShareFromTarget(`/share/plan/${ID}/extra?ref=${REF}`), null);
	assert.equal(signupShareFromTarget(`https://evil.example/share/plan/${ID}?ref=${REF}`), null);
	assert.equal(signupShareFromTarget(null), null);
});

test('isTrackedShareKind names the five kinds the creator view counts', () => {
	for (const k of ['plan', 'challenge', 'profile', 'session', 'workout']) assert.ok(isTrackedShareKind(k));
	for (const k of ['club', 'event', 'race', 'run', '']) assert.ok(!isTrackedShareKind(k));
});

test('isLikelyBot flags a self-named crawler and an automated browser, not a person', () => {
	assert.ok(isLikelyBot('Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)'));
	assert.ok(isLikelyBot('facebookexternalhit/1.1'));
	assert.ok(isLikelyBot('Mozilla/5.0 HeadlessChrome/120.0'));
	assert.ok(isLikelyBot('Mozilla/5.0 (iPhone)', true));
	assert.ok(!isLikelyBot('Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Safari/604.1'));
	assert.ok(!isLikelyBot(null));
});

test('shareSignupHref returns to the share page with the ref, or is the plain sign-up', () => {
	assert.equal(
		shareSignupHref(`/share/session/${ID}`, REF),
		`/login?signup=1&return_to=${encodeURIComponent(`/share/session/${ID}?ref=${REF}`)}`,
	);
	assert.equal(shareSignupHref(`/share/session/${ID}`, null), '/login?signup=1');
	assert.equal(shareSignupHref(`/share/session/${ID}`, 'bad'), '/login?signup=1');
});
